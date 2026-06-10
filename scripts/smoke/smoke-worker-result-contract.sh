#!/usr/bin/env bash
# smoke-worker-result-contract.sh — Positive v0.5.3 worker result contract smoke.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-worker-result-contract.XXXXXX)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

PROJECT_ROOT="$TMP_ROOT/project"
WORK_DIR="$PROJECT_ROOT/work"
mkdir -p "$WORK_DIR"

TASK_FILE="$TMP_ROOT/task.md"
cat > "$TASK_FILE" <<'EOF'
Implement a tiny todo store with TDD evidence and a worker result contract.
EOF

RUN_DIR="$(bash "$REPO_ROOT/scripts/run-init.sh" \
  --root "$PROJECT_ROOT" \
  --task-file "$TASK_FILE" \
  --scale M \
  --mode auto_run \
  --task-type feature \
  --project worker-result-smoke)"

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
store.add("write smoke");
if (store.list().length !== 1) throw new Error("expected one item");
if (store.list()[0].title !== "write smoke") throw new Error("bad title");
console.log("todo smoke pass");
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

GREEN_EXIT="$(python3 - "$RUN_DIR/raw/command-log.jsonl" <<'PY'
import json
import sys
items = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
print(items[-1]["exit_code"])
PY
)"
if [[ "$GREEN_EXIT" != "0" ]]; then
  echo "FAIL: GREEN phase did not pass"
  exit 1
fi

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

WORKER_RAW="$TMP_ROOT/worker-output.txt"
cat > "$WORKER_RAW" <<'EOF'
Simulated worker transcript: wrote test first, observed RED, wrote implementation, observed GREEN.
EOF

WORKER_RESULT="$TMP_ROOT/worker-result.json"
cat > "$WORKER_RESULT" <<'EOF'
{
  "schema_version": "0.5.3",
  "work_order_id": "WO-1",
  "worker": "claude-code",
  "worker_skill": "mattpocock/tdd",
  "status": "completed",
  "result_type": "implementation",
  "raw_output_path": "raw/worker/WO-1.raw.txt",
  "structured_output_path": "raw/worker/WO-1.worker-result.json",
  "files_touched": ["test.js", "src/todo.js"],
  "commands_run": ["node test.js", "node test.js"],
  "evidence_refs": ["raw/command-log.jsonl", "raw/claudecode-result.json"],
  "review": {
    "verdict": "UNKNOWN",
    "summary": "Implementation evidence captured; final acceptance remains outside worker ownership.",
    "blocking_findings": []
  },
  "deferred": {
    "is_deferred": false,
    "reason": ""
  },
  "notes": "Worker implementation evidence only. Final acceptance remains owned by Hermes/Codex gates."
}
EOF

PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime" python3 - "$RUN_DIR" "$WORKER_RESULT" "$WORKER_RAW" <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import sys

plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
spec = importlib.util.spec_from_file_location(
    "hermes_evidence_runtime",
    plugin_dir / "__init__.py",
    submodule_search_locations=[str(plugin_dir)],
)
if spec is None or spec.loader is None:
    raise SystemExit("failed to load plugin spec")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
tools = importlib.import_module("hermes_evidence_runtime.tools")

run_dir, worker_result, worker_raw = sys.argv[1:]

validate = json.loads(tools.evidence_validate_worker_result({
    "worker_result_path": worker_result,
}))
if not validate.get("ok") or validate.get("verdict") != "PASS":
    raise SystemExit(f"validate failed: {validate}")

record = json.loads(tools.evidence_record_worker_result({
    "run_dir": run_dir,
    "worker_result_path": worker_result,
    "raw_output_path": worker_raw,
}))
if not record.get("ok"):
    raise SystemExit(f"record failed: {record}")
PY

grep -q '"event_type":"WORKER_RESULT_RECORDED"' "$RUN_DIR/events.jsonl"

bash "$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
bash "$REPO_ROOT/scripts/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/policy.out"
bash "$REPO_ROOT/scripts/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/final.out"

grep -q "PASS  worker-result-contract-present" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-must-not-write-acceptance" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-result-deferred-consistency" "$TMP_ROOT/policy.out"
grep -q "PASS  codex-deferred-no-pass" "$TMP_ROOT/policy.out"
grep -q "PASS  worker-raw-output-tracked" "$TMP_ROOT/policy.out"
grep -q "Overall: PASS" "$TMP_ROOT/policy.out"

test -s "$RUN_DIR/raw/command-log.jsonl"
test -s "$RUN_DIR/generated/run-state.json"
test -s "$RUN_DIR/generated/policy-result.json"
test -s "$RUN_DIR/generated/final-report.md"
grep -q "Worker Result Evidence" "$RUN_DIR/generated/final-report.md"

python3 - "$RUN_DIR/generated/run-state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1], encoding="utf-8"))
assert state["worker_results"], "worker_results missing"
assert state["worker_result_contract"]["required"] is True
assert state["worker_results"][0]["worker_acceptance_complete"] is False
sources = set(state["provenance"]["source_files"])
assert "raw/worker/WO-1.worker-result.json" in sources
assert "raw/worker/WO-1.raw.txt" in sources
assert state["acceptance"]["complete"] is True
PY

echo "smoke-worker-result-contract: PASS"
