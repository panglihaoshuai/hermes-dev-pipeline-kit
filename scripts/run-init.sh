#!/usr/bin/env bash
# run-init.sh — Create a local evidence run directory.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-init.sh --root <dir> --task-file <file> [OPTIONS]

Options:
  --run-id <id>       Run id. Defaults to UTC timestamp + pid.
  --task-type <type>  feature | bugfix | refactor | integration | deployment | smoke
  --mode <mode>       dry_run | plan_only | auto_run. Defaults to auto_run.
  --scale <scale>     S | M | L. Defaults to S.
  --project <name>    Project name. Defaults to basename of --root.
  --help              Show this help.

Creates:
  <root>/.hermes-runs/<run-id>/
EOF
}

ROOT=""
TASK_FILE=""
RUN_ID=""
TASK_TYPE="smoke"
MODE="auto_run"
SCALE="S"
PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --task-file) TASK_FILE="${2:-}"; shift 2 ;;
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --task-type) TASK_TYPE="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --scale) SCALE="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOT" || -z "$TASK_FILE" ]]; then
  echo "Error: --root and --task-file are required" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Error: task file not found: $TASK_FILE" >&2
  exit 1
fi

case "$MODE" in
  dry_run|plan_only|auto_run) ;;
  *) echo "Error: invalid --mode: $MODE" >&2; exit 1 ;;
esac

case "$SCALE" in
  S|M|L) ;;
  *) echo "Error: invalid --scale: $SCALE" >&2; exit 1 ;;
esac

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")-$$"
fi

if [[ -z "$PROJECT" ]]; then
  PROJECT="$(basename "$ROOT")"
fi

RUN_DIR="$ROOT/.hermes-runs/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
  echo "Error: run directory already exists: $RUN_DIR" >&2
  exit 1
fi

mkdir -p \
  "$RUN_DIR/work-orders" \
  "$RUN_DIR/raw/stdout" \
  "$RUN_DIR/raw/stderr" \
  "$RUN_DIR/generated"

cp "$TASK_FILE" "$RUN_DIR/task.md"
: > "$RUN_DIR/raw/command-log.jsonl"
: > "$RUN_DIR/raw/files-touched.txt"

CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - "$RUN_DIR" "$RUN_ID" "$CREATED_AT" "$TASK_TYPE" "$MODE" "$SCALE" "$PROJECT" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
run_id, created_at, task_type, mode, scale, project = sys.argv[2:]

manifest = {
    "run_id": run_id,
    "created_at": created_at,
    "task_type": task_type,
    "requested_mode": mode,
    "project": project,
    "harness_version": "0.3.0",
    "run_dir": str(run_dir),
}

classification = {
    "scale": scale,
    "reasons": [f"Initialized by scripts/run-init.sh as {scale}-level {task_type} task"],
    "risk_level": "medium" if scale in {"M", "L"} else "low",
}

work_order = {
    "id": "WO-1",
    "owner": "ClaudeCode",
    "required_skill": "hermes-dev-pipeline-kit",
    "required_matt_skill": "tdd" if scale in {"M", "L"} else "tdd",
    "status": "pending",
    "files": [],
    "retries": 0,
}

(run_dir / "run-manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
(run_dir / "classification.json").write_text(
    json.dumps(classification, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
(run_dir / "work-orders" / "WO-1.json").write_text(
    json.dumps(work_order, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

echo "$RUN_DIR"
