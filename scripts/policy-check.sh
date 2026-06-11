#!/usr/bin/env bash
# policy-check.sh — Validates run-state objects and repo dirs against policy rules.
# No external dependencies (no npm/pip/ajv). Uses python3 -c for JSON parsing.
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
RESULTS=()
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

write_policy_result_and_event() {
  local run_state="$1"
  local generated_dir run_dir overall
  generated_dir="$(cd "$(dirname "$run_state")" && pwd)"
  run_dir="$(dirname "$generated_dir")"
  if [[ "$(basename "$generated_dir")" != "generated" || ! -f "$run_dir/events.jsonl" ]]; then
    return 0
  fi
  if grep -q '"event_type":"POLICY_CHECKED"' "$run_dir/events.jsonl"; then
    return 0
  fi
  if (( FAIL_COUNT == 0 )); then
    overall="PASS"
  else
    overall="FAIL"
  fi
  python3 - "$run_dir/generated/policy-result.json" "$overall" "${RESULTS[@]}" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

out = pathlib.Path(sys.argv[1])
overall = sys.argv[2]
checks = []
for item in sys.argv[3:]:
    parts = item.split()
    if len(parts) >= 2:
        checks.append({"status": parts[0], "name": parts[1]})
out.write_text(json.dumps({
    "overall": overall,
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "checks": checks,
}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  "$SCRIPT_DIR/append-event.sh" \
    --run-dir "$run_dir" \
    --event-type POLICY_CHECKED \
    --actor harness \
    --state-after POLICY_CHECKED \
    --artifact generated/run-state.json \
    --artifact generated/policy-result.json >/dev/null
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
    return obj
v = g(d, '$expr')
if isinstance(v, (dict, list)):
    print(json.dumps(v))
elif isinstance(v, bool):
    print('true' if v else 'false')
elif v is None:
    print('')
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
    return obj
print(len(g(d, '$expr') or []))
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
        if obj is None:
            return []
    return obj if isinstance(obj, list) else []
arr = g(d, '$expr')
if not isinstance(arr, list): arr = []
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p, [])
        else:
            return []
    return obj if isinstance(obj, list) else []
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
        if obj is None:
            return []
    return obj if isinstance(obj, list) else []
arr = g(d, '$array_expr')
if not isinstance(arr, list): arr = []
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
        if isinstance(obj, list) and p.isdigit():
            idx = int(p)
            obj = obj[idx] if idx < len(obj) else None
        elif isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
        if obj is None:
            return []
    return obj if isinstance(obj, list) else []
arr = g(d, '$array_expr')
if not isinstance(arr, list): arr = []
found = any(item.get('$field') != '$value' and item.get('pass_fail') == 'PASS' for item in arr if isinstance(item, dict))
# More precise: check exit_code != 0 AND pass_fail == 'PASS'
found = any(item.get('exit_code', 0) != 0 and item.get('pass_fail') == 'PASS' for item in arr if isinstance(item, dict))
print('true' if found else 'false')
  "
}

jcheck_any_field_eq() {
  local f="$1" array="$2" field="$3" value="$4"
  python3 -c "
import json, sys
with open('$f') as fh:
    data = json.load(fh)
items = data.get('$array', [])
for item in items:
    v = item.get('$field')
    # Handle both string and boolean comparisons
    if v == '$value' or (isinstance(v, bool) and str(v).lower() == '$value'.lower()):
        print('true')
        sys.exit(0)
print('false')
" 2>/dev/null || echo "false"
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

jprovenance_violation() {
  # M/L generated run-states must be harness-generated and provenance-backed.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

scale = (d.get("classification") or {}).get("scale")
if scale not in {"M", "L"}:
    print("false")
    sys.exit(0)

if d.get("state_source") != "generated":
    print("true")
    sys.exit(0)

prov = d.get("provenance")
if not isinstance(prov, dict):
    print("true")
    sys.exit(0)

required = ["generated_by", "generated_at", "generator_version", "source_files"]
if any(not prov.get(key) for key in required):
    print("true")
    sys.exit(0)

if prov.get("generated_by") != "scripts/generate-run-state.sh":
    print("true")
    sys.exit(0)

sources = set(prov.get("source_files") or [])
if "run-manifest.json" not in sources or "raw/command-log.jsonl" not in sources:
    print("true")
    sys.exit(0)

print("false")
PY
}

jclaudecode_result_contract_violation() {
  # ClaudeCode may submit raw evidence but must not write final acceptance.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

raw = d.get("raw_evidence") or {}
if raw.get("claudecode_result_contains_acceptance") is True:
    print("true")
    sys.exit(0)

embedded = d.get("claudecode_result")
if isinstance(embedded, dict) and "acceptance" in embedded:
    print("true")
    sys.exit(0)

print("false")
PY
}

jtdd_command_log_violation() {
  # M/L TDD evidence must come from command_log_summary, not text-only fields.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

scale = (d.get("classification") or {}).get("scale")
if scale not in {"M", "L"}:
    print("false")
    sys.exit(0)

required_tdd = False
if (d.get("matt_evidence_gate") or {}).get("required_skill") == "tdd":
    required_tdd = True
for wo in d.get("work_orders") or []:
    if isinstance(wo, dict) and wo.get("required_matt_skill") == "tdd":
        required_tdd = True
for item in (d.get("skill_trace") or {}).get("claudecode_skills", []):
    if isinstance(item, dict) and item.get("name") == "tdd" and item.get("required") is True:
        required_tdd = True

if not required_tdd:
    print("false")
    sys.exit(0)

summary = d.get("command_log_summary")
if not isinstance(summary, dict):
    print("true")
    sys.exit(0)

sources = set((d.get("provenance") or {}).get("source_files") or [])
if summary.get("source") != "raw/command-log.jsonl" or "raw/command-log.jsonl" not in sources:
    print("true")
    sys.exit(0)

red_reason = ""
for wo in d.get("work_orders") or []:
    ev = wo.get("skill_evidence") if isinstance(wo, dict) else {}
    if isinstance(ev, dict) and ev.get("red_not_applicable_reason"):
        red_reason = ev.get("red_not_applicable_reason")

red_exit = summary.get("red_exit_code")
green_exit = summary.get("green_exit_code")

if red_reason:
    if green_exit != 0:
        print("true")
        sys.exit(0)
    print("false")
    sys.exit(0)

if not isinstance(red_exit, int) or red_exit == 0:
    print("true")
    sys.exit(0)
if green_exit != 0:
    print("true")
    sys.exit(0)
if summary.get("tdd_sequence_verified") is not True:
    print("true")
    sys.exit(0)

print("false")
PY
}

jfailed_run_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

status = d.get("status")
acceptance = d.get("acceptance") or {}
verification = d.get("verification") or {}
command_summary = d.get("command_log_summary") or {}
event_chain = d.get("event_chain") or {}
events = event_chain.get("event_types") or []
raw = d.get("raw_evidence") or {}

green_failed = isinstance(command_summary.get("green_exit_code"), int) and command_summary.get("green_exit_code") != 0

if not (status == "failed" or green_failed):
    print("false")
    sys.exit(0)

if status != "failed":
    print("true")
    sys.exit(0)
if acceptance.get("complete") is True:
    print("true")
    sys.exit(0)
if str(acceptance.get("final_decision", "")).upper() in {"PASS", "ACCEPTED"}:
    print("true")
    sys.exit(0)
if verification.get("tests_pass") is True:
    print("true")
    sys.exit(0)
if green_failed and "RUN_FAILED" not in events:
    print("true")
    sys.exit(0)
if green_failed and not raw.get("failure_result"):
    print("true")
    sys.exit(0)
if not isinstance(d.get("replay_result"), dict):
    print("true")
    sys.exit(0)
if event_chain.get("replay_pass") is not True:
    print("true")
    sys.exit(0)

print("false")
PY
}

jcodex_deferred_pass_violation() {
  # Codex cannot be PASS while the run says Codex was deferred.
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    d = json.load(f)

deferred = d.get("codex_deferred") or {}
if not (deferred.get("required") is True and deferred.get("deferred") is True):
    print("false")
    sys.exit(0)

codex = d.get("codex") or {}
if codex.get("plan_review_verdict") in {"PASS", "PASS_WITH_REQUIRED_CHANGES"}:
    print("true")
    sys.exit(0)
if codex.get("diff_review_verdict") in {"PASS", "PASS_WITH_REQUIRED_CHANGES"}:
    print("true")
    sys.exit(0)

print("false")
PY
}

jworker_result_contract_present_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

contract = d.get("worker_result_contract") or {}
worker_results = d.get("worker_results") or []
event_types = (d.get("event_chain") or {}).get("event_types") or []
required = contract.get("required") is True or "WORKER_RESULT_RECORDED" in event_types

if not required:
    print("false")
    sys.exit(0)

if worker_results:
    print("false")
    sys.exit(0)

if str(contract.get("deferred_reason", "")).strip():
    print("false")
    sys.exit(0)

print("true")
PY
}

