#!/usr/bin/env bash
# replay-run.sh — Replay and validate a v0.4 hash-linked run event ledger.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: replay-run.sh <run-dir>

Validates:
  - events.jsonl exists and is append-only JSONL
  - seq is contiguous
  - prev_event_hash links to the prior event_hash
  - event_hash equals sha256(canonical_json(event_without_event_hash))
  - artifact_hashes match current artifact bytes
  - basic state transitions are valid

Writes:
  generated/replay-result.json
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

python3 - "$RUN_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone

run_dir = pathlib.Path(sys.argv[1]).resolve()
events_path = run_dir / "events.jsonl"
state_path = run_dir / "state.json"
out_path = run_dir / "generated" / "replay-result.json"

STATE_FOR_EVENT = {
    "RUN_INIT": "RUN_INITIALIZED",
    "CLASSIFICATION_RECORDED": "CLASSIFIED",
    "INTAKE_RECORDED": "INTAKE_RECORDED",
    "WORK_ORDER_CREATED": "WORK_ORDER_CREATED",
    "CLAUDECODE_DELEGATED": "CLAUDECODE_DELEGATED",
    "COMMAND_RECORDED_RED": "RED_RECORDED",
    "COMMAND_RECORDED_GREEN": "GREEN_RECORDED",
    "CLAUDECODE_RESULT_RECORDED": "CLAUDECODE_RESULT_RECORDED",
    "RUN_STATE_GENERATED": "RUN_STATE_GENERATED",
    "POLICY_CHECKED": "POLICY_CHECKED",
    "FINAL_REPORT_GENERATED": "FINAL_REPORT_GENERATED",
    "APPROVAL_RECORDED": "APPROVAL_PENDING",
    "RUN_COMPLETED": "COMPLETED",
    "RUN_FAILED": "FAILED",
}


def canonical_hash(obj):
    payload = json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def load_json(path, default):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def load_events():
    if not events_path.exists():
        return []
    events = []
    for idx, line in enumerate(events_path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError as exc:
            failures.append(f"line {idx}: invalid JSON: {exc}")
    return events


def check_transition(state_before, event, seen):
    event_type = event.get("event_type")
    state_after = event.get("state_after")
    scale = classification.get("scale", "S")
    if event_type not in STATE_FOR_EVENT:
        return f"unknown event_type {event_type}"
    if STATE_FOR_EVENT[event_type] != state_after:
        return f"{event_type} has invalid state_after {state_after}"
    if event.get("state_before") != state_before:
        return f"{event_type} state_before {event.get('state_before')} != replay state {state_before}"
    if state_before == "NONE" and event_type != "RUN_INIT":
        return "first transition must be RUN_INIT"
    if event_type == "RUN_INIT" and state_before != "NONE":
        return "RUN_INIT repeated or not first"
    if event_type == "COMMAND_RECORDED_GREEN" and scale in {"M", "L"} and "COMMAND_RECORDED_RED" not in seen:
        return "M/L GREEN before RED"
    if event_type == "RUN_STATE_GENERATED" and scale in {"M", "L"}:
        required = {"INTAKE_RECORDED", "WORK_ORDER_CREATED", "CLAUDECODE_DELEGATED", "COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN", "CLAUDECODE_RESULT_RECORDED"}
        missing = sorted(required - seen)
        if missing:
            return "M/L RUN_STATE_GENERATED before required events: " + ",".join(missing)
    if event_type == "POLICY_CHECKED" and "RUN_STATE_GENERATED" not in seen:
        return "POLICY_CHECKED before RUN_STATE_GENERATED"
    if event_type == "FINAL_REPORT_GENERATED" and "POLICY_CHECKED" not in seen:
        return "FINAL_REPORT_GENERATED before POLICY_CHECKED"
    return ""


failures = []
if not run_dir.exists():
    failures.append(f"run directory missing: {run_dir}")

manifest = load_json(run_dir / "run-manifest.json", {})
classification = load_json(run_dir / "classification.json", {})
events = load_events()

prev_hash = ""
state = "NONE"
seen = set()
last_hash = ""
command_event_count = 0

if not events:
    failures.append("events.jsonl missing or empty")

for expected_seq, event in enumerate(events, 1):
    event_type = event.get("event_type", f"event-{expected_seq}")
    if event.get("seq") != expected_seq:
        failures.append(f"{event_type}: seq {event.get('seq')} != {expected_seq}")
    if event.get("prev_event_hash", "") != prev_hash:
        failures.append(f"{event_type}: prev_event_hash mismatch")
    without_hash = dict(event)
    event_hash = without_hash.pop("event_hash", "")
    expected_hash = canonical_hash(without_hash)
    if event_hash != expected_hash:
        failures.append(f"{event_type}: event_hash mismatch")
    if event_type in {"COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN"}:
        command_event_count += 1
    artifact_hashes = event.get("artifact_hashes") or {}
    for rel_path, expected_artifact_hash in artifact_hashes.items():
        artifact_path = run_dir / rel_path
        if not artifact_path.exists() or not artifact_path.is_file():
            failures.append(f"{event_type}: artifact missing: {rel_path}")
            continue
        if rel_path == "raw/command-log.jsonl" and event_type in {"COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN"}:
            lines = artifact_path.read_text(encoding="utf-8").splitlines()
            payload = ("\n".join(lines[:command_event_count]) + "\n").encode("utf-8")
            actual_hash = hashlib.sha256(payload).hexdigest()
        else:
            actual_hash = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
        if actual_hash != expected_artifact_hash:
            failures.append(f"{event_type}: artifact hash mismatch: {rel_path}")
    transition_failure = check_transition(state, event, seen)
    if transition_failure:
        failures.append(f"{event_type}: {transition_failure}")
    state = event.get("state_after", state)
    seen.add(event.get("event_type", ""))
    prev_hash = event_hash
    last_hash = event_hash

recorded_state = load_json(state_path, {})
if recorded_state:
    if recorded_state.get("last_event_hash") != last_hash:
        failures.append("state.json last_event_hash mismatch")
    if recorded_state.get("event_count") != len(events):
        failures.append("state.json event_count mismatch")
    if recorded_state.get("current_state") != state:
        failures.append("state.json current_state mismatch")

command_log_path = run_dir / "raw" / "command-log.jsonl"
if command_log_path.exists():
    line_count = len([line for line in command_log_path.read_text(encoding="utf-8").splitlines() if line.strip()])
    if line_count != command_event_count:
        failures.append(f"raw/command-log.jsonl line count {line_count} != command event count {command_event_count}")

result = {
    "replay_pass": not failures,
    "run_id": manifest.get("run_id", run_dir.name),
    "event_count": len(events),
    "final_state": state,
    "last_event_hash": last_hash,
    "failures": failures,
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(out_path)
sys.exit(0 if result["replay_pass"] else 1)
PY
