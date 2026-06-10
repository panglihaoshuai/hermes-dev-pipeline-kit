#!/usr/bin/env bash
# generate-run-state.sh — Derive generated/run-state.json from raw evidence.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-run-state.sh <run-dir>

Reads:
  run-manifest.json
  classification.json
  work-orders/*.json
  raw/command-log.jsonl
  raw/claudecode-result.json
  raw/worker/*.worker-result.json
  raw/files-touched.txt

Writes:
  generated/run-state.json
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

RUN_DIR="${1:-}"
if [[ -z "$RUN_DIR" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Error: run directory not found: $RUN_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$RUN_DIR/generated"

if [[ -s "$RUN_DIR/events.jsonl" ]]; then
  "$SCRIPT_DIR/replay-run.sh" "$RUN_DIR" >/dev/null
fi

python3 - "$RUN_DIR" <<'PY'
import glob
import json
import os
import pathlib
import sys
from datetime import datetime, timezone

run_dir = pathlib.Path(sys.argv[1]).resolve()


def rel(path):
    return str(path.relative_to(run_dir))


def load_json(path, default):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def first_nonempty(*values):
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
        if value not in (None, "", [], {}):
            return value
    return ""


manifest_path = run_dir / "run-manifest.json"
classification_path = run_dir / "classification.json"
command_log_path = run_dir / "raw" / "command-log.jsonl"
claude_result_path = run_dir / "raw" / "claudecode-result.json"
failure_result_path = run_dir / "raw" / "failure-result.json"
files_touched_path = run_dir / "raw" / "files-touched.txt"
replay_result_path = run_dir / "generated" / "replay-result.json"
worker_result_paths = sorted((run_dir / "raw" / "worker").glob("*.worker-result.json"))

manifest = load_json(manifest_path, {})
classification = load_json(classification_path, {
    "scale": "S",
    "reasons": ["classification.json missing; generator defaulted to S"],
    "risk_level": "low",
})
raw_claude_result = load_json(claude_result_path, {})
failure_result = load_json(failure_result_path, {})


def valid_claudecode_result(value):
    if not isinstance(value, dict) or not value:
        return False
    if "acceptance" in value:
        return False
    required = {
        "work_order_id",
        "status",
        "required_matt_skill",
        "matt_evidence",
        "files_touched",
        "commands_run",
        "blocked",
        "notes",
    }
    if not required.issubset(value):
        return False
    if value.get("status") not in {"completed", "blocked", "partial"}:
        return False
    if value.get("required_matt_skill") not in {"tdd", "diagnose", "prototype", "to-issues", "grill-me", "none"}:
        return False
    if not isinstance(value.get("files_touched"), list):
        return False
    if not isinstance(value.get("commands_run"), list):
        return False
    if not isinstance(value.get("blocked"), bool):
        return False
    if not isinstance(value.get("notes"), str):
        return False
    matt = value.get("matt_evidence")
    if not isinstance(matt, dict):
        return False
    if value.get("required_matt_skill") == "tdd":
        matt_required = {
            "red",
            "red_exit_code",
            "red_not_applicable_reason",
            "green",
            "green_exit_code",
            "commands",
        }
        if not matt_required.issubset(matt):
            return False
        if not isinstance(matt.get("commands"), list):
            return False
    return True


claude_contract_valid = valid_claudecode_result(raw_claude_result)
claude_result = raw_claude_result if claude_contract_valid else {}
replay_result = load_json(replay_result_path, {})
events_path = run_dir / "events.jsonl"
event_types = []
if events_path.exists():
    for line in events_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            event_types.append(json.loads(line).get("event_type", ""))


def worker_acceptance_complete(value):
    if not isinstance(value, dict):
        return False
    acceptance = value.get("acceptance")
    return isinstance(acceptance, dict) and acceptance.get("complete") is True


def worker_deferred_summary(value):
    if not isinstance(value, dict):
        return {"is_deferred": False, "reason": ""}
    deferred = value.get("deferred")
    if not isinstance(deferred, dict):
        return {"is_deferred": value.get("status") == "deferred", "reason": ""}
    return {
        "is_deferred": bool(deferred.get("is_deferred") or value.get("status") == "deferred"),
        "reason": str(deferred.get("reason", "") or ""),
    }


worker_results = []
worker_result_violations = []
for path in worker_result_paths:
    raw_worker = load_json(path, {})
    review = raw_worker.get("review") if isinstance(raw_worker.get("review"), dict) else {}
    deferred = worker_deferred_summary(raw_worker)
    attempted_acceptance = isinstance(raw_worker, dict) and "acceptance" in raw_worker
    acceptance_complete = worker_acceptance_complete(raw_worker)
    if acceptance_complete:
        worker_result_violations.append({
            "path": rel(path),
            "violation": "worker result attempted acceptance.complete=true",
        })
    if deferred["is_deferred"] and not deferred["reason"].strip():
        worker_result_violations.append({
            "path": rel(path),
            "violation": "deferred worker result missing reason",
        })
    if deferred["is_deferred"] and review.get("verdict") == "PASS":
        worker_result_violations.append({
            "path": rel(path),
            "violation": "deferred worker result reported PASS",
        })
    worker_results.append({
        "path": rel(path),
        "work_order_id": raw_worker.get("work_order_id", ""),
        "worker": raw_worker.get("worker", ""),
        "worker_skill": raw_worker.get("worker_skill", ""),
        "status": raw_worker.get("status", ""),
        "result_type": raw_worker.get("result_type", ""),
        "review_verdict": review.get("verdict", ""),
        "blocking_findings": review.get("blocking_findings", []) if isinstance(review.get("blocking_findings"), list) else [],
        "deferred": deferred["is_deferred"],
        "deferred_reason": deferred["reason"],
        "raw_output_path": raw_worker.get("raw_output_path", ""),
        "structured_output_path": raw_worker.get("structured_output_path", ""),
        "worker_attempted_acceptance": attempted_acceptance,
        "worker_acceptance_complete": acceptance_complete,
    })

command_log = []
if command_log_path.exists():
    for line in command_log_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            command_log.append(json.loads(line))

work_orders = []
for path in sorted((run_dir / "work-orders").glob("*.json")):
    work_orders.append(load_json(path, {}))

if not work_orders:
    work_orders = [{
        "id": claude_result.get("work_order_id", "WO-1"),
        "owner": "ClaudeCode",
        "required_skill": "hermes-dev-pipeline-kit",
        "required_matt_skill": claude_result.get("required_matt_skill", "tdd"),
        "status": "pending",
        "files": [],
        "retries": 0,
    }]

files_touched = []
if files_touched_path.exists():
    files_touched.extend(
        line.strip()
        for line in files_touched_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    )
files_touched.extend(claude_result.get("files_touched", []) or [])
files_touched = sorted(dict.fromkeys(files_touched))

required_matt_skill = claude_result.get("required_matt_skill")
if not required_matt_skill or required_matt_skill == "none":
    required_matt_skill = first_nonempty(
        work_orders[0].get("required_matt_skill"),
        "none",
    )

red_commands = [
    item for item in command_log
    if str(item.get("phase", "")).upper() == "RED" or "red" in str(item.get("step_id", "")).lower()
]
green_commands = [
    item for item in command_log
    if str(item.get("phase", "")).upper() == "GREEN" or "green" in str(item.get("step_id", "")).lower()
]
red_exit_codes = [item.get("exit_code") for item in red_commands if isinstance(item.get("exit_code"), int)]
green_exit_codes = [item.get("exit_code") for item in green_commands if isinstance(item.get("exit_code"), int)]
failed_command_items = [
    item for item in command_log
    if isinstance(item.get("exit_code"), int) and item.get("exit_code") != 0
]
green_failed = any(isinstance(code, int) and code != 0 for code in green_exit_codes)
failure_present = bool(failure_result) or "RUN_FAILED" in event_types or green_failed
selected_failure = failure_result if isinstance(failure_result, dict) else {}
if not selected_failure and failed_command_items:
    item = failed_command_items[-1]
    selected_failure = {
        "failed_phase": item.get("phase", ""),
        "failed_command": item.get("command", ""),
        "failed_exit_code": item.get("exit_code"),
        "reason": "command exited non-zero",
    }

red_not_applicable_reason = (
    claude_result.get("matt_evidence", {}).get("red_not_applicable_reason")
    if isinstance(claude_result.get("matt_evidence"), dict)
    else ""
)
red_ok = bool(red_not_applicable_reason) or any(code != 0 for code in red_exit_codes)
green_ok = any(code == 0 for code in green_exit_codes)
tdd_sequence_verified = bool(required_matt_skill == "tdd" and red_ok and green_ok)

red_summary = ""
if red_commands:
    red_summary = f"{red_commands[0].get('command')} exited {red_commands[0].get('exit_code')}"
green_summary = ""
if green_commands:
    green_summary = f"{green_commands[-1].get('command')} exited {green_commands[-1].get('exit_code')}"

skill_evidence = {}
if required_matt_skill == "tdd":
    skill_evidence = {
        "red": red_summary,
        "red_exit_code": red_exit_codes[0] if red_exit_codes else None,
        "red_not_applicable_reason": red_not_applicable_reason or "",
        "green": green_summary,
        "green_exit_code": green_exit_codes[-1] if green_exit_codes else None,
        "commands": [item.get("command", "") for item in command_log],
        "exit_codes": [item.get("exit_code") for item in command_log],
        "source": "raw/command-log.jsonl",
    }

for work_order in work_orders:
    work_order.setdefault("id", claude_result.get("work_order_id", "WO-1"))
    work_order.setdefault("owner", "ClaudeCode")
    work_order.setdefault("required_skill", "hermes-dev-pipeline-kit")
    if required_matt_skill != "none":
        work_order["required_matt_skill"] = required_matt_skill
    work_order["status"] = "blocked" if claude_result.get("blocked") else claude_result.get("status", work_order.get("status", "completed"))
    if work_order["status"] == "partial":
        work_order["status"] = "failed"
    if failure_present:
        work_order["status"] = "failed"
    work_order["files"] = sorted(dict.fromkeys(work_order.get("files", []) + files_touched))
    work_order.setdefault("retries", 0)
    if skill_evidence:
        work_order["skill_evidence"] = skill_evidence

generated_files = [
    path for path in files_touched
    if "generated" in path or ".gen." in os.path.basename(path) or ".generated." in os.path.basename(path)
]

command_evidence = []
for item in command_log:
    stdout = read_text(run_dir / item.get("stdout_path", ""))
    stderr = read_text(run_dir / item.get("stderr_path", ""))
    phase = item.get("phase") or item.get("step_id", "")
    key_output = (stdout or stderr or f"phase={phase}").strip().replace("\n", " ")[:240]
    command_evidence.append({
        "command": item.get("command", ""),
        "exit_code": int(item.get("exit_code", 0)),
        "key_output": key_output,
        "pass_fail": "PASS" if int(item.get("exit_code", 0)) == 0 else "FAIL",
    })

verification_exit_codes = [
    {
        "command": item.get("command", ""),
        "exit_code": int(item.get("exit_code", 0)),
        "pass": int(item.get("exit_code", 0)) == 0,
    }
    for item in command_log
]

scale = classification.get("scale", "S")
tests_pass = green_ok if required_matt_skill == "tdd" else all(int(item.get("exit_code", 0)) == 0 for item in command_log)
evidence_present = tdd_sequence_verified if required_matt_skill == "tdd" else bool(command_log or claude_result)
acceptance_complete = bool(claude_result.get("status") == "completed" and evidence_present and tests_pass)
worker_policy_failure = bool(worker_result_violations)
if failure_present or worker_policy_failure:
    tests_pass = False
    acceptance_complete = False
status_color = "yellow" if any(int(item.get("exit_code", 0)) != 0 for item in command_log) else "green"
if not acceptance_complete:
    status_color = "red" if claude_result.get("blocked") else "yellow"
if failure_present or worker_policy_failure:
    status_color = "red"

source_files = [
    rel(manifest_path),
    rel(classification_path),
    rel(command_log_path),
]
if claude_result_path.exists():
    source_files.append(rel(claude_result_path))
for path in sorted((run_dir / "work-orders").glob("*.json")):
    source_files.append(rel(path))
if files_touched_path.exists():
    source_files.append(rel(files_touched_path))
if replay_result_path.exists():
    source_files.append(rel(replay_result_path))
if failure_result_path.exists():
    source_files.append(rel(failure_result_path))
for path in sorted((run_dir / "raw" / "commands").glob("*.json")):
    source_files.append(rel(path))
for path in worker_result_paths:
    source_files.append(rel(path))
    worker_data = load_json(path, {})
    for key in ("raw_output_path", "structured_output_path"):
        value = worker_data.get(key, "")
        if isinstance(value, str) and value:
            candidate = run_dir / value
            if candidate.exists() and candidate.is_file():
                source_files.append(rel(candidate))

codex_deferred = claude_result.get("codex_deferred", {}) if isinstance(claude_result.get("codex_deferred"), dict) else {}
codex_required = scale == "L"
codex_is_deferred = bool(codex_deferred.get("deferred"))
codex_reason = codex_deferred.get("reason", "")
codex_verdict = "NOT_REQUIRED"
if codex_required and not codex_is_deferred:
    codex_verdict = "UNKNOWN"

state = {
    "run_id": manifest.get("run_id", run_dir.name),
    "status": "failed" if failure_present or worker_policy_failure else "completed" if acceptance_complete else "partial",
    "failed_phase": selected_failure.get("failed_phase", ""),
    "failed_command": selected_failure.get("failed_command", ""),
    "failed_exit_code": selected_failure.get("failed_exit_code"),
    "failure_reason": first_nonempty(selected_failure.get("reason"), selected_failure.get("failure_reason"), ""),
    "project": manifest.get("project", run_dir.parent.parent.name),
    "mode": manifest.get("requested_mode", "auto_run"),
    "current_gate": "Gate 8: generated evidence report",
    "classification": classification,
    "work_orders": work_orders,
    "worker_results": worker_results,
    "worker_result_contract": {
        "required": bool(worker_results or "WORKER_RESULT_RECORDED" in event_types),
        "deferred_reason": "",
        "source": "raw/worker/*.worker-result.json",
    },
    "worker_result_violations": worker_result_violations,
    "allowed_files": files_touched,
    "forbidden_files": [".env", "secrets.json", "~/.hermes", "~/.claude"],
    "modified_files": files_touched,
    "generated_files": generated_files,
    "generation_command_evidence": bool(generated_files and any("generate" in item.get("command", "").lower() for item in command_log)),
    "command_evidence": command_evidence,
    "codex": {
        "plan_review_verdict": codex_verdict,
        "diff_review_verdict": codex_verdict,
        "disabled_by_user": False,
    },
    "verification": {
        "git_diff_name_status": "\n".join(f"M\t{path}" for path in files_touched),
        "git_diff_check_exit": 0,
        "tests_pass": bool(tests_pass),
        "typecheck_exit": None,
    },
    "acceptance": {
        "complete": acceptance_complete,
        "final_decision": "ACCEPTED" if acceptance_complete else "FAIL" if failure_present or worker_policy_failure else "PARTIAL",
    },
    "approval_gates": {
        "commit_approved": False,
        "push_approved": False,
        "pr_approved": False,
        "repo_create_approved": False,
    },
    "report_scale": "full" if scale == "L" else "standard" if scale == "M" else "compact",
    "owner_summary_required": True,
    "stage_update_required": scale in {"M", "L"},
    "responsibility_trace_required": scale == "L" or any(int(item.get("exit_code", 0)) != 0 for item in command_log),
    "approval_inbox_required": False,
    "owner_summary": {
        "task": read_text(run_dir / "task.md").strip().splitlines()[0] if read_text(run_dir / "task.md").strip() else "Hermes evidence run",
        "status_color": status_color,
        "current_stage_label": "证据报告输出",
        "progress": {
            "intake": "完成",
            "planning": "完成",
            "work_order_split": "完成",
            "execution": "完成" if claude_result else "缺失",
            "verification": "完成" if command_log else "缺失",
            "codex_review": "不需要" if not codex_required else ("deferred" if codex_is_deferred else "UNKNOWN"),
            "approval": "未请求",
        },
            "largest_risk": first_nonempty(selected_failure.get("reason"), "worker result contract violation") if failure_present or worker_policy_failure else "TDD RED is expected failure and must be interpreted through command_log_summary",
        "needs_user_decision": False,
            "next_action": "Review generated/final-report.md and repair the failed evidence contract" if failure_present or worker_policy_failure else "Review generated/final-report.md; commit/push still requires approval",
    },
    "stage_updates": [
        {
            "from": "raw evidence collection",
            "to": "generated run-state",
            "tools_or_skills": ["scripts/generate-run-state.sh", "scripts/record-command.sh"],
            "goal": "从原始命令日志和 ClaudeCode result contract 派生状态",
            "next_gate_condition": "policy-check must validate generated/run-state.json",
            "needs_user_decision": False,
        }
    ],
    "responsibility_trace": [
        {
            "item": "raw command execution",
            "owner": "Hermes",
            "status": "completed",
            "evidence": "raw/command-log.jsonl",
            "blocking": bool(failure_present),
            "failure_owner": "Harness command execution" if failure_present else "Expected TDD RED" if any(int(item.get("exit_code", 0)) != 0 for item in command_log) else "",
        },
        {
            "item": "ClaudeCode result contract",
            "owner": "ClaudeCode",
            "status": "completed" if claude_result else "missing",
            "evidence": "raw/claudecode-result.json" if claude_result else "missing",
            "blocking": not bool(claude_result),
            "failure_owner": "" if claude_result else "ClaudeCode",
        },
        {
            "item": "worker result contract",
            "owner": "worker adapters",
            "status": "completed" if worker_results else "not-recorded",
            "evidence": ", ".join(item.get("path", "") for item in worker_results) if worker_results else "missing",
            "blocking": bool(worker_result_violations),
            "failure_owner": "worker" if worker_result_violations else "",
        },
    ],
    "approval_inbox": [],
    "baseline_debt": [],
    "follow_up_backlog": [],
    "skill_trace": {
        "display_language": "zh-CN",
        "current_phase_label": "证据报告输出",
        "user_visible_skill_banner": True,
        "hermes_skills": [
            {
                "name": "dev-pipeline-orchestrator",
                "planned": True,
                "used": True,
                "evidence": "run-manifest.json + generated/run-state.json",
                "verdict": "FAIL" if failure_present or worker_policy_failure else "PASS",
            }
        ],
        "claudecode_skills": [
            {
                "name": required_matt_skill,
                "required": required_matt_skill != "none",
                "reported": bool(claude_result),
                "evidence": skill_evidence,
                "verdict": "PASS" if evidence_present else "MISSING",
            }
        ] if required_matt_skill != "none" else [],
        "codex_gates": [
            {
                "name": "diff_review",
                "required": codex_required,
                "used": False,
                "evidence": codex_reason if codex_is_deferred else "NOT_REQUIRED" if not codex_required else "missing",
                "verdict": "SKIPPED" if not codex_required else "DEFERRED" if codex_is_deferred else "MISSING",
            }
        ],
        "missing_evidence": [] if evidence_present else ["required Matt skill evidence missing"],
        "acceptance_impact": "none" if evidence_present else "blocking",
    },
    "claudecode_delegation": {
        "delegated": bool(claude_contract_valid),
        "waiver": False,
        "waiver_reason": "",
    },
    "matt_evidence_gate": {
        "required_skill": required_matt_skill if required_matt_skill != "none" else "",
        "evidence_present": bool(evidence_present),
        "evidence_type": required_matt_skill if required_matt_skill in {"tdd", "diagnose", "prototype"} else "tdd",
        "blocking": required_matt_skill != "none",
    },
    "codex_deferred": {
        "deferred": codex_is_deferred,
        "reason": codex_reason,
        "required": codex_required,
    },
    "vague_task": False,
    "verification_exit_codes": verification_exit_codes,
    "self_improvement_side_effect": False,
    "explicit_user_approval": False,
    "command_log_summary": {
        "source": "raw/command-log.jsonl",
        "red_exit_code": red_exit_codes[0] if red_exit_codes else None,
        "green_exit_code": green_exit_codes[-1] if green_exit_codes else None,
        "red_command": red_commands[0].get("command", "") if red_commands else "",
        "green_command": green_commands[-1].get("command", "") if green_commands else "",
        "tdd_sequence_verified": tdd_sequence_verified,
    },
    "event_chain": {
        "source": "events.jsonl",
        "event_count": replay_result.get("event_count", 0),
        "last_event_hash": replay_result.get("last_event_hash", ""),
        "final_state": replay_result.get("final_state", ""),
        "replay_pass": bool(replay_result.get("replay_pass", False)),
        "event_types": event_types,
    },
    "replay_result": replay_result,
    "raw_evidence": {
        "run_manifest": "run-manifest.json",
        "classification": "classification.json",
        "command_log": "raw/command-log.jsonl",
        "command_records": [
            rel(path)
            for path in sorted((run_dir / "raw" / "commands").glob("*.json"))
        ],
        "claudecode_result": "raw/claudecode-result.json" if claude_result_path.exists() else "",
        "claudecode_result_contains_acceptance": isinstance(raw_claude_result, dict) and "acceptance" in raw_claude_result,
        "claudecode_result_contract_valid": bool(claude_contract_valid),
        "worker_results": [item.get("path", "") for item in worker_results],
        "worker_result_contains_acceptance": any(item.get("worker_attempted_acceptance") for item in worker_results),
        "worker_result_acceptance_complete": any(item.get("worker_acceptance_complete") for item in worker_results),
        "failure_result": "raw/failure-result.json" if failure_result_path.exists() else "",
    },
    "state_source": "generated",
    "provenance": {
        "generated_by": "scripts/generate-run-state.sh",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator_version": "0.4.0",
        "source_files": source_files,
    },
}

out = run_dir / "generated" / "run-state.json"
out.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(out)
PY

if [[ -s "$RUN_DIR/events.jsonl" ]]; then
  EVENT_ARTIFACTS=()
  if [[ -f "$RUN_DIR/raw/claudecode-result.json" ]]; then
    EVENT_ARTIFACTS+=(--artifact raw/claudecode-result.json)
  fi
  if [[ -f "$RUN_DIR/raw/failure-result.json" ]]; then
    EVENT_ARTIFACTS+=(--artifact raw/failure-result.json)
  fi
  while IFS= read -r worker_artifact; do
    EVENT_ARTIFACTS+=(--artifact "$worker_artifact")
  done < <(cd "$RUN_DIR" && find raw/worker -type f \( -name "*.worker-result.json" -o -name "*.raw.txt" -o -name "*.structured.json" \) 2>/dev/null | sort)
  if [[ ${#EVENT_ARTIFACTS[@]} -gt 0 ]]; then
    "$SCRIPT_DIR/append-event.sh" \
      --run-dir "$RUN_DIR" \
      --event-type RUN_STATE_GENERATED \
      --actor harness \
      --state-after RUN_STATE_GENERATED \
      "${EVENT_ARTIFACTS[@]}" >/dev/null
  else
    "$SCRIPT_DIR/append-event.sh" \
      --run-dir "$RUN_DIR" \
      --event-type RUN_STATE_GENERATED \
      --actor harness \
      --state-after RUN_STATE_GENERATED >/dev/null
  fi

  "$SCRIPT_DIR/replay-run.sh" "$RUN_DIR" >/dev/null

python3 - "$RUN_DIR" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1]).resolve()
run_state_path = run_dir / "generated" / "run-state.json"
replay_path = run_dir / "generated" / "replay-result.json"
events_path = run_dir / "events.jsonl"

state = json.loads(run_state_path.read_text(encoding="utf-8"))
replay = json.loads(replay_path.read_text(encoding="utf-8"))
event_types = []
if events_path.exists():
    for line in events_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            event_types.append(json.loads(line).get("event_type", ""))

state["event_chain"] = {
    "source": "events.jsonl",
    "event_count": replay.get("event_count", 0),
    "last_event_hash": replay.get("last_event_hash", ""),
    "final_state": replay.get("final_state", ""),
    "replay_pass": bool(replay.get("replay_pass", False)),
    "event_types": event_types,
}
state["replay_result"] = replay
extra_sources = ["events.jsonl", "state.json", "generated/replay-result.json"]
if (run_dir / "raw" / "failure-result.json").exists():
    extra_sources.append("raw/failure-result.json")
for path in sorted((run_dir / "raw" / "worker").glob("*")):
    if path.is_file():
        extra_sources.append(str(path.relative_to(run_dir)))
state["provenance"]["source_files"] = sorted(set(state["provenance"].get("source_files", []) + extra_sources))

run_state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
fi
