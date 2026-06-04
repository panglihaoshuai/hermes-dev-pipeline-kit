#!/usr/bin/env bash
# policy-check.sh — Validates run-state objects and repo dirs against policy rules.
# No external dependencies (no npm/pip/ajv). Uses python3 -c for JSON parsing.
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
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
  elif [[ "$status" == WARN* ]]; then
    (( WARN_COUNT++ )) || true
  else
    (( FAIL_COUNT++ )) || true
  fi
  RESULTS+=("  $status  $name")
}

show_results() {
  echo ""
  echo "--- Policy Checks ---"
  for r in "${RESULTS[@]}"; do echo "$r"; done
  local total=$(( PASS_COUNT + FAIL_COUNT + WARN_COUNT ))
  echo ""
  echo "--- Results ---"
  echo "  PASS: $PASS_COUNT / $total"
  if (( WARN_COUNT > 0 )); then
    echo "  WARN: $WARN_COUNT"
  fi
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

jgenerated_file_without_evidence() {
  # Returns 'true' if modified_files includes a generated file but no official
  # generation evidence is present.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import os
import re
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

modified_files = d.get("modified_files", [])
generated_files = set(d.get("generated_files", []))
generated_files.update(d.get("diff_summary", {}).get("generated_files", []))


def is_generated(path):
    base = os.path.basename(path)
    return (
        path in generated_files
        or base == "routeTree.gen.ts"
        or ".generated." in base
        or ".gen." in base
        or "generated" in path
    )


generated_modified = [p for p in modified_files if is_generated(p)]
if not generated_modified:
    print("false")
    sys.exit(0)

if d.get("generation_command_evidence") is True:
    print("false")
    sys.exit(0)

generation_pattern = re.compile(
    r"(generation[_ -]?command|official generation|regenerat|codegen|"
    r"generate|gen:|gen-|gen_|routeTree|tanstack|tsr|vite (dev|build))",
    re.IGNORECASE,
)

for item in d.get("command_evidence", []):
    if not isinstance(item, dict):
        continue
    text = f"{item.get('command', '')}\n{item.get('key_output', '')}"
    if generation_pattern.search(text):
        print("false")
        sys.exit(0)

print("true")
PY
}

jskill_trace_violation() {
  # Returns 'true' when skill trace/evidence policy is violated.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

MATT_SKILLS = {"tdd", "diagnose", "prototype", "to-issues", "grill-me"}
PASS_VERDICTS = {"PASS", "PASS_WITH_REQUIRED_CHANGES", "SKIPPED"}


def non_empty(value):
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


def evidence_complete(skill, evidence):
    if not isinstance(evidence, dict):
        return False

    if skill == "tdd":
        return (
            non_empty(evidence.get("red"))
            and non_empty(evidence.get("green"))
            and non_empty(evidence.get("commands"))
            and non_empty(evidence.get("exit_codes"))
        )
    if skill == "diagnose":
        return (
            non_empty(evidence.get("hypothesis"))
            and non_empty(evidence.get("test"))
            and non_empty(evidence.get("finding"))
            and (
                non_empty(evidence.get("fix_recommendation"))
                or non_empty(evidence.get("applied_fix"))
            )
        )
    if skill == "prototype":
        return (
            non_empty(evidence.get("variants_considered"))
            and non_empty(evidence.get("chosen_variant"))
            and non_empty(evidence.get("reason"))
        )
    if skill == "to-issues":
        return (
            non_empty(evidence.get("issue_breakdown"))
            and non_empty(evidence.get("acceptance_criteria"))
            and non_empty(evidence.get("priority"))
        )
    if skill == "grill-me":
        return (
            non_empty(evidence.get("challenge_questions"))
            and (
                non_empty(evidence.get("decisions_changed"))
                or non_empty(evidence.get("decisions_confirmed"))
            )
        )
    return non_empty(evidence)


acceptance_complete = bool(
    d.get("acceptance", {}).get("complete")
    or d.get("acceptance_complete")
)
skill_trace = d.get("skill_trace")

# Backward compatibility: old or partial run-states may omit skill_trace only
# while acceptance is not complete.
if acceptance_complete and not isinstance(skill_trace, dict):
    print("true")
    sys.exit(0)

if not isinstance(skill_trace, dict):
    print("false")
    sys.exit(0)

display_language = skill_trace.get("display_language")
if acceptance_complete and not non_empty(display_language):
    print("true")
    sys.exit(0)

if display_language == "zh-CN":
    if not non_empty(skill_trace.get("current_phase_label")):
        print("true")
        sys.exit(0)
    if skill_trace.get("user_visible_skill_banner") is not True:
        print("true")
        sys.exit(0)

clarification_questions = d.get("clarification_questions", [])
if not clarification_questions:
    clarification_questions = skill_trace.get("clarification_questions", [])
if clarification_questions:
    clarification_trace = skill_trace.get("clarification_trace")
    if not isinstance(clarification_trace, dict):
        print("true")
        sys.exit(0)
    if not non_empty(clarification_trace.get("why_questions_are_needed")):
        print("true")
        sys.exit(0)

if acceptance_complete:
    missing_evidence = skill_trace.get("missing_evidence", [])
    if missing_evidence:
        print("true")
        sys.exit(0)
    if skill_trace.get("acceptance_impact") in {"partial", "blocking"}:
        print("true")
        sys.exit(0)

required_matt = set()
for work_order in d.get("work_orders", []):
    if not isinstance(work_order, dict):
        continue
    skill = work_order.get("required_matt_skill")
    if skill in MATT_SKILLS:
        required_matt.add(skill)
    # Older work orders may only use required_skill for Matt skill routing.
    skill = work_order.get("required_skill")
    owner = str(work_order.get("owner", "")).lower()
    if skill in MATT_SKILLS and "claude" in owner:
        required_matt.add(skill)

for item in skill_trace.get("claudecode_skills", []):
    if not isinstance(item, dict):
        continue
    if item.get("required") is True and item.get("name") in MATT_SKILLS:
        required_matt.add(item["name"])

for skill in required_matt:
    trace_items = [
        item for item in skill_trace.get("claudecode_skills", [])
        if isinstance(item, dict) and item.get("name") == skill
    ]
    trace_ok = any(
        item.get("reported") is True
        and item.get("verdict") not in {"MISSING", "PARTIAL", "FAIL"}
        and evidence_complete(skill, item.get("evidence"))
        for item in trace_items
    )

    work_order_ok = any(
        isinstance(wo, dict)
        and wo.get("required_matt_skill") == skill
        and evidence_complete(skill, wo.get("skill_evidence"))
        for wo in d.get("work_orders", [])
    )

    if not (trace_ok or work_order_ok):
        print("true")
        sys.exit(0)

for item in skill_trace.get("codex_gates", []):
    if not isinstance(item, dict):
        continue
    if item.get("required") is True:
        if item.get("used") is not True:
            print("true")
            sys.exit(0)
        if item.get("verdict") not in {"PASS", "PASS_WITH_REQUIRED_CHANGES"}:
            print("true")
            sys.exit(0)

for item in skill_trace.get("hermes_skills", []):
    if not isinstance(item, dict):
        continue
    if item.get("used") is True:
        if not non_empty(item.get("evidence")):
            print("true")
            sys.exit(0)
        if item.get("verdict") not in PASS_VERDICTS:
            print("true")
            sys.exit(0)
    elif item.get("planned") is True:
        reason = item.get("skipped_reason") or item.get("reason")
        if not non_empty(reason):
            print("true")
            sys.exit(0)

print("false")
PY
}

jowner_summary_violation() {
  # Returns 'true' when owner summary / approval inbox policy is violated.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)


def non_empty(value):
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


acceptance_complete = bool(
    d.get("acceptance", {}).get("complete")
    or d.get("acceptance_complete")
)
if not acceptance_complete:
    print("false")
    sys.exit(0)

owner_summary = d.get("owner_summary")
if not isinstance(owner_summary, dict):
    print("true")
    sys.exit(0)

required_owner_fields = [
    "task",
    "status_color",
    "current_stage_label",
    "progress",
    "largest_risk",
    "needs_user_decision",
    "next_action",
]
if any(not non_empty(owner_summary.get(field)) for field in required_owner_fields):
    print("true")
    sys.exit(0)

approval_inbox = d.get("approval_inbox", [])
responsibility_trace = d.get("responsibility_trace", [])
needs_decision = owner_summary.get("needs_user_decision") is True
progress = owner_summary.get("progress", {})
approval_waiting = (
    isinstance(progress, dict)
    and str(progress.get("approval", "")).lower() in {"waiting", "等待审批"}
)
approval_gates = d.get("approval_gates", {})
commit_waiting = (
    acceptance_complete
    and isinstance(approval_gates, dict)
    and approval_gates.get("commit_approved") is False
    and owner_summary.get("current_stage_label") in {"Commit 审批", "Commit / Push / PR 审批"}
)

if (needs_decision or approval_waiting or commit_waiting) and not non_empty(approval_inbox):
    print("true")
    sys.exit(0)

status_color = str(owner_summary.get("status_color", "")).lower()
green_status = status_color in {"green", "绿"}
if green_status:
    verification = d.get("verification", {})
    if verification.get("tests_pass") is False:
        print("true")
        sys.exit(0)
    for item in d.get("command_evidence", []):
        if isinstance(item, dict) and item.get("pass_fail") == "FAIL":
            print("true")
            sys.exit(0)
    skill_trace = d.get("skill_trace", {})
    if isinstance(skill_trace, dict):
        if non_empty(skill_trace.get("missing_evidence")):
            print("true")
            sys.exit(0)
        if skill_trace.get("acceptance_impact") in {"partial", "blocking"}:
            print("true")
            sys.exit(0)

failure_exists = False
verification = d.get("verification", {})
if verification.get("tests_pass") is False:
    failure_exists = True
for item in d.get("command_evidence", []):
    if isinstance(item, dict) and item.get("pass_fail") == "FAIL":
        failure_exists = True
codex = d.get("codex", {})
if codex.get("plan_review_verdict") == "FAIL" or codex.get("diff_review_verdict") == "FAIL":
    failure_exists = True

if failure_exists:
    if not isinstance(responsibility_trace, list) or not responsibility_trace:
        print("true")
        sys.exit(0)
    has_failure_owner = any(
        isinstance(item, dict)
        and (
            item.get("blocking") is True
            or str(item.get("status", "")).lower() in {"fail", "failed", "blocked", "失败", "阻塞"}
            or non_empty(item.get("failure_owner"))
        )
        for item in responsibility_trace
    )
    if not has_failure_owner:
        print("true")
        sys.exit(0)

report_scale = d.get("report_scale")
classification = d.get("classification") or d.get("task_classification") or {}
scale = classification.get("scale")
if d.get("responsibility_trace_required") or report_scale == "full" or scale == "L":
    if not isinstance(responsibility_trace, list) or not responsibility_trace:
        print("true")
        sys.exit(0)

print("false")
PY
}

jreport_scale_status() {
  # Returns PASS, WARN, or FAIL for Chinese Report Scale Policy.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)


def non_empty(value):
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


def lower_text(value):
    if isinstance(value, (list, tuple)):
        return " ".join(lower_text(v) for v in value)
    if isinstance(value, dict):
        return " ".join(lower_text(v) for v in value.values())
    return str(value or "").lower()


classification = d.get("classification") or d.get("task_classification") or {}
scale = classification.get("scale")
reasons_text = lower_text(classification.get("reasons", []))
current_gate = lower_text(d.get("current_gate", ""))
mode = lower_text(d.get("mode") or d.get("pipeline_mode") or "")
report_scale = d.get("report_scale")
acceptance_complete = bool(d.get("acceptance", {}).get("complete") or d.get("acceptance_complete"))
stopped_reason = lower_text(d.get("stopped_reason", ""))

# A run-state that is correctly paused at an approval gate is not a final
# evidence report yet, so do not force full report metadata at this point.
if not acceptance_complete and "approval required" in stopped_reason:
    print("PASS")
    sys.exit(0)

# Backward-compatible default for older samples. New samples should set this
# explicitly; policy still validates scale mismatches when the field is present.
if not report_scale:
    report_scale = "full" if scale == "L" else "standard" if scale == "M" else "compact"

full_keywords = (
    "recovery",
    "publish",
    "release",
    "generated-file",
    "generated file",
    "security",
    "api/store/ui",
    "api + store",
    "store + ui",
)
full_required = (
    scale == "L"
    or any(k in reasons_text for k in full_keywords)
    or "publish" in current_gate
    or "publish" in mode
)

failure_exists = False
verification = d.get("verification", {})
if verification.get("tests_pass") is False:
    failure_exists = True
for key in ("command_evidence", "verification_evidence"):
    for item in d.get(key, []):
        if isinstance(item, dict) and item.get("pass_fail") == "FAIL":
            failure_exists = True
codex = d.get("codex") or d.get("codex_review") or {}
if codex.get("plan_review_verdict") in {"FAIL", "UNKNOWN"}:
    failure_exists = True
if codex.get("diff_review_verdict") in {"FAIL", "UNKNOWN"}:
    failure_exists = True
if d.get("acceptance", {}).get("final_decision") in {"NOT_ACCEPTED", "PARTIAL", "BLOCKED"}:
    failure_exists = True
if d.get("final_decision") in {"NOT_ACCEPTED", "PARTIAL", "BLOCKED"}:
    failure_exists = True

approval_required = False
owner_summary = d.get("owner_summary", {})
if isinstance(owner_summary, dict) and owner_summary.get("needs_user_decision") is True:
    approval_required = True
approval_gates = d.get("approval_gates", {})
if isinstance(approval_gates, dict) and any(k in current_gate for k in ("commit", "push", "pr", "publish", "approval", "审批")):
    if approval_gates.get("commit_approved") is False or approval_gates.get("push_approved") is False or approval_gates.get("pr_approved") is False:
        approval_required = True
if d.get("user_action_required") is True:
    approval_required = True
approval_keywords = (
    "commit",
    "push",
    "pr",
    "publish",
    "deploy",
    "install",
    "dependency",
    "global config",
    "全局配置",
    "安装依赖",
)
if any(k in reasons_text or k in current_gate for k in approval_keywords):
    approval_required = True

responsibility_required = bool(
    d.get("responsibility_trace_required")
    or failure_exists
    or full_required
)
approval_inbox_required = bool(d.get("approval_inbox_required") or approval_required)
stage_update_required = bool(d.get("stage_update_required") or scale in {"M", "L"} or full_required)
owner_summary_required = bool(d.get("owner_summary_required") or d.get("acceptance", {}).get("complete") or d.get("acceptance_complete"))

if report_scale not in {"compact", "standard", "full"}:
    print("FAIL")
    sys.exit(0)
if scale == "S" and report_scale == "full" and not failure_exists and not approval_required:
    print("WARN")
    sys.exit(0)
if full_required and report_scale == "compact":
    print("FAIL")
    sys.exit(0)

if report_scale == "compact" and acceptance_complete:
    # Strict Compact Report Contract: compact means shorter sections, not a
    # checklist-only report. Empty approval_inbox is allowed to mean "无", but
    # the section must be represented.
    if not isinstance(d.get("owner_summary"), dict):
        print("FAIL")
        sys.exit(0)
    if not non_empty(d.get("stage_updates")):
        print("FAIL")
        sys.exit(0)
    if not isinstance(d.get("skill_trace"), dict):
        print("FAIL")
        sys.exit(0)
    if not non_empty(d.get("responsibility_trace")):
        print("FAIL")
        sys.exit(0)
    if "approval_inbox" not in d or not isinstance(d.get("approval_inbox"), list):
        print("FAIL")
        sys.exit(0)

if owner_summary_required and not isinstance(d.get("owner_summary"), dict):
    print("FAIL")
    sys.exit(0)
if stage_update_required and not non_empty(d.get("stage_updates")):
    print("FAIL")
    sys.exit(0)
if responsibility_required and not non_empty(d.get("responsibility_trace")):
    print("FAIL")
    sys.exit(0)
if approval_inbox_required and not non_empty(d.get("approval_inbox")):
    print("FAIL")
    sys.exit(0)

green_status = str(owner_summary.get("status_color", "")).lower() in {"green", "绿"}
if green_status:
    if verification.get("tests_pass") is False:
        print("FAIL")
        sys.exit(0)
    for key in ("command_evidence", "verification_evidence"):
        for item in d.get(key, []):
            if isinstance(item, dict) and item.get("pass_fail") == "FAIL":
                print("FAIL")
                sys.exit(0)
    skill_trace = d.get("skill_trace", {})
    if isinstance(skill_trace, dict):
        if non_empty(skill_trace.get("missing_evidence")):
            print("FAIL")
            sys.exit(0)
        if skill_trace.get("acceptance_impact") in {"partial", "blocking"}:
            print("FAIL")
            sys.exit(0)

print("PASS")
PY
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

  # 8. generated file modified without official generation evidence
  local generated_without_evidence
  generated_without_evidence=$(jgenerated_file_without_evidence "$f")
  if [[ "$generated_without_evidence" == "true" ]]; then
    record "generated-file-without-evidence" "FAIL"
  else
    record "generated-file-without-evidence" "PASS"
  fi

  # 9. skill_trace must support acceptance and required skill evidence.
  local skill_trace_violation
  skill_trace_violation=$(jskill_trace_violation "$f")
  if [[ "$skill_trace_violation" == "true" ]]; then
    record "skill-trace-evidence" "FAIL"
  else
    record "skill-trace-evidence" "PASS"
  fi

  # 10. owner-facing summary, responsibility trace, and approval inbox.
  local owner_summary_violation
  owner_summary_violation=$(jowner_summary_violation "$f")
  if [[ "$owner_summary_violation" == "true" ]]; then
    record "owner-summary" "FAIL"
  else
    record "owner-summary" "PASS"
  fi

  # 11. report verbosity must match task scale and risk.
  local report_scale_status
  report_scale_status=$(jreport_scale_status "$f")
  record "report-scale" "$report_scale_status"
}

# ── report checks ───────────────────────────────────────────────────────────

check_report() {
  local f="$1"

  local skill_trace_violation
  skill_trace_violation=$(jskill_trace_violation "$f")
  if [[ "$skill_trace_violation" == "true" ]]; then
    record "skill-trace-evidence" "FAIL"
  else
    record "skill-trace-evidence" "PASS"
  fi

  local owner_summary_violation
  owner_summary_violation=$(jowner_summary_violation "$f")
  if [[ "$owner_summary_violation" == "true" ]]; then
    record "owner-summary" "FAIL"
  else
    record "owner-summary" "PASS"
  fi

  local report_scale_status
  report_scale_status=$(jreport_scale_status "$f")
  record "report-scale" "$report_scale_status"
}

# ── repo checks ─────────────────────────────────────────────────────────────

check_repo() {
  local dir="$1"
  local fail=0

  echo "--- Repo Checks ---"

  # 1. Secret patterns
  local secret_hits secret_pattern
  secret_pattern="API""_KEY|SEC""RET|TOK""EN|PASS""WORD|PRIVATE""_KEY"
  secret_hits=$(grep -rInE "(${secret_pattern})\\s*[:=]" "$dir" \
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
  local personal_hits user_name account_name project_name personal_pattern
  user_name="song""shiyao"
  account_name="pangli""haoshuai"
  project_name="resume""forcm"
  personal_pattern="(\\/Users\\/${user_name}|${account_name}|${project_name})"
  personal_hits=$(grep -rInE "$personal_pattern" "$dir" \
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
  --report <file>      Validate a dev-pipeline-report JSON file
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
    --report)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --report requires a file argument" >&2
        exit 1
      fi
      banner
      check_report "$2"
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