jworker_acceptance_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

raw = d.get("raw_evidence") or {}
if raw.get("worker_result_acceptance_complete") is True:
    print("true")
    sys.exit(0)

for item in d.get("worker_results") or []:
    if isinstance(item, dict) and item.get("worker_acceptance_complete") is True:
        print("true")
        sys.exit(0)

for item in d.get("worker_result_violations") or []:
    if isinstance(item, dict) and "acceptance.complete=true" in str(item.get("violation", "")):
        print("true")
        sys.exit(0)

print("false")
PY
}

jworker_deferred_consistency_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

for item in d.get("worker_results") or []:
    if not isinstance(item, dict):
        continue
    deferred = item.get("deferred") is True or item.get("status") == "deferred" or item.get("review_verdict") == "DEFERRED"
    if deferred and not str(item.get("deferred_reason", "")).strip():
        print("true")
        sys.exit(0)

for item in d.get("worker_result_violations") or []:
    if isinstance(item, dict) and "deferred worker result missing reason" in str(item.get("violation", "")):
        print("true")
        sys.exit(0)

print("false")
PY
}

jcodex_worker_deferred_pass_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

for item in d.get("worker_results") or []:
    if not isinstance(item, dict) or item.get("worker") != "codex":
        continue
    deferred = item.get("deferred") is True or item.get("status") == "deferred"
    if deferred and item.get("review_verdict") == "PASS":
        print("true")
        sys.exit(0)

