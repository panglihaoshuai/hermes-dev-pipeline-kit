#!/usr/bin/env bash
# fail-run.sh — Finalize a failed v0.4 harness run with auditable evidence.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fail-run.sh --run-dir <dir> --reason <text> [--failed-phase <phase>] [--failed-command <command>]

Writes raw/failure-result.json, appends RUN_FAILED, runs replay, generates
run-state, runs policy-check, and writes generated/final-report.md.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR=""
REASON=""
FAILED_PHASE=""
FAILED_COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    --failed-phase) FAILED_PHASE="${2:-}"; shift 2 ;;
    --failed-command) FAILED_COMMAND="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$REASON" ]]; then
  usage >&2
  exit 1
fi
if [[ ! -d "$RUN_DIR" ]]; then
  echo "Error: run directory not found: $RUN_DIR" >&2
  exit 1
fi

mkdir -p "$RUN_DIR/raw" "$RUN_DIR/generated"

python3 - "$RUN_DIR" "$REASON" "$FAILED_PHASE" "$FAILED_COMMAND" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

run_dir = pathlib.Path(sys.argv[1]).resolve()
reason = sys.argv[2]
failed_phase = sys.argv[3]
failed_command = sys.argv[4]
command_log_path = run_dir / "raw" / "command-log.jsonl"

commands = []
if command_log_path.exists():
    for line in command_log_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            commands.append(json.loads(line))

failed_commands = [
    item for item in commands
    if isinstance(item.get("exit_code"), int) and item.get("exit_code") != 0
]
selected = None
if failed_phase:
    for item in reversed(failed_commands):
        if str(item.get("phase", "")).upper() == failed_phase.upper():
            selected = item
            break
if selected is None and failed_commands:
    selected = failed_commands[-1]

out = {
    "status": "failed",
    "reason": reason,
    "failed_phase": failed_phase or (selected or {}).get("phase", ""),
    "failed_command": failed_command or (selected or {}).get("command", ""),
    "failed_exit_code": (selected or {}).get("exit_code"),
    "stdout_path": (selected or {}).get("stdout_path", ""),
    "stderr_path": (selected or {}).get("stderr_path", ""),
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "commands": commands,
}
(run_dir / "raw" / "failure-result.json").write_text(
    json.dumps(out, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

if [[ -f "$RUN_DIR/events.jsonl" ]] && ! grep -q '"event_type":"RUN_FAILED"' "$RUN_DIR/events.jsonl"; then
  "$SCRIPT_DIR/append-event.sh" \
    --run-dir "$RUN_DIR" \
    --event-type RUN_FAILED \
    --actor harness \
    --state-after FAILED \
    --artifact raw/failure-result.json >/dev/null
fi

"$SCRIPT_DIR/replay-run.sh" "$RUN_DIR" >/dev/null
"$SCRIPT_DIR/generate-run-state.sh" "$RUN_DIR" >/dev/null
set +e
"$SCRIPT_DIR/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" > "$RUN_DIR/generated/policy-check.out"
POLICY_EXIT=$?
set -e
"$SCRIPT_DIR/final-report.sh" "$RUN_DIR/generated/run-state.json" > "$RUN_DIR/generated/final-report.out"

echo "$RUN_DIR/generated/final-report.md"
exit 1
