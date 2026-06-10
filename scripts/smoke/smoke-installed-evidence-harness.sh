#!/usr/bin/env bash
# smoke-installed-evidence-harness.sh — Verify installed skill bin scripts work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_HOME="$(mktemp -d /tmp/hermes-installed-harness-home.XXXXXX)"
TMP_WORK="$(mktemp -d /tmp/hermes-installed-harness-work.XXXXXX)"

cleanup() {
  rm -rf "$TMP_HOME" "$TMP_WORK"
}
trap cleanup EXIT

mkdir -p "$TMP_HOME/.claude"
cat > "$TMP_HOME/.claude/CLAUDE.md" <<'EOF'
# CLAUDE

Hermes Delegation Protocol
EOF

HOME="$TMP_HOME" bash "$REPO_ROOT/scripts/install.sh" --yes >/tmp/hermes-installed-harness-install.out

BIN="$TMP_HOME/.hermes/skills/software-development/dev-pipeline-orchestrator/bin"

for script in append-event.sh transition-check.sh replay-run.sh run-init.sh record-command.sh drive-s-run.sh generate-run-state.sh final-report.sh policy-check.sh fail-run.sh; do
  if [[ ! -x "$BIN/$script" ]]; then
    echo "FAIL: installed $script missing or not executable at $BIN/$script"
    exit 1
  fi
done

cat > "$TMP_WORK/task.md" <<'EOF'
Installed harness smoke: implement add.js with RED/GREEN evidence.
EOF

RUN_DIR="$("$BIN/run-init.sh" \
  --root "$TMP_WORK" \
  --task-file "$TMP_WORK/task.md" \
  --run-id "installed-evidence-harness-smoke" \
  --task-type "bugfix" \
  --mode "auto_run" \
  --scale "M" \
  --project "installed-evidence-harness-smoke")"

"$BIN/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type INTAKE_RECORDED \
  --actor Hermes \
  --state-after INTAKE_RECORDED \
  --artifact task.md >/dev/null

"$BIN/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type WORK_ORDER_CREATED \
  --actor Hermes \
  --state-after WORK_ORDER_CREATED \
  --artifact work-orders/WO-1.json >/dev/null

"$BIN/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_DELEGATED \
  --actor Hermes \
  --state-after CLAUDECODE_DELEGATED \
  --artifact work-orders/WO-1.json >/dev/null

mkdir -p "$TMP_WORK/project"
cat > "$TMP_WORK/project/test.js" <<'EOF'
const { add } = require("./add");

if (add(2, 2) !== 4) {
  throw new Error("add(2, 2) should equal 4");
}
EOF

if "$BIN/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_WORK/project" \
  --step-id "red" \
  --phase "RED" \
  -- node test.js; then
  echo "FAIL: RED phase should fail before add.js exists"
  exit 1
fi

cat > "$TMP_WORK/project/add.js" <<'EOF'
function add(a, b) {
  return a + b;
}

module.exports = { add };
EOF

"$BIN/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_WORK/project" \
  --step-id "green" \
  --phase "GREEN" \
  -- node test.js

cat > "$RUN_DIR/raw/files-touched.txt" <<'EOF'
add.js
test.js
EOF

cat > "$RUN_DIR/raw/claudecode-result.json" <<'EOF'
{
  "work_order_id": "WO-1",
  "status": "completed",
  "required_matt_skill": "tdd",
  "matt_evidence": {
    "red": "node test.js failed before add.js existed",
    "red_exit_code": 1,
    "red_not_applicable_reason": "",
    "green": "node test.js passed after add.js implementation",
    "green_exit_code": 0,
    "commands": [
      "node test.js",
      "node test.js"
    ]
  },
  "files_touched": [
    "add.js",
    "test.js"
  ],
  "commands_run": [
    "node test.js",
    "node test.js"
  ],
  "blocked": false,
  "notes": "Installed harness smoke result contract. Acceptance is intentionally absent."
}
EOF

"$BIN/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_RESULT_RECORDED \
  --actor ClaudeCode \
  --state-after CLAUDECODE_RESULT_RECORDED \
  --artifact raw/claudecode-result.json >/dev/null

"$BIN/generate-run-state.sh" "$RUN_DIR" >/dev/null
"$BIN/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" >/dev/null
"$BIN/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$TMP_WORK/final-report.out"

if ! grep -q "负责人摘要" "$TMP_WORK/final-report.out"; then
  echo "FAIL: installed final-report.sh output should contain Chinese owner summary"
  exit 1
fi

echo "smoke-installed-evidence-harness: PASS"
