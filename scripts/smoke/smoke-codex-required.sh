#!/usr/bin/env bash
# smoke-codex-required.sh — L-level, Codex diff_review NOT PASS, acceptance true => FAIL.
# Expected: policy-check exits 1, failure specifically for acceptance-codex-consistency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_CHECK="$SCRIPT_DIR/../policy-check.sh"
FIXTURE="$SCRIPT_DIR/../../examples/policy/bad-acceptance-without-codex.json"
TMPFILE=$(mktemp /tmp/smoke-codex-XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT

cp "$FIXTURE" "$TMPFILE"

PASS=true

# Capture output; policy-check must exit 1
OUTPUT=$("$POLICY_CHECK" --run-state "$TMPFILE" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "FAIL: policy-check should have exited non-zero for missing Codex review"
  PASS=false
else
  echo "PASS: policy-check exited 1 as expected"
  if echo "$OUTPUT" | grep -q "FAIL  acceptance-codex-consistency"; then
    echo "PASS: policy-check correctly flagged acceptance-codex-consistency as FAIL"
  else
    echo "FAIL: policy-check did not report acceptance-codex-consistency"
    PASS=false
  fi
fi

if $PASS; then
  echo ""
  echo "=== smoke-codex-required: ALL CHECKS PASSED ==="
  exit 0
else
  echo ""
  echo "=== smoke-codex-required: FAILED ==="
  exit 1
fi
