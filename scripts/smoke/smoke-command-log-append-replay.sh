#!/usr/bin/env bash
# smoke-command-log-append-replay.sh — command-log appends must not break replay.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-v04-command-log-append.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/project"
cat > "$TMP_ROOT/task.md" <<'EOF'
Verify append-safe command evidence.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "v04-command-log-append" \
  --task-type "smoke" \
  --mode "auto_run" \
  --scale "S" \
  --project "v04-command-log-append")"

set +e
"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "red" \
  --phase "RED" \
  -- node -e "process.exit(1)" >/dev/null
RED_EXIT=$?
set -e
if [[ "$RED_EXIT" -eq 0 ]]; then
  echo "FAIL: RED command should fail"
  exit 1
fi

"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "green" \
  --phase "GREEN" \
  -- node -e "console.log('green')"

"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "verify" \
  --phase "VERIFY" \
  -- node -e "console.log('verify')"

test "$(wc -l < "$RUN_DIR/raw/command-log.jsonl" | tr -d ' ')" = "3"
test -f "$RUN_DIR/raw/commands/cmd-0001.json"
test -f "$RUN_DIR/raw/commands/cmd-0002.json"
test -f "$RUN_DIR/raw/commands/cmd-0003.json"

if grep -A1 -B1 '"event_type":"COMMAND_RECORDED' "$RUN_DIR/events.jsonl" | grep -q 'raw/command-log.jsonl'; then
  echo "FAIL: command events must not hash raw/command-log.jsonl"
  exit 1
fi

"$REPO_ROOT/scripts/replay-run.sh" "$RUN_DIR" >/dev/null

python3 - "$RUN_DIR/generated/replay-result.json" <<'PY'
import json
import pathlib
import sys

replay = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert replay["replay_pass"] is True
assert replay["failures"] == []
PY

printf '\n' >> "$RUN_DIR/raw/commands/cmd-0002.json"
if "$REPO_ROOT/scripts/replay-run.sh" "$RUN_DIR" >/dev/null 2>&1; then
  echo "FAIL: replay-run should fail after immutable command record tampering"
  exit 1
fi

echo "smoke-command-log-append-replay: PASS"
