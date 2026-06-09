#!/usr/bin/env bash
# smoke-failure-finalization.sh — GREEN failure must produce failed evidence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="/tmp/hermes-v04-failure-finalization-smoke"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT/project/src"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/task.md" <<'EOF'
Implement a tiny add function and finalize failures with v0.4 evidence.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "v04-failure-finalization" \
  --task-type "smoke" \
  --mode "auto_run" \
  --scale "S" \
  --project "v04-failure-finalization")"

cat > "$TMP_ROOT/project/test.js" <<'EOF'
const assert = require("assert");
const { add } = require("./src/todo");

assert.strictEqual(add(1, 2), 3);
assert.strictEqual(add(-1, 1), 0);
EOF

if "$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "red" \
  --phase "RED" \
  -- node test.js; then
  echo "FAIL: RED must fail before implementation exists"
  exit 1
fi

cat > "$TMP_ROOT/project/src/todo.js" <<'EOF'
function add(a, b) {
  return a - b;
}

module.exports = { add };
EOF

set +e
"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "green" \
  --phase "GREEN" \
  -- node test.js
GREEN_EXIT=$?
set -e

if [[ "$GREEN_EXIT" -eq 0 ]]; then
  echo "FAIL: GREEN must fail with the intentionally wrong implementation"
  exit 1
fi

cat > "$RUN_DIR/raw/files-touched.txt" <<'EOF'
src/todo.js
test.js
EOF

set +e
"$REPO_ROOT/scripts/fail-run.sh" \
  --run-dir "$RUN_DIR" \
  --reason "GREEN command failed in failure-finalization smoke" \
  --failed-phase "GREEN" \
  --failed-command "node test.js" > "$TMP_ROOT/fail-run.out"
FAIL_RUN_EXIT=$?
set -e

if [[ "$FAIL_RUN_EXIT" -eq 0 ]]; then
  echo "FAIL: fail-run.sh should return non-zero for a failed task"
  exit 1
fi

test -f "$RUN_DIR/raw/failure-result.json"
test -f "$RUN_DIR/events.jsonl"
test -f "$RUN_DIR/generated/replay-result.json"
test -f "$RUN_DIR/generated/run-state.json"
test -f "$RUN_DIR/generated/policy-result.json"
test -f "$RUN_DIR/generated/final-report.md"

grep -q '"event_type":"RUN_FAILED"' "$RUN_DIR/events.jsonl"
grep -Eq "Overall:[[:space:]]+FAIL" "$RUN_DIR/generated/policy-check.out"

if grep -q "PASS" "$RUN_DIR/generated/final-report.md"; then
  echo "FAIL: failure final report must not contain PASS"
  exit 1
fi

python3 - "$RUN_DIR/generated/run-state.json" "$RUN_DIR/generated/policy-result.json" "$RUN_DIR/generated/replay-result.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
policy = json.load(open(sys.argv[2], encoding="utf-8"))
replay = json.load(open(sys.argv[3], encoding="utf-8"))

assert state["status"] == "failed"
assert state["acceptance"]["complete"] is False
assert state["verification"]["tests_pass"] is False
assert state["failed_phase"] == "GREEN"
assert state["failed_command"]
assert state["failed_exit_code"] != 0
assert state["failure_reason"]
assert state["event_chain"]["replay_pass"] is True
assert "RUN_FAILED" in state["event_chain"]["event_types"]
assert state["raw_evidence"]["failure_result"] == "raw/failure-result.json"
assert policy["overall"] == "FAIL"
assert replay["replay_pass"] is True
PY

echo "smoke-failure-finalization: PASS"