for item in d.get("worker_result_violations") or []:
    if isinstance(item, dict) and "deferred worker result reported PASS" in str(item.get("violation", "")):
        print("true")
        sys.exit(0)

print("false")
PY
}

jworker_raw_output_tracked_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1]).resolve()
with state_path.open(encoding="utf-8") as f:
    d = json.load(f)

worker_results = [item for item in (d.get("worker_results") or []) if isinstance(item, dict)]
if not worker_results:
    print("false")
    sys.exit(0)

sources = set((d.get("provenance") or {}).get("source_files") or [])
generated_parent = state_path.parent.name == "generated"
run_dir = state_path.parent.parent if generated_parent else None

for item in worker_results:
    raw_output = str(item.get("raw_output_path", "") or "")
    if not raw_output:
        print("true")
        sys.exit(0)
    if raw_output not in sources:
        print("true")
        sys.exit(0)
    if generated_parent and not (run_dir / raw_output).is_file():
        print("true")
        sys.exit(0)

print("false")
PY
}

jworker_invocation_truthfulness_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

for item in d.get("worker_results") or []:
    if not isinstance(item, dict):
        continue
    real_invocation = item.get("real_invocation")
    if real_invocation is False and item.get("official_worker_capture") is True:
        print("true")
        sys.exit(0)
print("false")
PY
}

jworker_invocation_evidence_present_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1]).resolve()
with state_path.open(encoding="utf-8") as f:
    d = json.load(f)

sources = set((d.get("provenance") or {}).get("source_files") or [])
generated_parent = state_path.parent.name == "generated"
run_dir = state_path.parent.parent if generated_parent else None

for item in d.get("worker_results") or []:
    if not isinstance(item, dict) or item.get("real_invocation") is not True:
        continue
    invocation_path = str(item.get("invocation_path", "") or "")
    if not invocation_path:
        print("true")
        sys.exit(0)
    if invocation_path not in sources:
        print("true")
        sys.exit(0)
    if generated_parent and not (run_dir / invocation_path).is_file():
        print("true")
        sys.exit(0)

