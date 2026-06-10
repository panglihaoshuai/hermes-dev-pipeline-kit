#!/usr/bin/env bash
# drive-s-run.sh — Drive an S-level auto_run task from classification to final report.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: drive-s-run.sh --run-dir <dir> --work-dir <dir> --command <command> [OPTIONS]

Required:
  --run-dir <dir>      Existing Hermes run directory created by run-init.sh.
  --work-dir <dir>     Project or work directory for the verification command.
  --command <string>   Command to execute (run through bash -lc).

Optional:
  --work-order-id <id>          Work order id to embed in raw/claudecode-result.json.
  --required-matt-skill <skill>  Defaults to tdd.
  --step-id <id>                record-command step id. Defaults to s-green.
  --files-touched <path>        Repeatable; written to raw/files-touched.txt.
  --red-not-applicable-reason <text>
                                Defaults to an S-level single-command explanation.
  --help                        Show this help.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RUN_DIR=""
WORK_DIR=""
COMMAND=""
WORK_ORDER_ID="WO-1"
REQUIRED_MATT_SKILL="tdd"
STEP_ID="s-green"
RED_NOT_APPLICABLE_REASON="S-level auto_run uses a single verification command; RED phase is not applicable."
FILES_TOUCHED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --work-dir) WORK_DIR="${2:-}"; shift 2 ;;
    --command) COMMAND="${2:-}"; shift 2 ;;
    --work-order-id) WORK_ORDER_ID="${2:-}"; shift 2 ;;
    --required-matt-skill) REQUIRED_MATT_SKILL="${2:-}"; shift 2 ;;
    --step-id) STEP_ID="${2:-}"; shift 2 ;;
    --files-touched) FILES_TOUCHED+=("${2:-}"); shift 2 ;;
    --red-not-applicable-reason) RED_NOT_APPLICABLE_REASON="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$WORK_DIR" || -z "$COMMAND" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Error: run directory not found: $RUN_DIR" >&2
  exit 1
fi

if [[ ! -d "$WORK_DIR" ]]; then
  echo "Error: work directory not found: $WORK_DIR" >&2
  exit 1
fi

if [[ ! -f "$RUN_DIR/state.json" ]]; then
  echo "Error: missing state.json: $RUN_DIR/state.json" >&2
  exit 1
fi

CURRENT_STATE="$(python3 - "$RUN_DIR/state.json" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(state.get("current_state", ""))
PY
)"

if [[ "$CURRENT_STATE" != "CLASSIFIED" ]]; then
  echo "Error: S-level driver requires current_state=CLASSIFIED, got: ${CURRENT_STATE:-<empty>}" >&2
  exit 1
fi

mkdir -p "$RUN_DIR/raw"

