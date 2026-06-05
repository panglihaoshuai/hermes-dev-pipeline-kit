#!/usr/bin/env bash
# smoke-generated-run-state.sh — v0.3 executable evidence harness smoke test.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="/tmp/hermes-generated-run-state-smoke"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT/work"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/task.md" <<'EOF'
Add a tiny add.js implementation with TDD evidence.
EOF

RUN_DIR="$("$REPO_ROOT/scripts/run-init.sh" \
  --root "$TMP_ROOT" \
  --task-file "$TMP_ROOT/task.md" \
  --run-id "smoke-generated-run-state" \
  --task-type "bugfix" \
  --mode "auto_run" \
  --scale "M" \
  --project "generated-run-state-smoke")"

cat > "$TMP_ROOT/work/test.js" <<'EOF'
const { add } = require("./add");

if (add(1, 2) !== 3) {
  throw new Error("add(1, 2) should equal 3");
}
EOF

if "$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/work" \
  --step-id "red" \
  --phase "RED" \
  -- node test.js; then
  echo "FAIL: RED phase should fail before add.js exists"
  exit 1
fi

cat > "$TMP_ROOT/work/add.js" <<'EOF'
function add(a, b) {
  return a + b;
}

module.exports = { add };
EOF

"$REPO_ROOT/scripts/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$TMP_ROOT/work" \
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
  "notes": "Smoke result contract. Acceptance is intentionally absent."
}
EOF

"$REPO_ROOT/scripts/generate-run-state.sh" "$RUN_DIR" >/dev/null
"$REPO_ROOT/scripts/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" >/dev/null
"$REPO_ROOT/scripts/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$TMP_ROOT/final-report.out"

if ! grep -q "负责人摘要" "$TMP_ROOT/final-report.out"; then
  echo "FAIL: final report should contain Chinese owner summary"
  exit 1
fi

if [[ ! -f "$RUN_DIR/generated/final-report.md" ]]; then
  echo "FAIL: final report file was not written"
  exit 1
fi

echo "smoke-generated-run-state: PASS"
