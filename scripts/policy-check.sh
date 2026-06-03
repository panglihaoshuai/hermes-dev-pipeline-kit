#!/usr/bin/env bash
# policy-check.sh — Validates run-state objects and repo dirs against policy rules.
# No external dependencies (no npm/pip/ajv). Uses python3 -c for JSON parsing.
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

# ── helpers ──────────────────────────────────────────────────────────────────

banner() {
  echo ""
  echo "========================================"
  echo " policy-check"
  echo "========================================"
  echo ""
}

record() {
  local name="$1" status="$2"
  if [[ "$status" == PASS* ]]; then
    (( PASS_COUNT++ )) || true
  else
    (( FAIL_COUNT++ )) || true
  fi
  RESULTS+=("  $status  $name")
}

show_results() {
  echo ""
  echo "--- Run-State Checks ---"
  for r in "${RESULTS[@]}"; do echo "$r"; done
  local total=$(( PASS_COUNT + FAIL_COUNT ))
  echo ""
  echo "--- Results ---"
  echo "  PASS: $PASS_COUNT / $total"
  if (( FAIL_COUNT == 0 )); then
    echo "  Overall: PASS"
  else
    echo "  Overall: FAIL"
  fi
  echo ""
}

# ── JSON extraction helper (python3) ────────────────────────────────────────

jget() {
  # Usage: jget <file> <jq-like-expression>
  # Supports: .key, .key.sub, .arr | returns raw value
  local file="$1" expr="$2"
  python3 -c "
import json, sys
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
v = g(d, '$expr')
if isinstance(v, (dict, list)):
    print(json.dumps(v))
elif isinstance(v, bool):
    print('true' if v else 'false')
elif v is None:
    print('null')
else:
    print(v)
"
}

jlen() {
  local file="$1" expr="$2"
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
print(len(g(d, '$expr')))
"
}

jarray_contains() {
  # Returns 'true' if array at expr contains value
  local file="$1" expr="$2" value="$3"
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
arr = g(d, '$expr')
print('true' if '$value' in arr else 'false')
"
}

jcheck_intersection() {
  # Returns 'true' if two arrays share any element
  local file="$1" expr1="$2" expr2="$3"
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
a = set(g(d, '$expr1'))
b = set(g(d, '$expr2'))
print('true' if a & b else 'false')
"
}

jcheck_any_field() {
  # Check if any item in array has a field matching value
  local file="$1" array_expr="$2" field="$3" value="$4"
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
arr = g(d, '$array_expr')
found = any(item.get('$field') == '$value' for item in arr if isinstance(item, dict))
print('true' if found else 'false')
"
}

jcheck_any_field_ne() {
  # Check if any item in array has a field NOT matching value
  local file="$1" array_expr="$2" field="$3" value="$4"
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
def g(obj, path):
    for p in path.split('.'):
        if not p: continue
        if isinstance(obj, list):
            obj = obj[int(p)]
        else:
            obj = obj[p]
    return obj
arr = g(d, '$array_expr')
found = any(item.get('$field') != '$value' and item.get('pass_fail') == 'PASS' for item in arr if isinstance(item, dict))
# More precise: check exit_code != 0 AND pass_fail == 'PASS'
found = any(item.get('exit_code', 0) != 0 and item.get('pass_fail') == 'PASS' for item in arr if isinstance(item, dict))
print('true' if found else 'false')
"
}

# ── run-state checks ────────────────────────────────────────────────────────

check_run_state() {
  local f="$1"

  # 1. acceptance.complete && codex.diff_review_verdict != PASS && !disabled_by_user && scale != S
  local acc_complete diff_verdict disabled scale
  acc_complete=$(jget "$f" "acceptance.complete")
  diff_verdict=$(jget "$f" "codex.diff_review_verdict")
  disabled=$(jget "$f" "codex.disabled_by_user")
  scale=$(jget "$f" "classification.scale")

  if [[ "$acc_complete" == "true" && "$diff_verdict" != "PASS" && "$disabled" != "true" && "$scale" != "S" ]]; then
    record "acceptance-codex-consistency" "FAIL"
  else
    record "acceptance-codex-consistency" "PASS"
  fi

  # 2. forbidden file violation
  local has_intersection
  has_intersection=$(jcheck_intersection "$f" "modified_files" "forbidden_files")
  if [[ "$has_intersection" == "true" ]]; then
    record "forbidden-file-violation" "FAIL"
  else
    record "forbidden-file-violation" "PASS"
  fi

  # 3. codex.plan_review_verdict is FAIL or UNKNOWN
  local plan_verdict
  plan_verdict=$(jget "$f" "codex.plan_review_verdict")
  if [[ "$plan_verdict" == "FAIL" || "$plan_verdict" == "UNKNOWN" ]]; then
    record "plan-review-verdict" "FAIL"
  else
    record "plan-review-verdict" "PASS"
  fi

  # 4. scale=L AND plan_review_verdict=NOT_REQUIRED
  scale=$(jget "$f" "classification.scale")
  plan_verdict=$(jget "$f" "codex.plan_review_verdict")
  if [[ "$scale" == "L" && "$plan_verdict" == "NOT_REQUIRED" ]]; then
    record "large-task-plan-review" "FAIL"
  else
    record "large-task-plan-review" "PASS"
  fi

  # 5. command_evidence: exit_code != 0 AND pass_fail == PASS (inconsistent)
  local has_inconsistent
  has_inconsistent=$(jcheck_any_field_ne "$f" "command_evidence" "exit_code" "0")
  if [[ "$has_inconsistent" == "true" ]]; then
    record "command-evidence-consistency" "FAIL"
  else
    record "command-evidence-consistency" "PASS"
  fi

  # 6. commit_approved but tests_pass == false
  local commit_approved tests_pass
  commit_approved=$(jget "$f" "approval_gates.commit_approved")
  tests_pass=$(jget "$f" "verification.tests_pass")
  if [[ "$commit_approved" == "true" && "$tests_pass" == "false" ]]; then
    record "commit-without-tests" "FAIL"
  else
    record "commit-without-tests" "PASS"
  fi

  # 7. mode must be dry_run/plan_only/auto_run
  local mode
  mode=$(jget "$f" "mode")
  if [[ "$mode" != "dry_run" && "$mode" != "plan_only" && "$mode" != "auto_run" ]]; then
    record "valid-mode" "FAIL"
  else
    record "valid-mode" "PASS"
  fi

  # 8. generated file warning (informational — always PASS, just prints warning)
  local modified_len
  modified_len=$(jlen "$f" "modified_files")
  local has_gen=false
  for (( i=0; i<modified_len; i++ )); do
    local mf
    mf=$(jget "$f" "modified_files.$i" 2>/dev/null || true)
    if [[ "$mf" == *"generated"* ]]; then
      has_gen=true
      break
    fi
  done
  if [[ "$has_gen" == "true" ]]; then
    local cmd_len
    cmd_len=$(jlen "$f" "command_evidence")
    if [[ "$cmd_len" == "0" ]]; then
      record "generated-file-without-evidence" "PASS (warning)"
    else
      record "generated-file-without-evidence" "PASS"
    fi
  else
    record "generated-file-without-evidence" "PASS"
  fi
}

