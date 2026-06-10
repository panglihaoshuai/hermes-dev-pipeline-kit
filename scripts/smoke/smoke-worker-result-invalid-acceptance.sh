#!/usr/bin/env bash
# smoke-worker-result-invalid-acceptance.sh — Negative worker acceptance smoke.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/hermes-worker-result-invalid.XXXXXX)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

PROJECT_ROOT="$TMP_ROOT/project"
mkdir -p "$PROJECT_ROOT"
TASK_FILE="$TMP_ROOT/task.md"
cat > "$TASK_FILE" <<'EOF'
Invalid worker result must not be accepted.
EOF

RUN_DIR="$(bash "$REPO_ROOT/scripts/run-init.sh" \
  --root "$PROJECT_ROOT" \
  --task-file "$TASK_FILE" \
  --scale M \
  --mode auto_run \
  --task-type smoke \
  --project worker-result-invalid-smoke)"

BAD_RESULT="$REPO_ROOT/examples/worker-results/bad-worker-acceptance-complete.json"

set +e
bash "$REPO_ROOT/scripts/validate-worker-result.sh" --worker-result "$BAD_RESULT" > "$TMP_ROOT/validate.out"
VALIDATE_EXIT=$?
bash "$REPO_ROOT/scripts/record-worker-result.sh" --run-dir "$RUN_DIR" --worker-result "$BAD_RESULT" > "$TMP_ROOT/record.out" 2> "$TMP_ROOT/record.err"
RECORD_EXIT=$?
set -e

if [[ "$VALIDATE_EXIT" -eq 0 ]]; then
  echo "FAIL: invalid worker result validation passed"
  cat "$TMP_ROOT/validate.out"
  exit 1
fi

grep -q '"verdict": "FAIL"' "$TMP_ROOT/validate.out"

if [[ "$RECORD_EXIT" -eq 0 ]]; then
  echo "FAIL: invalid worker result was recorded"
  cat "$TMP_ROOT/record.out"
  exit 1
fi

if grep -q '"event_type":"WORKER_RESULT_RECORDED"' "$RUN_DIR/events.jsonl"; then
  echo "FAIL: invalid worker result appended an event"
  exit 1
fi

echo "smoke-worker-result-invalid-acceptance: PASS"
