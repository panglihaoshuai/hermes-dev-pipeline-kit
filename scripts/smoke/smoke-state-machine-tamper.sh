#!/usr/bin/env bash
# smoke-state-machine-tamper.sh — replay-run must detect event/artifact tampering.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-v04-tamper.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/project"
cat > "$TMP_ROOT/task.md" <<'EOF'
Create a minimal S-level command evidence run.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "v04-tamper-smoke" \
  --task-type "smoke" \
  --mode "auto_run" \
  --scale "S" \
  --project "v04-tamper-smoke")"

cat > "$TMP_ROOT/project/test.js" <<'EOF'
if (1 + 1 !== 2) {
  throw new Error("math failed");
}
EOF

"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "green" \
  --phase "GREEN" \
  -- node test.js

"$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
"$REPO_ROOT/scripts/replay-run.sh" "$RUN_DIR" >/dev/null

printf '\n# tampered\n' >> "$RUN_DIR/raw/command-log.jsonl"

if "$REPO_ROOT/scripts/replay-run.sh" "$RUN_DIR" >/dev/null 2>&1; then
  echo "FAIL: replay-run should fail after command-log tampering"
  exit 1
fi

echo "smoke-state-machine-tamper: PASS"
