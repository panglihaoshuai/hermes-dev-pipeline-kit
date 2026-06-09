#!/usr/bin/env bash
# transition-check.sh — Validate a state-machine transition without mutating the run.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: transition-check.sh --run-dir <dir> --event-type <EVENT> --state-after <STATE> [--artifact <path> ...]

Checks current state, required ordering, and artifact existence.
EOF
}

RUN_DIR=""
EVENT_TYPE=""
STATE_AFTER=""
ARTIFACTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --event-type) EVENT_TYPE="${2:-}"; shift 2 ;;
    --state-after) STATE_AFTER="${2:-}"; shift 2 ;;
    --artifact) ARTIFACTS+=("${2:-}"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$EVENT_TYPE" || -z "$STATE_AFTER" ]]; then
  usage >&2
  exit 1
fi

python3 - "$RUN_DIR" "$EVENT_TYPE" "$STATE_AFTER" "${ARTIFACTS[@]:-}" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1]).resolve()
event_type = sys.argv[2]
state_after = sys.argv[3]
artifact_args = sys.argv[4:]

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


def load_json(path, default):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def read_events(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


if not run_dir.exists():
    fail(f"run directory not found: {run_dir}")
if event_type not in STATE_FOR_EVENT:
    fail(f"unknown event_type {event_type}")
if STATE_FOR_EVENT[event_type] != state_after:
    fail(f"{event_type} must transition to {STATE_FOR_EVENT[event_type]}")

for item in artifact_args:
    path = pathlib.Path(item)
    path = path.resolve() if path.is_absolute() else (run_dir / path).resolve()
    try:
        path.relative_to(run_dir)
    except ValueError:
        fail(f"artifact outside run directory: {path}")
    if not path.exists() or not path.is_file():
        fail(f"artifact missing: {path}")

events = read_events(run_dir / "events.jsonl")
seen = {event.get("event_type", "") for event in events}
state = load_json(run_dir / "state.json", {"current_state": "NONE"})
state_before = state.get("current_state", "NONE")
scale = load_json(run_dir / "classification.json", {}).get("scale", "S")

if event_type == "RUN_INIT" and state_before != "NONE":
    fail("RUN_INIT can only occur from NONE")
if event_type == "POLICY_CHECKED" and "RUN_STATE_GENERATED" not in seen:
    fail("POLICY_CHECKED requires RUN_STATE_GENERATED")
if event_type == "FINAL_REPORT_GENERATED" and "POLICY_CHECKED" not in seen:
    fail("FINAL_REPORT_GENERATED requires POLICY_CHECKED")
if event_type == "COMMAND_RECORDED_GREEN" and scale in {"M", "L"} and "COMMAND_RECORDED_RED" not in seen:
    fail("M/L GREEN requires prior RED")
if event_type == "RUN_STATE_GENERATED" and scale in {"M", "L"}:
    if "RUN_FAILED" not in seen:
        required = {"INTAKE_RECORDED", "WORK_ORDER_CREATED", "CLAUDECODE_DELEGATED", "COMMAND_RECORDED_RED", "COMMAND_RECORDED_GREEN", "CLAUDECODE_RESULT_RECORDED"}
        missing = sorted(required - seen)
        if missing:
            fail("M/L run-state missing required events: " + ",".join(missing))
if event_type == "RUN_COMPLETED" and "RUN_FAILED" in seen:
    fail("failed run cannot be completed")

print("PASS")
PY
