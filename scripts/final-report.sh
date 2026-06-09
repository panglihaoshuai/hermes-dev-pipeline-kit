#!/usr/bin/env bash
# final-report.sh — Generate an owner-facing Chinese report from run-state.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: final-report.sh <generated/run-state.json>

Prints the report to stdout. If the input path is inside a generated/
directory, also writes generated/final-report.md.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

STATE_FILE="${1:-}"
if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  usage >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")"

if [[ "$(basename "$(dirname "$STATE_FILE")")" == "generated" ]]; then
  RUN_DIR="$(dirname "$(dirname "$STATE_FILE")")"
  if [[ -f "$RUN_DIR/events.jsonl" ]]; then
    "$SCRIPT_DIR/replay-run.sh" "$RUN_DIR" >/dev/null
    if ! grep -q '"event_type":"POLICY_CHECKED"' "$RUN_DIR/events.jsonl"; then
      echo "Error: final report requires POLICY_CHECKED event" >&2
      exit 1
    fi
    if ! grep -q '"event_type":"FINAL_REPORT_GENERATED"' "$RUN_DIR/events.jsonl"; then
      ARTIFACT_ARGS=(--artifact generated/run-state.json)
      if [[ -f "$RUN_DIR/generated/policy-result.json" ]]; then
        ARTIFACT_ARGS+=(--artifact generated/policy-result.json)
      fi
      "$SCRIPT_DIR/append-event.sh" \
        --run-dir "$RUN_DIR" \
        --event-type FINAL_REPORT_GENERATED \
        --actor harness \
        --state-after FINAL_REPORT_GENERATED \
        "${ARTIFACT_ARGS[@]}" >/dev/null
    fi
    "$SCRIPT_DIR/replay-run.sh" "$RUN_DIR" >/dev/null
  fi
fi

python3 - "$STATE_FILE" <<'PY'
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1]).resolve()
state = json.loads(state_path.read_text(encoding="utf-8"))


def val(path, default=""):
    cur = state
    for part in path.split("."):
        if not isinstance(cur, dict):
            return default
        cur = cur.get(part, default)
    return cur


owner = state.get("owner_summary", {})
classification = state.get("classification", {})
verification = state.get("verification", {})
acceptance = state.get("acceptance", {})
provenance = state.get("provenance", {})
command_summary = state.get("command_log_summary", {})
skill_trace = state.get("skill_trace", {})
event_chain = state.get("event_chain", {})
replay_result = state.get("replay_result", {})
policy_result = {}
policy_path = state_path.parent / "policy-result.json"
replay_path = state_path.parent / "replay-result.json"
if policy_path.exists():
    policy_result = json.loads(policy_path.read_text(encoding="utf-8"))
if replay_path.exists():
    replay_result = json.loads(replay_path.read_text(encoding="utf-8"))
    event_chain = {
        "event_count": replay_result.get("event_count", event_chain.get("event_count", 0)),
        "last_event_hash": replay_result.get("last_event_hash", event_chain.get("last_event_hash", "")),
        "final_state": replay_result.get("final_state", event_chain.get("final_state", "")),
        "replay_pass": replay_result.get("replay_pass", event_chain.get("replay_pass", False)),
    }

lines = []
lines.append("# Dev Pipeline Evidence Report")
lines.append("")
lines.append("## 负责人摘要")
lines.append("")
lines.append(f"- 状态：{owner.get('status_color', 'unknown')}")
lines.append(f"- 任务：{owner.get('task', state.get('run_id', 'unknown'))}")
lines.append(f"- 当前阶段：{owner.get('current_stage_label', state.get('current_gate', 'unknown'))}")
lines.append(f"- 最大风险：{owner.get('largest_risk', 'unknown')}")
lines.append(f"- 下一步：{owner.get('next_action', 'unknown')}")
lines.append(f"- 验收完成：{str(acceptance.get('complete', False)).lower()}")
lines.append(f"- 最终决定：{acceptance.get('final_decision', 'UNKNOWN')}")
lines.append(f"- run_id：{state.get('run_id', '')}")
lines.append(f"- run status：{state.get('status', 'unknown')}")
lines.append(f"- final_state：{event_chain.get('final_state', '')}")
lines.append(f"- last_event_hash：{event_chain.get('last_event_hash', '')}")
lines.append(f"- replay_pass：{event_chain.get('replay_pass', False)}")
lines.append(f"- policy verdict：{policy_result.get('overall', 'UNKNOWN')}")
lines.append("")

if state.get("status") == "failed":
    lines.append("## Failure Details")
    lines.append("")
    lines.append(f"- failed_phase: {state.get('failed_phase', '')}")
    lines.append(f"- failed_command: {state.get('failed_command', '')}")
    lines.append(f"- failed_exit_code: {state.get('failed_exit_code', '')}")
    lines.append(f"- failure_reason: {state.get('failure_reason', '')}")
    lines.append(f"- replay_pass: {event_chain.get('replay_pass', False)}")
    lines.append(f"- policy verdict: {policy_result.get('overall', 'UNKNOWN')}")
    missing = []
    run_root = state_path.parent.parent
    for rel_path in (
        "raw/failure-result.json",
        "generated/run-state.json",
        "generated/replay-result.json",
        "generated/policy-result.json",
        "generated/final-report.md",
    ):
        if not (run_root / rel_path).exists():
            missing.append(rel_path)
    if missing:
        lines.append("- missing artifacts:")
        for item in missing:
            lines.append(f"  - {item}")
    else:
        lines.append("- missing artifacts: none")
    lines.append(f"- next action: {owner.get('next_action', 'repair failed command and rerun verification')}")
    lines.append("")