print("false")
PY
}

jworker_invocation_skipped_consistency_violation() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

for item in d.get("worker_results") or []:
    if not isinstance(item, dict):
        continue
    if item.get("real_invocation") is False and not str(item.get("skipped_reason", "")).strip():
        print("true")
        sys.exit(0)

for item in d.get("worker_result_violations") or []:
    if isinstance(item, dict) and "skipped worker invocation missing skipped_reason" in str(item.get("violation", "")):
        print("true")
        sys.exit(0)

print("false")
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
            (non_empty(evidence.get("red")) or non_empty(evidence.get("red_not_applicable_reason")))
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

jv04_check() {
  # Usage: jv04_check <file> <check-name>
  local file="$1" check_name="$2"
  python3 - "$file" "$check_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)

check = sys.argv[2]
scale = (d.get("classification") or {}).get("scale")
status = d.get("status")
if scale not in {"M", "L"} and status != "failed":
    print("PASS")
    sys.exit(0)

event_chain = d.get("event_chain")
replay = d.get("replay_result")
provenance = d.get("provenance") or {}
sources = set(provenance.get("source_files") or [])
events = []
if isinstance(event_chain, dict):
    events = event_chain.get("event_types") or []
version = str(provenance.get("generator_version", ""))
v04_required = version.startswith("0.4") or isinstance(event_chain, dict) or isinstance(replay, dict)
if not v04_required:
    print("PASS")
    sys.exit(0)

def fail():
    print("FAIL")
    sys.exit(0)

def ok():
    print("PASS")
    sys.exit(0)

if check == "event-chain-provenance":
    if not isinstance(event_chain, dict):
        fail()
    if event_chain.get("source") != "events.jsonl":
        fail()
    if not event_chain.get("last_event_hash") or not event_chain.get("event_count"):
        fail()
    if "events.jsonl" not in sources or "generated/replay-result.json" not in sources:
        fail()
    ok()

if check == "replay-result":
    if not isinstance(replay, dict) or replay.get("replay_pass") is not True:
        fail()
    ok()

if check == "state-transition-validity":
    if not isinstance(replay, dict) or replay.get("failures"):
        fail()
    ok()

if check == "hash-chain-integrity":
    last_hash = event_chain.get("last_event_hash", "") if isinstance(event_chain, dict) else ""
    if not isinstance(replay, dict) or replay.get("replay_pass") is not True or len(last_hash) != 64:
        fail()
    ok()

if check == "artifact-hash-integrity":
    if not isinstance(replay, dict) or replay.get("replay_pass") is not True:
        fail()
    failures = replay.get("failures") or []
    if any("artifact" in str(item).lower() for item in failures):
        fail()
    ok()

if check == "no-final-report-before-policy":
    if "FINAL_REPORT_GENERATED" in events:
        if "POLICY_CHECKED" not in events:
            fail()
        if events.index("FINAL_REPORT_GENERATED") < events.index("POLICY_CHECKED"):
            fail()
    ok()

if check == "no-run-state-before-required-events":
    if "RUN_STATE_GENERATED" not in events:
        fail()
    idx = events.index("RUN_STATE_GENERATED")
    if "RUN_FAILED" in events and events.index("RUN_FAILED") < idx:
        ok()
    required = [
        "INTAKE_RECORDED",
        "WORK_ORDER_CREATED",
        "CLAUDECODE_DELEGATED",
        "COMMAND_RECORDED_RED",
        "COMMAND_RECORDED_GREEN",
        "CLAUDECODE_RESULT_RECORDED",
    ]
    for item in required:
        if item not in events or events.index(item) > idx:
            fail()
    ok()

if check == "no-green-before-red":
    if "COMMAND_RECORDED_GREEN" in events:
        if "COMMAND_RECORDED_RED" not in events:
            fail()
        if events.index("COMMAND_RECORDED_GREEN") < events.index("COMMAND_RECORDED_RED"):
            fail()
    ok()

if check == "no-complete-with-failed-policy":
    if "RUN_COMPLETED" in events:
        policy = d.get("policy_result") or {}
        if policy.get("overall") == "FAIL":
            fail()
    ok()

fail()
PY
}

