#!/usr/bin/env bash
# smoke-real-task-medium.sh — Exercise a realistic M-level task through v0.3 evidence harness.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-real-task-medium.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/project/src"

cat > "$TMP_ROOT/task.md" <<'EOF'
Implement a tiny todo store with TDD evidence.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "real-task-medium-smoke" \
  --task-type "feature" \
  --mode "auto_run" \
  --scale "M" \
  --project "real-task-medium-smoke")"

cat > "$TMP_ROOT/project/test.js" <<'EOF'
const { createTodoStore } = require("./src/todo");

const todos = createTodoStore();
todos.add("capture command evidence");
todos.add("write result contract");

const list = todos.list();

if (list.length !== 2) {
  throw new Error(`expected 2 todos, got ${list.length}`);
}

if (list[0].title !== "capture command evidence") {
  throw new Error("first todo title mismatch");
}

if (list.some((item) => item.completed !== false)) {
  throw new Error("new todos should be incomplete");
}
EOF

if "$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "red" \
  --phase "RED" \
  -- node test.js; then
  echo "FAIL: RED phase should fail before src/todo.js exists"
  exit 1
fi

cat > "$TMP_ROOT/project/src/store.js" <<'EOF'
function createStore() {
  const items = [];

  return {
    add(item) {
      items.push(item);
    },
    list() {
      return items.map((item) => ({ ...item }));
    },
  };
}

module.exports = { createStore };
EOF

cat > "$TMP_ROOT/project/src/todo.js" <<'EOF'
const { createStore } = require("./store");

function createTodoStore() {
  const store = createStore();

  return {
    add(title) {
      store.add({ title, completed: false });
    },
    list() {
      return store.list();
    },
  };
}

module.exports = { createTodoStore };
EOF

"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/project" \
  --step-id "green" \
  --phase "GREEN" \
  -- node test.js

cat > "$RUN_DIR/raw/files-touched.txt" <<'EOF'
src/store.js
src/todo.js
test.js
EOF

cat > "$RUN_DIR/raw/claudecode-result.json" <<'EOF'
{
  "work_order_id": "WO-1",
  "status": "completed",
  "required_matt_skill": "tdd",
  "matt_evidence": {
    "red": "node test.js failed before src/todo.js existed",
    "red_exit_code": 1,
    "red_not_applicable_reason": "",
    "green": "node test.js passed after src/store.js and src/todo.js implementation",
    "green_exit_code": 0,
    "commands": [
      "node test.js",
      "node test.js"
    ]
  },
  "files_touched": [
    "src/store.js",
    "src/todo.js",
    "test.js"
  ],
  "commands_run": [
    "node test.js",
    "node test.js"
  ],
  "blocked": false,
  "notes": "Real M-level smoke result contract. Acceptance is intentionally absent."
}
EOF

"$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
"$REPO_ROOT/scripts/final-report.sh" "$RUN_DIR/generated/run-state.json" >/dev/null
"$REPO_ROOT/scripts/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/policy.out"

grep -Eq "PASS[[:space:]]+ml-delegation" "$TMP_ROOT/policy.out"
grep -Eq "PASS[[:space:]]+tdd-command-log-evidence" "$TMP_ROOT/policy.out"
grep -Eq "Overall:[[:space:]]+PASS" "$TMP_ROOT/policy.out"

python3 - "$RUN_DIR/generated/run-state.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    state = json.load(f)

assert state["claudecode_delegation"]["delegated"] is True
assert state["raw_evidence"]["claudecode_result"] == "raw/claudecode-result.json"
assert state["raw_evidence"]["claudecode_result_contract_valid"] is True
assert state["command_log_summary"]["red_exit_code"] != 0
assert state["command_log_summary"]["green_exit_code"] == 0
assert state["command_log_summary"]["tdd_sequence_verified"] is True
PY

echo "smoke-real-task-medium: PASS"
