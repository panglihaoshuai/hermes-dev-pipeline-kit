#!/usr/bin/env bash
# append-event.sh — Append a hash-linked state-machine event to a run.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: append-event.sh --run-dir <dir> --event-type <EVENT> --actor <actor> --state-after <STATE> [--artifact <path> ...]

Appends one event to <run-dir>/events.jsonl and updates <run-dir>/state.json.
Event hashes are sha256(canonical_json(event_without_event_hash)).
Artifacts are hashed relative to the run directory.
EOF
}

RUN_DIR=""
EVENT_TYPE=""
ACTOR=""
STATE_AFTER=""
ARTIFACTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --event-type) EVENT_TYPE="${2:-}"; shift 2 ;;
    --actor) ACTOR="${2:-}"; shift 2 ;;
    --state-after) STATE_AFTER="${2:-}"; shift 2 ;;
    --artifact) ARTIFACTS+=("${2:-}"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$EVENT_TYPE" || -z "$ACTOR" || -z "$STATE_AFTER" ]]; then
  usage >&2
  exit 1
fi

PY_ARGS=("$RUN_DIR" "$EVENT_TYPE" "$ACTOR" "$STATE_AFTER")
if [[ ${#ARTIFACTS[@]} -gt 0 ]]; then
  PY_ARGS+=("${ARTIFACTS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone

run_dir = pathlib.Path(sys.argv[1]).resolve()
event_type = sys.argv[2]
actor = sys.argv[3]
state_after = sys.argv[4]
artifact_args = sys.argv[5:]

events_path = run_dir / "events.jsonl"
state_path = run_dir / "state.json"

VALID_ACTORS = {"harness", "Hermes", "ClaudeCode", "Codex", "Owner"}
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


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def canonical_hash(obj):
    payload = json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def load_json(path, default):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def read_events():
    if not events_path.exists():
        return []
    events = []
    for line in events_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            events.append(json.loads(line))
    return events


def rel_artifact(path_text):
    path = pathlib.Path(path_text)
    if path.is_absolute():
        path = path.resolve()
    else:
        path = (run_dir / path).resolve()
    try:
        return str(path.relative_to(run_dir))
    except ValueError:
        fail(f"artifact outside run directory: {path}")


def artifact_hashes(paths):
    hashes = {}
    for item in paths:
        rel = rel_artifact(item)
        path = run_dir / rel
        if not path.exists() or not path.is_file():
            fail(f"artifact missing: {rel}")
        hashes[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def current_scale():
    classification = load_json(run_dir / "classification.json", {})
    return classification.get("scale", "S")


def event_types(events):
    return [item.get("event_type", "") for item in events]


def transition_allowed(state_before, event_type, events):
    scale = current_scale()
    seen = set(event_types(events))

    if event_type not in STATE_FOR_EVENT:
        return False, f"unknown event_type {event_type}"
    if STATE_FOR_EVENT[event_type] != state_after:
        return False, f"{event_type} must transition to {STATE_FOR_EVENT[event_type]}"

    if state_before == "NONE":
        return (event_type == "RUN_INIT", "RUN_INIT required from NONE")
    if event_type == "RUN_INIT":
        return False, "RUN_INIT can only occur once from NONE"
    if event_type in seen and event_type not in {"COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN"}:
        return False, f"duplicate event_type {event_type}"

    if event_type == "CLASSIFICATION_RECORDED":
        return (state_before == "RUN_INITIALIZED", "classification must follow RUN_INIT")
    if event_type == "INTAKE_RECORDED":
        return (state_before == "CLASSIFIED", "intake must follow classification")
    if event_type == "WORK_ORDER_CREATED":
        if scale in {"M", "L"} and "INTAKE_RECORDED" not in seen:
            return False, "M/L work order requires intake first"
        return (state_before in {"CLASSIFIED", "INTAKE_RECORDED"}, "work order must follow intake/classification")
    if event_type == "CLAUDECODE_DELEGATED":
        return (state_before == "WORK_ORDER_CREATED", "delegation must follow work order")
    if event_type == "COMMAND_RECORDED_RED":
        if scale in {"M", "L"}:
            return (state_before == "CLAUDECODE_DELEGATED", "M/L RED must follow delegation")
        return (state_before in {"CLASSIFIED", "WORK_ORDER_CREATED", "CLAUDECODE_DELEGATED"}, "RED not allowed here")
    if event_type == "COMMAND_RECORDED_GREEN":
        if scale in {"M", "L"}:
            return ("COMMAND_RECORDED_RED" in seen and state_before == "RED_RECORDED", "M/L GREEN must follow RED")
        return (state_before in {"CLASSIFIED", "RED_RECORDED"}, "S GREEN must follow classification or RED")
    if event_type == "CLAUDECODE_RESULT_RECORDED":
        return (state_before == "GREEN_RECORDED", "ClaudeCode result must follow GREEN")
    if event_type == "RUN_STATE_GENERATED":
        if "RUN_FAILED" in seen:
            return (state_before == "FAILED", "failed run-state must follow RUN_FAILED")
        if scale in {"M", "L"}:
            required = {"INTAKE_RECORDED", "WORK_ORDER_CREATED", "CLAUDECODE_DELEGATED", "COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN", "CLAUDECODE_RESULT_RECORDED"}
            missing = sorted(required - seen)
            if missing:
                return False, f"M/L run-state missing required events: {','.join(missing)}"
            return (state_before == "CLAUDECODE_RESULT_RECORDED", "M/L run-state must follow ClaudeCode result")
        return (
            "COMMAND_RECORDED_GREEN" in seen
            and state_before in {"GREEN_RECORDED", "CLAUDECODE_RESULT_RECORDED"},
            "S run-state must follow GREEN or ClaudeCode result",
        )
    if event_type == "POLICY_CHECKED":
        return (state_before == "RUN_STATE_GENERATED", "policy must follow generated run-state")
    if event_type == "FINAL_REPORT_GENERATED":
        return (state_before == "POLICY_CHECKED", "final report must follow policy")
    if event_type == "APPROVAL_RECORDED":
        return (state_before == "FINAL_REPORT_GENERATED", "approval must follow final report")
    if event_type == "RUN_COMPLETED":
        if "RUN_FAILED" in seen:
            return False, "failed run cannot be completed"
        return (state_before in {"FINAL_REPORT_GENERATED", "APPROVAL_PENDING"}, "completion must follow final report or approval")
    if event_type == "RUN_FAILED":
        return True, ""
    return False, "transition not allowed"


if actor not in VALID_ACTORS:
    fail(f"invalid actor {actor}")
if not run_dir.exists():
    fail(f"run directory not found: {run_dir}")

events = read_events()
state = load_json(state_path, {"current_state": "NONE", "event_count": 0, "last_event_hash": ""})
state_before = state.get("current_state", "NONE")

ok, reason = transition_allowed(state_before, event_type, events)
if not ok:
    fail(reason)

prev_hash = events[-1].get("event_hash", "") if events else ""
run_id = load_json(run_dir / "run-manifest.json", {}).get("run_id", run_dir.name)
artifact_map = artifact_hashes(artifact_args)

event = {
    "seq": len(events) + 1,
    "run_id": run_id,
    "event_type": event_type,
    "state_before": state_before,
    "state_after": state_after,
    "actor": actor,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "artifact_paths": sorted(artifact_map),
    "artifact_hashes": artifact_map,
    "prev_event_hash": prev_hash,
}
event["event_hash"] = canonical_hash(event)

with events_path.open("a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")

next_state = {
    "run_id": run_id,
    "current_state": state_after,
    "last_event_hash": event["event_hash"],
    "event_count": event["seq"],
    "updated_at": event["timestamp"],
}
state_path.write_text(json.dumps(next_state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(event["event_hash"])
PY
