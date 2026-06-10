#!/usr/bin/env bash
# smoke-s-level-driver.sh — Verify S-level auto_run reaches final report.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="/tmp/hermes-v04-s-level-driver-smoke"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT/project"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/task.md" <<'EOF'
Implement a tiny addition function and prove the S-level driver reaches final report.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "v04-s-level-driver-success" \
  --task-type "smoke" \
  --mode "auto_run" \
  --scale "S" \
  --project "v04-s-level-driver-success")"

"$REPO_ROOT/scripts/transition-check.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLASSIFICATION_RECORDED \
  --state-after CLASSIFIED

"$REPO_ROOT/scripts/transition-check.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLASSIFICATION_RECORDED \
  --state-after CLASSIFIED \
  --artifact ""

cat > "$TMP_ROOT/project/add.js" <<'EOF'
function add(a, b) {
  return a + b;
}

module.exports = { add };
EOF

cat > "$TMP_ROOT/project/test.js" <<'EOF'
const assert = require("assert");
const { add } = require("./add");

assert.strictEqual(add(1, 2), 3);
assert.strictEqual(add(-4, 4), 0);
EOF

"$REPO_ROOT/scripts/drive-s-run.sh" \
  --run-dir "$RUN_DIR" \
  --work-dir "$TMP_ROOT/project" \
  --command "node test.js" \
  --work-order-id "WO-1" \
  --files-touched "add.js" \
  --files-touched "test.js" \
  > "$TMP_ROOT/drive.out"

test -s "$RUN_DIR/raw/command-log.jsonl"
test -f "$RUN_DIR/raw/commands/cmd-0001.json"
test -f "$RUN_DIR/raw/claudecode-result.json"
test -f "$RUN_DIR/generated/run-state.json"
test -f "$RUN_DIR/generated/replay-result.json"
test -f "$RUN_DIR/generated/policy-result.json"
test -f "$RUN_DIR/generated/final-report.md"

grep -q '"event_type":"COMMAND_RECORDED_GREEN"' "$RUN_DIR/events.jsonl"
if grep '"event_type":"COMMAND_RECORDED_GREEN"' "$RUN_DIR/events.jsonl" | grep -q "raw/command-log.jsonl"; then
  echo "FAIL: command event must not hash raw/command-log.jsonl"
  exit 1
fi
grep -q '"event_type":"RUN_STATE_GENERATED"' "$RUN_DIR/events.jsonl"
grep -q '"event_type":"POLICY_CHECKED"' "$RUN_DIR/events.jsonl"
grep -q '"event_type":"FINAL_REPORT_GENERATED"' "$RUN_DIR/events.jsonl"

python3 - "$RUN_DIR/state.json" "$RUN_DIR/raw/claudecode-result.json" "$RUN_DIR/generated/run-state.json" "$RUN_DIR/generated/policy-result.json" <<'PY'
import json
import pathlib
import sys

state_pointer = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
claude = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
run_state = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
policy = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))

assert state_pointer["current_state"] == "FINAL_REPORT_GENERATED"
assert claude["status"] == "completed"
assert claude["required_matt_skill"] == "tdd"
assert claude["matt_evidence"]["red_not_applicable_reason"]
assert run_state["status"] == "completed"
assert run_state["acceptance"]["complete"] is True
assert run_state["command_log_summary"]["green_exit_code"] == 0
assert run_state["event_chain"]["replay_pass"] is True
assert run_state["raw_evidence"]["claudecode_result_contract_valid"] is True
assert run_state["matt_evidence_gate"]["evidence_present"] is True
assert policy["overall"] == "PASS"
PY

grep -q "负责人摘要" "$RUN_DIR/generated/final-report.md"

echo "smoke-s-level-driver: PASS"