lines.append("## 阶段更新")
lines.append("")
for item in state.get("stage_updates", []):
    lines.append(f"- {item.get('from', '?')} → {item.get('to', '?')}：{item.get('goal', '')}")
if not state.get("stage_updates"):
    lines.append("- 无阶段更新。")
lines.append("")

lines.append("## 技能使用证据")
lines.append("")
lines.append("| layer | skill/tool | planned/required | used/reported | evidence | verdict |")
lines.append("|---|---|---:|---:|---|---|")
for item in skill_trace.get("hermes_skills", []):
    lines.append(
        f"| Hermes | {item.get('name', '')} | {item.get('planned', False)} | "
        f"{item.get('used', False)} | {item.get('evidence', '')} | {item.get('verdict', '')} |"
    )
for item in skill_trace.get("claudecode_skills", []):
    evidence = item.get("evidence", {})
    if isinstance(evidence, dict):
        evidence_text = "; ".join(
            str(evidence.get(key, ""))
            for key in ("red", "green", "source")
            if evidence.get(key, "") not in ("", None)
        )
    else:
        evidence_text = str(evidence)
    lines.append(
        f"| ClaudeCode/Matt | {item.get('name', '')} | {item.get('required', False)} | "
        f"{item.get('reported', False)} | {evidence_text} | {item.get('verdict', '')} |"
    )
for item in skill_trace.get("codex_gates", []):
    lines.append(
        f"| Codex | {item.get('name', '')} | {item.get('required', False)} | "
        f"{item.get('used', False)} | {item.get('evidence', '')} | {item.get('verdict', '')} |"
    )
lines.append("")

lines.append("## 责任归因")
lines.append("")
lines.append("| item | owner | status | evidence | blocking |")
lines.append("|---|---|---|---|---:|")
for item in state.get("responsibility_trace", []):
    lines.append(
        f"| {item.get('item', '')} | {item.get('owner', '')} | {item.get('status', '')} | "
        f"{item.get('evidence', '')} | {item.get('blocking', False)} |"
    )
if not state.get("responsibility_trace"):
    lines.append("| 无 | - | - | - | false |")
lines.append("")

lines.append("## 待你审批")
lines.append("")
approval = state.get("approval_inbox", [])
if approval:
    for item in approval:
        lines.append(f"- {item.get('id', '')}: {item.get('item', '')} — {item.get('why_approval_required', '')}")
else:
    lines.append("- 无")
lines.append("")

lines.append("## Verification Evidence")
lines.append("")

lines.append("## State Machine Evidence")
lines.append("")
lines.append(f"- events.jsonl: {state_path.parent.parent / 'events.jsonl'}")
lines.append(f"- state.json: {state_path.parent.parent / 'state.json'}")
lines.append(f"- replay-result.json: {state_path.parent / 'replay-result.json'}")
lines.append(f"- event_count: {event_chain.get('event_count', 0)}")
lines.append(f"- final_state: {event_chain.get('final_state', '')}")
lines.append(f"- last_event_hash: {event_chain.get('last_event_hash', '')}")
lines.append(f"- replay_pass: {event_chain.get('replay_pass', False)}")
failed = replay_result.get("failures", []) if isinstance(replay_result, dict) else []
if failed:
    lines.append("- failed gates:")
    for item in failed:
        lines.append(f"  - {item}")
else:
    lines.append("- failed gates: none")
lines.append("")
lines.append(f"- tests_pass: {verification.get('tests_pass', False)}")
lines.append(f"- git_diff_check_exit: {verification.get('git_diff_check_exit', '')}")
lines.append(f"- typecheck_exit: {verification.get('typecheck_exit', '')}")
lines.append(f"- RED command: {command_summary.get('red_command', '')} / exit {command_summary.get('red_exit_code', '')}")
lines.append(f"- GREEN command: {command_summary.get('green_command', '')} / exit {command_summary.get('green_exit_code', '')}")
lines.append(f"- TDD sequence verified from command log: {command_summary.get('tdd_sequence_verified', False)}")
lines.append("")

lines.append("## Evidence Ownership")
lines.append("")
lines.append("- agent writes raw evidence: yes")
lines.append("- harness generates run-state: yes")
lines.append("- policy-check validates generated run-state: yes")
lines.append("- final report generated from run-state: yes")
lines.append("")

lines.append("## Provenance")
lines.append("")
lines.append(f"- generated_by: {provenance.get('generated_by', '')}")
lines.append(f"- generated_at: {provenance.get('generated_at', '')}")
lines.append(f"- generator_version: {provenance.get('generator_version', '')}")
lines.append("- source_files:")
for source in provenance.get("source_files", []):
    lines.append(f"  - {source}")
lines.append("")

report = "\n".join(lines)
print(report)

if state_path.parent.name == "generated":
    (state_path.parent / "final-report.md").write_text(report + "\n", encoding="utf-8")
PY