if [[ ${#FILES_TOUCHED[@]} -gt 0 ]]; then
  python3 - "$RUN_DIR/raw/files-touched.txt" "${FILES_TOUCHED[@]}" <<'PY'
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
paths = []
for item in sys.argv[2:]:
    if item and item not in paths:
        paths.append(item)
out.write_text("\n".join(paths) + ("\n" if paths else ""), encoding="utf-8")
PY
elif [[ ! -f "$RUN_DIR/raw/files-touched.txt" ]]; then
  : > "$RUN_DIR/raw/files-touched.txt"
fi

record_command_exit=0
set +e
"$SCRIPT_DIR/record-command.sh" \
  --run-dir "$RUN_DIR" \
  --cwd "$WORK_DIR" \
  --step-id "$STEP_ID" \
  --phase GREEN \
  -- bash -lc "$COMMAND"
record_command_exit=$?
set -e

if [[ ! -s "$RUN_DIR/raw/command-log.jsonl" ]]; then
  echo "Error: command log is empty after record-command.sh" >&2
  exit 1
fi

update_work_order() {
  local status="$1"
  python3 - "$RUN_DIR" "$WORK_ORDER_ID" "$status" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1]).resolve()
work_order_id = sys.argv[2]
status = sys.argv[3]
path = run_dir / "work-orders" / f"{work_order_id}.json"
if not path.exists():
    sys.exit(0)
data = json.loads(path.read_text(encoding="utf-8"))
data["status"] = status
if status == "completed":
    data["files"] = sorted(dict.fromkeys((data.get("files") or []) + [
        line.strip()
        for line in (run_dir / "raw" / "files-touched.txt").read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]))
elif status == "failed":
    data["files"] = sorted(dict.fromkeys((data.get("files") or [])))
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

require_artifact() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Error: required artifact missing: $path" >&2
    exit 1
  fi
}

write_claude_contract() {
  python3 - "$RUN_DIR/raw/claudecode-result.json" "$WORK_ORDER_ID" "$REQUIRED_MATT_SKILL" "$COMMAND" "$record_command_exit" "$RED_NOT_APPLICABLE_REASON" "${FILES_TOUCHED[@]}" <<'PY'
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
work_order_id = sys.argv[2]
required_matt_skill = sys.argv[3]
command = sys.argv[4]
green_exit = int(sys.argv[5])
red_reason = sys.argv[6]
files_touched = []
for item in sys.argv[7:]:
    if item and item not in files_touched:
        files_touched.append(item)

contract = {
    "work_order_id": work_order_id,
    "status": "completed",
    "required_matt_skill": required_matt_skill,
    "matt_evidence": {
        "red": "S-level single-command path; RED not applicable.",
        "red_exit_code": 0,
        "red_not_applicable_reason": red_reason,
        "green": command,
        "green_exit_code": green_exit,
        "commands": [command],
        "exit_codes": [green_exit],
    },
    "files_touched": files_touched,
    "commands_run": [command],
    "blocked": False,
    "notes": "S-level execution driver result contract. Acceptance is intentionally present on success.",
}
out.write_text(json.dumps(contract, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

if [[ "$record_command_exit" -eq 0 ]]; then
  update_work_order "completed"
  write_claude_contract

  "$SCRIPT_DIR/generate-run-state.sh" "$RUN_DIR" >/dev/null
  require_artifact "$RUN_DIR/generated/run-state.json"

  "$SCRIPT_DIR/policy-check.sh" --run-state "$RUN_DIR/generated/run-state.json" >/dev/null
  require_artifact "$RUN_DIR/generated/policy-result.json"

  "$SCRIPT_DIR/final-report.sh" "$RUN_DIR/generated/run-state.json" >/dev/null
  require_artifact "$RUN_DIR/generated/final-report.md"

  echo "run directory: $RUN_DIR"
  echo "command: $COMMAND"
  echo "command exit code: $record_command_exit"
  echo "run-state path: $RUN_DIR/generated/run-state.json"
  echo "policy-result path: $RUN_DIR/generated/policy-result.json"
  echo "final-report path: $RUN_DIR/generated/final-report.md"
  echo "final status: PASS"
  exit 0
fi

update_work_order "failed"

set +e
"$SCRIPT_DIR/fail-run.sh" \
  --run-dir "$RUN_DIR" \
  --reason "S-level verification command failed" \
  --failed-phase "GREEN" \
  --failed-command "$COMMAND" >/dev/null
fail_run_exit=$?
set -e

require_artifact "$RUN_DIR/raw/failure-result.json"
require_artifact "$RUN_DIR/generated/run-state.json"
require_artifact "$RUN_DIR/generated/policy-result.json"
require_artifact "$RUN_DIR/generated/final-report.md"

echo "run directory: $RUN_DIR"
echo "command: $COMMAND"
echo "command exit code: $record_command_exit"
echo "run-state path: $RUN_DIR/generated/run-state.json"
echo "policy-result path: $RUN_DIR/generated/policy-result.json"
echo "final-report path: $RUN_DIR/generated/final-report.md"
echo "final status: FAIL"
exit "$fail_run_exit"
