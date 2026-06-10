#!/usr/bin/env bash
# record-command.sh — Execute a command and append immutable raw command facts.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: record-command.sh --run-dir <dir> [OPTIONS] -- <command> [args...]

Options:
  --cwd <dir>       Working directory. Defaults to current directory.
  --step-id <id>    Logical step id. Defaults to step-<n>.
  --phase <phase>   free text phase label such as RED, GREEN, VERIFY.
  --help            Show this help.

The wrapped command's stdout/stderr are saved under raw/stdout and raw/stderr.
The wrapper exits with the wrapped command's exit code after logging it.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RUN_DIR=""
CWD="$(pwd)"
STEP_ID=""
PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    --step-id) STEP_ID="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "Error: unknown argument before --: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || $# -eq 0 ]]; then
  echo "Error: --run-dir and command after -- are required" >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$RUN_DIR/raw" ]]; then
  echo "Error: run raw directory not found: $RUN_DIR/raw" >&2
  exit 1
fi

mkdir -p "$RUN_DIR/raw/commands" "$RUN_DIR/raw/stdout" "$RUN_DIR/raw/stderr"
LOG="$RUN_DIR/raw/command-log.jsonl"
touch "$LOG"

if [[ ! -d "$CWD" ]]; then
  echo "Error: cwd not found: $CWD" >&2
  exit 1
fi
CWD="$(cd "$CWD" && pwd)"

SEQ="$(($(wc -l < "$LOG" | tr -d ' ') + 1))"
if [[ -z "$STEP_ID" ]]; then
  STEP_ID="step-$SEQ"
fi

SAFE_STEP="$(printf "%s" "$STEP_ID" | tr -c 'A-Za-z0-9_.-' '_')"
COMMAND_ID="$(printf "cmd-%04d" "$SEQ")"
COMMAND_RECORD_REL="raw/commands/${COMMAND_ID}.json"
COMMAND_RECORD_PATH="$RUN_DIR/$COMMAND_RECORD_REL"
STDOUT_REL="raw/stdout/${COMMAND_ID}.out"
STDERR_REL="raw/stderr/${COMMAND_ID}.err"
STDOUT_PATH="$RUN_DIR/$STDOUT_REL"
STDERR_PATH="$RUN_DIR/$STDERR_REL"

COMMAND_DISPLAY="$(printf "%q " "$@")"
COMMAND_DISPLAY="${COMMAND_DISPLAY% }"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

set +e
(
  cd "$CWD"
  "$@"
) >"$STDOUT_PATH" 2>"$STDERR_PATH"
EXIT_CODE=$?
set -e

ENDED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RUN_DIR="$RUN_DIR" \
SEQ="$SEQ" \
COMMAND_ID="$COMMAND_ID" \
STEP_ID="$STEP_ID" \
PHASE="$PHASE" \
COMMAND_DISPLAY="$COMMAND_DISPLAY" \
CWD="$CWD" \
STARTED_AT="$STARTED_AT" \
ENDED_AT="$ENDED_AT" \
EXIT_CODE="$EXIT_CODE" \
COMMAND_RECORD_REL="$COMMAND_RECORD_REL" \
COMMAND_RECORD_PATH="$COMMAND_RECORD_PATH" \
STDOUT_REL="$STDOUT_REL" \
STDERR_REL="$STDERR_REL" \
python3 - <<'PY' >> "$LOG"
import json
import os
import pathlib

record = {
    "seq": int(os.environ["SEQ"]),
    "command_id": os.environ["COMMAND_ID"],
    "step_id": os.environ["STEP_ID"],
    "phase": os.environ["PHASE"],
    "command": os.environ["COMMAND_DISPLAY"],
    "cwd": os.environ["CWD"],
    "started_at": os.environ["STARTED_AT"],
    "ended_at": os.environ["ENDED_AT"],
    "exit_code": int(os.environ["EXIT_CODE"]),
    "passed": int(os.environ["EXIT_CODE"]) == 0,
    "failure": int(os.environ["EXIT_CODE"]) != 0,
    "command_record_path": os.environ["COMMAND_RECORD_REL"],
    "stdout_path": os.environ["STDOUT_REL"],
    "stderr_path": os.environ["STDERR_REL"],
}
payload = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
pathlib.Path(os.environ["COMMAND_RECORD_PATH"]).write_text(payload + "\n", encoding="utf-8")
print(payload)
PY

PHASE_UPPER="$(printf "%s" "$PHASE" | tr '[:lower:]' '[:upper:]')"
if [[ -f "$RUN_DIR/events.jsonl" && ( "$PHASE_UPPER" == "RED" || "$PHASE_UPPER" == "GREEN" ) ]]; then
  if [[ "$PHASE_UPPER" == "RED" ]]; then
    EVENT_TYPE="COMMAND_RECORDED_RED"
    STATE_AFTER="RED_RECORDED"
  else
    EVENT_TYPE="COMMAND_RECORDED_GREEN"
    STATE_AFTER="GREEN_RECORDED"
  fi
  "$SCRIPT_DIR/append-event.sh" \
    --run-dir "$RUN_DIR" \
    --event-type "$EVENT_TYPE" \
    --actor harness \
    --state-after "$STATE_AFTER" \
    --artifact "$COMMAND_RECORD_REL" \
    --artifact "$STDOUT_REL" \
    --artifact "$STDERR_REL" >/dev/null
fi

exit "$EXIT_CODE"
