#!/usr/bin/env bash
set -euo pipefail

# check-manifest.sh — Validate manifest.yaml structure and referenced files/dirs
# Usage: bash scripts/check-manifest.sh
# Exit 0 if all checks pass, 1 otherwise.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest.yaml"
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "=== manifest.yaml validation ==="
echo ""

# --- Check 1: manifest.yaml exists ---
if [[ -f "$MANIFEST" ]]; then
  pass "manifest.yaml exists"
else
  fail "manifest.yaml does not exist at $MANIFEST"
  echo ""
  echo "Result: FAIL (cannot continue without manifest)"
  exit 1
fi

# --- Check 2: Contains 'name:' field ---
if grep -qE '^\s*name:' "$MANIFEST"; then
  pass "Contains 'name:' field"
else
  fail "Missing 'name:' field"
fi

# --- Check 3: Contains 'version:' field ---
if grep -qE '^\s*version:' "$MANIFEST"; then
  pass "Contains 'version:' field"
else
  fail "Missing 'version:' field"
fi

# --- Check 4: Contains 'entrypoints:' section ---
if grep -qE '^\s*entrypoints:' "$MANIFEST"; then
  pass "Contains 'entrypoints:' section"
else
  fail "Missing 'entrypoints:' section"
fi

# --- Check 5: Contains 'skills:' section ---
if grep -qE '^\s*skills:' "$MANIFEST"; then
  pass "Contains 'skills:' section"
else
  fail "Missing 'skills:' section"
fi

# --- Check 6: Contains 'protocols:' section ---
if grep -qE '^\s*protocols:' "$MANIFEST"; then
  pass "Contains 'protocols:' section"
else
  fail "Missing 'protocols:' section"
fi

# --- Check 7: Contains 'dependencies:' section ---
if grep -qE '^\s*dependencies:' "$MANIFEST"; then
  pass "Contains 'dependencies:' section"
else
  fail "Missing 'dependencies:' section"
fi

# --- Check 8: Contains 'safety:' section ---
if grep -qE '^\s*safety:' "$MANIFEST"; then
  pass "Contains 'safety:' section"
else
  fail "Missing 'safety:' section"
fi

# --- Check 9: All entrypoint files exist ---
ENTRYPOINT_FILES=(
  "BOOTSTRAP.md"
  "README.md"
  "scripts/install.sh"
  "scripts/doctor.sh"
  "scripts/ci-local.sh"
  "scripts/uninstall.sh"
  "scripts/install-deps.sh"
  "protocols/claude-delegation-protocol.md"
)

for f in "${ENTRYPOINT_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    pass "Entrypoint file exists: $f"
  else
    fail "Entrypoint file missing: $f"
  fi
done

# --- Check 10: All skill directories exist ---
SKILL_DIRS=(
  "skills/software-development/dev-pipeline-orchestrator"
  "skills/software-development/dev-pipeline-report"
)

for d in "${SKILL_DIRS[@]}"; do
  if [[ -d "$REPO_ROOT/$d" ]]; then
    pass "Skill directory exists: $d"
  else
    fail "Skill directory missing: $d"
  fi
done

# --- Summary ---
echo ""
echo "=== Results ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "Result: PASS"
  exit 0
else
  echo "Result: FAIL"
  exit 1
fi
