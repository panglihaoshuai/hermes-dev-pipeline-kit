#!/usr/bin/env bash
# smoke-worker-dry-run-to-run-state.sh — Verify explicit dry-run evidence flows into run-state.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-worker-dry-run-run-state.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

PROJECT_ROOT="$TMP_ROOT/project"
WORK_DIR="$PROJECT_ROOT/work"
DRY_RUN_DIR="$TMP_ROOT/worker-dry-run"
mkdir -p "$WORK_DIR" "$DRY_RUN_DIR"

TASK_FILE="$TMP_ROOT/task.md"
cat > "$TASK_FILE" <<'EOF'
Implement a tiny todo store and record explicit worker dry-run evidence.
EOF

RUN_DIR="$(bash "$REPO_ROOT/scripts/run-init.sh" \
  --root "$PROJECT_ROOT" \
  --task-file "$TASK_FILE" \
  --scale M \
  --mode auto_run \
  --task-type feature \
  --project worker-dry-run-smoke)"

bash "$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type INTAKE_RECORDED \
  --actor Hermes \
  --state-after INTAKE_RECORDED \
  --artifact task.md >/dev/null

bash "$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type WORK_ORDER_CREATED \
  --actor Hermes \
  --state-after WORK_ORDER_CREATED \
  --artifact work-orders/WO-1.json >/dev/null

bash "$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_DELEGATED \
  --actor Hermes \
  --state-after CLAUDECODE_DELEGATED \
  --artifact work-orders/WO-1.json >/dev/null

cat > "$WORK_DIR/test.js" <<'EOF'
const { createTodoStore } = require("./src/todo");

const store = createTodoStore();
store.add("record worker dry-run evidence");
if (store.list().length !== 1) throw new Error("expected one item");
if (store.list()[0].title !== "record worker dry-run evidence") throw new Error("bad title");
console.log("todo dry-run smoke pass");
EOF

set +e
bash "$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$WORK_DIR" \
  --step-id red-missing-implementation \
  --phase RED \
  -- node test.js
RED_EXIT=$?
set -e

if [[ "$RED_EXIT" -eq 0 ]]; then
  echo "FAIL: RED phase unexpectedly passed"
  exit 1
fi

mkdir -p "$WORK_DIR/src"
cat > "$WORK_DIR/src/todo.js" <<'EOF'
function createTodoStore() {
  const items = [];
  return {
    add(title) {
      items.push({ title });
    },
    list() {
      return items.slice();
    },
  };
}

module.exports = { createTodoStore };
EOF

bash "$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$WORK_DIR" \
  --step-id green-implementation \
  --phase GREEN \
  -- node test.js

python3 - "$RUN_DIR/raw/command-log.jsonl" <<'PY'
import json
import sys

items = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
red = [item for item in items if item.get("phase") == "RED"]
green = [item for item in items if item.get("phase") == "GREEN"]
if not red or red[0].get("exit_code") == 0:
    raise SystemExit("RED evidence missing or did not fail")
if not green or green[-1].get("exit_code") != 0:
    raise SystemExit("GREEN evidence missing or did not pass")
PY

cat > "$RUN_DIR/raw/files-touched.txt" <<'EOF'
test.js
src/todo.js
EOF

cat > "$RUN_DIR/raw/claudecode-result.json" <<'EOF'
{
  "work_order_id": "WO-1",
  "status": "completed",
  "required_matt_skill": "tdd",
  "matt_evidence": {
    "red": "node test.js failed before implementation",
    "red_exit_code": 1,
    "red_not_applicable_reason": "",
    "green": "node test.js passed after implementation",
    "green_exit_code": 0,
    "commands": ["node test.js", "node test.js"]
  },
  "files_touched": ["test.js", "src/todo.js"],
  "commands_run": ["node test.js", "node test.js"],
  "blocked": false,
  "notes": "Simulated ClaudeCode result contract. No final acceptance field."
}
EOF

bash "$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_RESULT_RECORDED \
  --actor ClaudeCode \
  --state-after CLAUDECODE_RESULT_RECORDED \
  --artifact raw/claudecode-result.json >/dev/null

bash "$REPO_ROOT/scripts/invoke-worker-dry-run.sh" \
  --worker claude-code \
  --out-dir "$DRY_RUN_DIR" \
  --timeout-seconds 15 \
  --allow-real-invocation no >/dev/null

NORMALIZED_WORKER_RESULT="$TMP_ROOT/worker-result.json"
bash "$REPO_ROOT/scripts/normalize-worker-result.sh" \
  --worker claude-code \
  --worker-skill explicit-dry-run/tdd \
  --work-order-id WO-1 \
  --status deferred \
  --result-type implementation \
  --raw-output "$DRY_RUN_DIR/raw.txt" \
  --structured-output "$DRY_RUN_DIR/structured.json" \
  --invocation-json "$DRY_RUN_DIR/invocation.json" \
  --out "$NORMALIZED_WORKER_RESULT" >/dev/null

mkdir -p "$RUN_DIR/raw/worker"
cp "$DRY_RUN_DIR/invocation.json" "$RUN_DIR/raw/worker/WO-1.invocation.json"
cp "$DRY_RUN_DIR/structured.json" "$RUN_DIR/raw/worker/WO-1.structured.json"

bash "$REPO_ROOT/scripts/record-worker-result.sh" \
  --run-dir "$RUN_DIR" \
  --worker-result "$NORMALIZED_WORKER_RESULT" \
  --raw-output "$DRY_RUN_DIR/raw.txt" >/dev/null

grep -q '"event_type":"WORKER_RESULT_RECORDED"' "$RUN_DIR/events.jsonl"

bash "$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
bash "$REPO_ROOT/scripts/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/policy.out"
bash "$REPO_ROOT/scripts/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/final.out"

grep -q "Overall: PASS" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-result-contract-present" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-invocation-truthfulness" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-invocation-evidence-present" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-invocation-no-acceptance" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-invocation-skipped-consistency" "$TMP_ROOT/policy.out"
grep -q "Worker Result Evidence" "$RUN_DIR/generated/final-report.md"
grep -q "real invocation" "$RUN_DIR/generated/final-report.md"
grep -q "real invocation disabled" "$RUN_DIR/generated/final-report.md"

test -s "$RUN_DIR/raw/command-log.jsonl"
test -s "$RUN_DIR/raw/worker/WO-1.worker-result.json"
test -s "$RUN_DIR/raw/worker/WO-1.raw.txt"
test -s "$RUN_DIR/raw/worker/WO-1.structured.json"
test -s "$RUN_DIR/raw/worker/WO-1.invocation.json"
test -s "$RUN_DIR/generated/run-state.json"
test -s "$RUN_DIR/generated/policy-result.json"
test -s "$RUN_DIR/generated/final-report.md"

python3 - "$RUN_DIR/generated/run-state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["worker_results"], "worker_results missing"
worker = state["worker_results"][0]
assert worker["worker"] == "claude-code"
assert worker["real_invocation"] is False
assert worker["skipped_reason"] == "real invocation disabled"
assert worker["invocation_path"] == "raw/worker/WO-1.invocation.json"
assert worker["worker_acceptance_complete"] is False
sources = set(state["provenance"]["source_files"])
assert "raw/worker/WO-1.worker-result.json" in sources
assert "raw/worker/WO-1.raw.txt" in sources
assert "raw/worker/WO-1.structured.json" in sources
assert "raw/worker/WO-1.invocation.json" in sources
assert state["command_log_summary"]["red_exit_code"] != 0
assert state["command_log_summary"]["green_exit_code"] == 0
PY

echo "smoke-worker-dry-run-to-run-state: PASS"