# ── repo checks ─────────────────────────────────────────────────────────────

check_repo() {
  local dir="$1"
  local fail=0

  echo "--- Repo Checks ---"

  # 1. Secret patterns
  local secret_hits
  secret_hits=$(grep -rInE '(API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY)\s*[:=]' "$dir" \
    --include='*.json' --include='*.ts' --include='*.js' --include='*.sh' --include='*.md' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude='policy-check.sh' --exclude='AGENTS.md' --exclude='run-state.schema.json' 2>/dev/null || true)
  if [[ -n "$secret_hits" ]]; then
    echo "  FAIL  secret-patterns"
    echo "$secret_hits" | head -5
    fail=1
  else
    echo "  PASS  secret-patterns"
  fi

  # 2. Personal data paths
  local personal_hits
  personal_hits=$(grep -rInE '(\/Users\/songshiyao|panglihaoshuai|resumeforcm)' "$dir" \
    --include='*.json' --include='*.ts' --include='*.js' --include='*.sh' --include='*.md' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude='policy-check.sh' 2>/dev/null || true)
  if [[ -n "$personal_hits" ]]; then
    echo "  FAIL  personal-data-paths"
    echo "$personal_hits" | head -5
    fail=1
  else
    echo "  PASS  personal-data-paths"
  fi

  # 3. Forbidden files (.env, *.bak*, *backup*, *.log)
  local bad_files
  bad_files=$(find "$dir" -not -path '*/.git/*' -not -path '*/node_modules/*' \
    \( -name '.env' -o -name '*.bak*' -o -name '*backup*' -o -name '*.log' \) 2>/dev/null || true)
  if [[ -n "$bad_files" ]]; then
    echo "  FAIL  forbidden-file-types"
    echo "$bad_files" | head -5
    fail=1
  else
    echo "  PASS  forbidden-file-types"
  fi

  # 4. No 'git add -A' as recommended command (only forbidden/warning context OK)
  local add_all
  add_all=$(grep -rIn 'git add -A' "$dir" \
    --include='*.json' --include='*.ts' --include='*.js' --include='*.sh' --exclude-dir=.git --exclude-dir=node_modules --exclude='policy-check.sh' 2>/dev/null \
    | grep -v -iE '(never|forbidden|avoid|do not|warning|not allowed)' || true)
  if [[ -n "$add_all" ]]; then
    echo "  FAIL  git-add-A-usage"
    echo "$add_all" | head -5
    fail=1
  else
    echo "  PASS  git-add-A-usage"
  fi

  echo ""
  if (( fail == 0 )); then
    echo "  Overall: PASS"
  else
    echo "  Overall: FAIL"
  fi
  echo ""
  return $fail
}

# ── usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: policy-check.sh [OPTIONS]

Validates run-state objects and repo directories against policy rules.

Modes:
  --run-state <file>   Validate a run-state JSON file
  --repo <dir>         Scan a repo directory for policy violations
  --help               Show this help message

Exit codes:
  0   All checks passed
  1   One or more checks failed
EOF
}

# ── main ────────────────────────────────────────────────────────────────────

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --run-state)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --run-state requires a file argument" >&2
        exit 1
      fi
      banner
      check_run_state "$2"
      show_results
      if (( FAIL_COUNT > 0 )); then
        exit 1
      fi
      exit 0
      ;;
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --repo requires a directory argument" >&2
        exit 1
      fi
      banner
      check_repo "$2"
      if [[ $? -ne 0 ]]; then
        exit 1
      fi
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'. Use --help for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