# ── run-state checks ────────────────────────────────────────────────────────

check_run_state() {
  local f="$1"

  # 1. acceptance.complete && codex.diff_review_verdict != PASS && !disabled_by_user && scale != S
  # Allow NOT_REQUIRED when Codex is not needed for the task
  local acc_complete diff_verdict disabled scale
  acc_complete=$(jget "$f" "acceptance.complete" 2>/dev/null || echo "false")
  diff_verdict=$(jget "$f" "codex.diff_review_verdict" 2>/dev/null || echo "")
  disabled=$(jget "$f" "codex.disabled_by_user" 2>/dev/null || echo "false")
  scale=$(jget "$f" "classification.scale" 2>/dev/null || echo "")

  if [[ "$acc_complete" == "true" && "$diff_verdict" != "PASS" && "$diff_verdict" != "NOT_REQUIRED" && "$disabled" != "true" && "$scale" != "S" ]]; then
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
  plan_verdict=$(jget "$f" "codex.plan_review_verdict" 2>/dev/null || echo "")
  if [[ "$plan_verdict" == "FAIL" || "$plan_verdict" == "UNKNOWN" ]]; then
    record "plan-review-verdict" "FAIL"
  else
    record "plan-review-verdict" "PASS"
  fi

  # 4. scale=L AND plan_review_verdict=NOT_REQUIRED
  scale=$(jget "$f" "classification.scale" 2>/dev/null || echo "")
  plan_verdict=$(jget "$f" "codex.plan_review_verdict" 2>/dev/null || echo "")
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
  commit_approved=$(jget "$f" "approval_gates.commit_approved" 2>/dev/null || echo "false")
  tests_pass=$(jget "$f" "verification.tests_pass" 2>/dev/null || echo "false")
  if [[ "$commit_approved" == "true" && "$tests_pass" == "false" ]]; then
    record "commit-without-tests" "FAIL"
  else
    record "commit-without-tests" "PASS"
  fi

  # 7. mode must be dry_run/plan_only/auto_run
  local mode
  mode=$(jget "$f" "mode" 2>/dev/null || echo "")
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

  # 12. scale-classification: multi-module/system/tool/persistence but classification=S
  local scale_val modules_count has_persistence scale_violation=0
  scale_val=$(jget "$f" "classification.scale" 2>/dev/null || echo "")
  modules_count=$(jget "$f" "classification.modules_count" 2>/dev/null || echo "0")
  has_persistence=$(jget "$f" "classification.has_persistence" 2>/dev/null || echo "false")
  if [[ "$scale_val" == "S" ]]; then
    if [[ "$modules_count" =~ ^[0-9]+$ ]] && [[ "$modules_count" -gt 2 ]]; then
      scale_violation=1
    fi
    if [[ "$has_persistence" == "true" ]]; then
      scale_violation=1
    fi
  fi
  if [[ "$scale_violation" -eq 1 ]]; then
    record "scale-classification" "FAIL"
  else
    record "scale-classification" "PASS"
  fi

  # 13. ml-delegation: M/L must have ClaudeCode delegation or waiver.
  # For generated evidence runs, delegation requires raw/claudecode-result.json.
  local ml_delegated ml_waiver ml_raw_result ml_contract_valid
  ml_delegated=$(jget "$f" "claudecode_delegation.delegated" 2>/dev/null || echo "false")
  ml_waiver=$(jget "$f" "claudecode_delegation.waiver" 2>/dev/null || echo "false")
  ml_raw_result=$(jget "$f" "raw_evidence.claudecode_result" 2>/dev/null || echo "")
  ml_contract_valid=$(jget "$f" "raw_evidence.claudecode_result_contract_valid" 2>/dev/null || echo "")
  if [[ ("$scale_val" == "M" || "$scale_val" == "L") && "$ml_waiver" != "true" && ( "$ml_delegated" != "true" || -z "$ml_raw_result" || "$ml_contract_valid" == "false" ) ]]; then
    record "ml-delegation" "FAIL"
  else
    record "ml-delegation" "PASS"
  fi

  # 14. matt-evidence: required Matt skill must have evidence if acceptance.complete=true
  local matt_evidence_present matt_required
  matt_evidence_present=$(jget "$f" "matt_evidence_gate.evidence_present" 2>/dev/null || echo "false")
  matt_required=$(jget "$f" "matt_evidence_gate.required_skill" 2>/dev/null || echo "")
  if [[ "$acc_complete" == "true" && -n "$matt_required" && "$matt_evidence_present" != "true" ]]; then
    record "matt-evidence" "FAIL"
  else
    record "matt-evidence" "PASS"
  fi

  # 15. full-report-sections: full report must have all critical sections
  local report_scale_val all_present
  report_scale_val=$(jget "$f" "report_scale_enforcement.report_scale" 2>/dev/null || echo "")
  all_present=$(jget "$f" "report_scale_enforcement.all_present" 2>/dev/null || echo "true")
  if [[ "$report_scale_val" == "full" && "$all_present" != "true" ]]; then
    record "full-report-sections" "FAIL"
  else
    record "full-report-sections" "PASS"
  fi

  # 16. verification-exit-code: M/L tests_pass=true requires exit code evidence
  local tests_pass_val has_exit_codes
  tests_pass_val=$(jget "$f" "verification.tests_pass" 2>/dev/null || echo "false")
  has_exit_codes=$(jcheck_any_field_eq "$f" "verification_exit_codes" "pass" "true")
  if [[ ("$scale_val" == "M" || "$scale_val" == "L") && "$tests_pass_val" == "true" && "$has_exit_codes" != "true" ]]; then
    record "verification-exit-code" "FAIL"
  else
    record "verification-exit-code" "PASS"
  fi

  # 17. vague-intake: vague M/L tasks must have intake outputs
  local vague_task_val has_normalized_brief
  vague_task_val=$(jget "$f" "vague_task" 2>/dev/null || echo "false")
  has_normalized_brief=$(jget "$f" "intake_quality.normalized_task_brief" 2>/dev/null || echo "")
  if [[ "$vague_task_val" == "true" && ("$scale_val" == "M" || "$scale_val" == "L") && -z "$has_normalized_brief" ]]; then
    record "vague-intake" "FAIL"
  else
    record "vague-intake" "PASS"
  fi

  # 18. codex-deferred: if Codex required but deferred, must have reason
  local codex_required codex_deferred codex_reason
  codex_required=$(jget "$f" "codex_deferred.required" 2>/dev/null || echo "false")
  codex_deferred=$(jget "$f" "codex_deferred.deferred" 2>/dev/null || echo "false")
  codex_reason=$(jget "$f" "codex_deferred.reason" 2>/dev/null || echo "")
  if [[ "$codex_required" == "true" && "$codex_deferred" == "true" && -z "$codex_reason" ]]; then
    record "codex-deferred" "FAIL"
  else
    record "codex-deferred" "PASS"
  fi

  # 19. evidence-blocking-acceptance: matt_evidence_gate.blocking=true + evidence_present=false → acceptance.complete must be false
  local matt_blocking matt_present acc_complete_val
  matt_blocking=$(jget "$f" "matt_evidence_gate.blocking" 2>/dev/null || echo "false")
  matt_present=$(jget "$f" "matt_evidence_gate.evidence_present" 2>/dev/null || echo "false")
  acc_complete_val=$(jget "$f" "acceptance.complete" 2>/dev/null || echo "false")
  if [[ "$matt_blocking" == "true" && "$matt_present" != "true" && "$acc_complete_val" == "true" ]]; then
    record "evidence-blocking-acceptance" "FAIL"
  else
    record "evidence-blocking-acceptance" "PASS"
  fi

  # 20. codex-deferred-consistency: codex_deferred.deferred=true + required=true → acceptance.complete=true + status_color=green is forbidden
  local codex_def_req codex_def_val status_color
  codex_def_req=$(jget "$f" "codex_deferred.required" 2>/dev/null || echo "false")
  codex_def_val=$(jget "$f" "codex_deferred.deferred" 2>/dev/null || echo "false")
  status_color=$(jget "$f" "owner_summary.status_color" 2>/dev/null || echo "")
  if [[ "$codex_def_req" == "true" && "$codex_def_val" == "true" && "$acc_complete_val" == "true" && "$status_color" == "green" ]]; then
    record "codex-deferred-consistency" "FAIL"
  else
    record "codex-deferred-consistency" "PASS"
  fi

  # 21. self-improvement-side-effect: self_improvement_side_effect=true + no explicit_user_approval → FAIL
  local self_improve has_approval
  self_improve=$(jget "$f" "self_improvement_side_effect" 2>/dev/null || echo "false")
  has_approval=$(jget "$f" "explicit_user_approval" 2>/dev/null || echo "false")
  if [[ "$self_improve" == "true" && "$has_approval" != "true" ]]; then
    record "self-improvement-side-effect" "FAIL"
  else
    record "self-improvement-side-effect" "PASS"
  fi

  # 22. tdd-red-evidence: required_matt_skill=tdd → red must exist or red_not_applicable_reason must exist
  local tdd_required tdd_red tdd_reason tdd_red_trace
  tdd_required=$(jget "$f" "matt_evidence_gate.required_skill" 2>/dev/null || echo "")
  if [[ "$tdd_required" == "tdd" ]]; then
    tdd_red=$(jget "$f" "work_orders.0.skill_evidence.red" 2>/dev/null || echo "")
    tdd_reason=$(jget "$f" "work_orders.0.skill_evidence.red_not_applicable_reason" 2>/dev/null || echo "")
    # Also check skill_trace.claudecode_skills[].evidence.red
    tdd_red_trace=$(python3 -c "
import json, sys
with open('$f') as fh:
    d = json.load(fh)
for item in d.get('skill_trace', {}).get('claudecode_skills', []):
    if isinstance(item, dict) and item.get('name') == 'tdd':
        ev = item.get('evidence', {})
        if isinstance(ev, dict) and ev.get('red'):
            print('found')
            sys.exit(0)
print('')
" 2>/dev/null || echo "")
    if [[ -z "$tdd_red" && -z "$tdd_reason" && -z "$tdd_red_trace" ]]; then
      record "tdd-red-evidence" "FAIL"
    else
      record "tdd-red-evidence" "PASS"
    fi
  else
    record "tdd-red-evidence" "PASS"
  fi

  # 23. provenance: M/L run-state must be generated by harness with raw evidence source files.
  local provenance_bad
  provenance_bad=$(jprovenance_violation "$f")
  if [[ "$provenance_bad" == "true" ]]; then
    record "provenance" "FAIL"
  else
    record "provenance" "PASS"
  fi

  # 24. claudecode-result-contract: ClaudeCode result must not write final acceptance.
  local claudecode_contract_bad
  claudecode_contract_bad=$(jclaudecode_result_contract_violation "$f")
  local claudecode_contract_valid
  claudecode_contract_valid=$(jget "$f" "raw_evidence.claudecode_result_contract_valid" 2>/dev/null || echo "")
  local run_status raw_claudecode_path
  run_status=$(jget "$f" "status" 2>/dev/null || echo "")
  raw_claudecode_path=$(jget "$f" "raw_evidence.claudecode_result" 2>/dev/null || echo "")
  if [[ "$claudecode_contract_bad" == "true" || ( "$claudecode_contract_valid" == "false" && !( "$run_status" == "failed" && -z "$raw_claudecode_path" ) ) ]]; then
    record "claudecode-result-contract" "FAIL"
  else
    record "claudecode-result-contract" "PASS"
  fi

  # 25. tdd-command-log-evidence: M/L TDD needs RED/GREEN in command log summary.
  local tdd_command_log_bad
  tdd_command_log_bad=$(jtdd_command_log_violation "$f")
  if [[ "$tdd_command_log_bad" == "true" ]]; then
    record "tdd-command-log-evidence" "FAIL"
  else
    record "tdd-command-log-evidence" "PASS"
  fi

  # 26. codex-deferred-pass: deferred Codex must not be reported as PASS.
  local codex_deferred_pass_bad
  codex_deferred_pass_bad=$(jcodex_deferred_pass_violation "$f")
  if [[ "$codex_deferred_pass_bad" == "true" ]]; then
    record "codex-deferred-pass" "FAIL"
  else
    record "codex-deferred-pass" "PASS"
  fi

  local worker_result_missing_bad
  worker_result_missing_bad=$(jworker_result_contract_present_violation "$f")
  if [[ "$worker_result_missing_bad" == "true" ]]; then
    record "worker-result-contract-present" "FAIL"
  else
    record "worker-result-contract-present" "PASS"
  fi

  local worker_acceptance_bad
  worker_acceptance_bad=$(jworker_acceptance_violation "$f")
  if [[ "$worker_acceptance_bad" == "true" ]]; then
    record "worker-must-not-write-acceptance" "FAIL"
  else
    record "worker-must-not-write-acceptance" "PASS"
  fi
  if [[ "$worker_acceptance_bad" == "true" ]]; then
    record "worker-invocation-no-acceptance" "FAIL"
  else
    record "worker-invocation-no-acceptance" "PASS"
  fi

  local worker_deferred_bad
  worker_deferred_bad=$(jworker_deferred_consistency_violation "$f")
  if [[ "$worker_deferred_bad" == "true" ]]; then
    record "worker-result-deferred-consistency" "FAIL"
  else
    record "worker-result-deferred-consistency" "PASS"
  fi

  local codex_worker_deferred_pass_bad
  codex_worker_deferred_pass_bad=$(jcodex_worker_deferred_pass_violation "$f")
  if [[ "$codex_worker_deferred_pass_bad" == "true" ]]; then
    record "codex-deferred-no-pass" "FAIL"
  else
    record "codex-deferred-no-pass" "PASS"
  fi

  local worker_raw_output_bad
  worker_raw_output_bad=$(jworker_raw_output_tracked_violation "$f")
  if [[ "$worker_raw_output_bad" == "true" ]]; then
    record "worker-raw-output-tracked" "FAIL"
  else
    record "worker-raw-output-tracked" "PASS"
  fi

  local worker_invocation_truth_bad
  worker_invocation_truth_bad=$(jworker_invocation_truthfulness_violation "$f")
  if [[ "$worker_invocation_truth_bad" == "true" ]]; then
    record "worker-invocation-truthfulness" "FAIL"
  else
    record "worker-invocation-truthfulness" "PASS"
  fi

  local worker_invocation_evidence_bad
  worker_invocation_evidence_bad=$(jworker_invocation_evidence_present_violation "$f")
  if [[ "$worker_invocation_evidence_bad" == "true" ]]; then
    record "worker-invocation-evidence-present" "FAIL"
  else
    record "worker-invocation-evidence-present" "PASS"
  fi

  local worker_invocation_skipped_bad
  worker_invocation_skipped_bad=$(jworker_invocation_skipped_consistency_violation "$f")
  if [[ "$worker_invocation_skipped_bad" == "true" ]]; then
    record "worker-invocation-skipped-consistency" "FAIL"
  else
    record "worker-invocation-skipped-consistency" "PASS"
  fi

  local failed_run_bad
  failed_run_bad=$(jfailed_run_violation "$f")
  if [[ "$failed_run_bad" == "true" ]]; then
    record "failed-run-finalization" "FAIL"
  else
    record "failed-run-finalization" "PASS"
  fi

  local failed_run_status
  failed_run_status=$(jget "$f" "status" 2>/dev/null || echo "")
  if [[ "$failed_run_status" == "failed" ]]; then
    record "failed-run-status" "FAIL"
  else
    record "failed-run-status" "PASS"
  fi

  # v0.4 hash-linked state-machine checks.
  local v04_check_name v04_status
  for v04_check_name in \
    "event-chain-provenance" \
    "replay-result" \
    "state-transition-validity" \
    "hash-chain-integrity" \
    "artifact-hash-integrity" \
    "no-final-report-before-policy" \
    "no-run-state-before-required-events" \
    "no-green-before-red" \
    "no-complete-with-failed-policy"
  do
    v04_status=$(jv04_check "$f" "$v04_check_name")
    record "$v04_check_name" "$v04_status"
  done
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
      write_policy_result_and_event "$2"
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
