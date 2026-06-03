#!/usr/bin/env bash
# smoke-forbidden-file.sh — Forbidden file modified => policy-check FAIL.
# Expected: policy-check exits 1, failure specifically for forbidden-file-violation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_CHECK="$SCRIPT_DIR/../policy-check.sh"
FIXTURE="$SCRIPT_DIR/../../examples/policy/bad-forbidden-file.json"
TMPFILE=$(mktemp /tmp/smoke-forbidden-XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT

cp "$FIXTURE" "$TMPFILE"

PASS=true

# Capture output; policy-check must exit 1
OUTPUT=$("$POLICY_CHECK" --run-state "$TMPFILE" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "FAIL: policy-check should have exited non-zero for forbidden-file violation"
  PASS=false
else
  echo "PASS: policy-check exited 1 as expected"
  if echo "$OUTPUT" | grep -q "FAIL  forbidden-file-violation"; then
    echo "PASS: policy-check correctly flagged forbidden-file-violation as FAIL"
  else
    echo "FAIL: policy-check did not report forbidden-file-violation"
    PASS=false
  fi
fi

if $PASS; then
  echo ""
  echo "=== smoke-forbidden-file: ALL CHECKS PASSED ==="
  exit 0
else
  echo ""
  echo "=== smoke-forbidden-file: FAILED ==="
  exit 1
fi
