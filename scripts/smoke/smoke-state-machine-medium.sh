#!/usr/bin/env bash
# smoke-state-machine-medium.sh — v0.4 M-level hash-linked state-machine smoke.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="/tmp/hermes-v04-state-machine-medium"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT/project/src"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/task.md" <<'EOF'
Implement a tiny todo store with hash-linked state-machine evidence.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "v04-state-machine-medium" \
  --task-type "feature" \
  --mode "auto_run" \
  --scale "M" \
  --project "v04-state-machine-medium")"

"$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type INTAKE_RECORDED \
  --actor Hermes \
  --state-after INTAKE_RECORDED \
  --artifact task.md >/dev/null

"$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type WORK_ORDER_CREATED \
  --actor Hermes \
  --state-after WORK_ORDER_CREATED \
  --artifact work-orders/WO-1.json >/dev/null

"$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_DELEGATED \
  --actor Hermes \
  --state-after CLAUDECODE_DELEGATED \
  --artifact work-orders/WO-1.json >/dev/null

cat > "$TMP_ROOT/project/test.js" <<'EOF'
const { createTodoStore } = require("./src/todo");

const store = createTodoStore();
store.add("red before green");

if (store.list().length !== 1) {
  throw new Error("expected one todo");
}
if (store.list()[0].completed !== false) {
  throw new Error("todo should start incomplete");
}
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
  "notes": "v0.4 state-machine smoke result contract. Acceptance is intentionally absent."
}
EOF

"$REPO_ROOT/scripts/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type CLAUDECODE_RESULT_RECORDED \
  --actor ClaudeCode \
  --state-after CLAUDECODE_RESULT_RECORDED \
  --artifact raw/claudecode-result.json >/dev/null

"$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
"$REPO_ROOT/scripts/replay-run.sh" "$RUN_DIR" >/dev/null
"$REPO_ROOT/scripts/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/policy.out"
"$REPO_ROOT/scripts/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/final-report.out"

test -f "$RUN_DIR/events.jsonl"
test -f "$RUN_DIR/state.json"
test -f "$RUN_DIR/raw/command-log.jsonl"
test -f "$RUN_DIR/raw/commands/cmd-0001.json"
test -f "$RUN_DIR/raw/commands/cmd-0002.json"
test -f "$RUN_DIR/raw/claudecode-result.json"
test -f "$RUN_DIR/generated/run-state.json"
test -f "$RUN_DIR/generated/replay-result.json"
test -f "$RUN_DIR/generated/final-report.md"

grep -q '"event_chain"' "$RUN_DIR/generated/run-state.json"
grep -q '"last_event_hash"' "$RUN_DIR/generated/run-state.json"
grep -Eq "Overall:[[:space:]]+PASS" "$TMP_ROOT/policy.out"
if grep '"event_type":"COMMAND_RECORDED_' "$RUN_DIR/events.jsonl" | grep -q "raw/command-log.jsonl"; then
  echo "FAIL: command events must not hash raw/command-log.jsonl"
  exit 1
fi

python3 - "$RUN_DIR/events.jsonl" "$RUN_DIR/generated/run-state.json" "$RUN_DIR/generated/replay-result.json" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
types = [event["event_type"] for event in events]
assert types.index("COMMAND_RECORDED_RED") < types.index("COMMAND_RECORDED_GREEN")
state = json.load(open(sys.argv[2], encoding="utf-8"))
assert state["event_chain"]["last_event_hash"]
assert state["event_chain"]["replay_pass"] is True
replay = json.load(open(sys.argv[3], encoding="utf-8"))
assert replay["replay_pass"] is True
assert replay["last_event_hash"]
PY

echo "smoke-state-machine-medium: PASS"
