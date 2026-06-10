#!/usr/bin/env bash
# record-worker-result.sh — Validate and record a v0.5.3 worker result into a run.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: record-worker-result.sh --run-dir <dir> --worker-result <worker-result.json> [--raw-output <path>]

Writes:
  <run-dir>/raw/worker/<work_order_id>.worker-result.json
  optional <run-dir>/<raw_output_path>

Appends:
  WORKER_RESULT_RECORDED

Prints machine-readable JSON to stdout.
EOF
}

RUN_DIR=""
WORKER_RESULT=""
RAW_OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --worker-result) WORKER_RESULT="${2:-}"; shift 2 ;;
    --raw-output) RAW_OUTPUT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$RUN_DIR" || -z "$WORKER_RESULT" ]]; then
  usage >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Error: run directory not found: $RUN_DIR" >&2
  exit 1
fi

bash "$SCRIPT_DIR/validate-worker-result.sh" --worker-result "$WORKER_RESULT" >/dev/null

python3 - "$RUN_DIR" "$WORKER_RESULT" "$RAW_OUTPUT" <<'PY'
import json
import pathlib
import re
import shutil
import sys

run_dir = pathlib.Path(sys.argv[1]).expanduser().resolve()
source_path = pathlib.Path(sys.argv[2]).expanduser().resolve()
raw_output_source = pathlib.Path(sys.argv[3]).expanduser().resolve() if sys.argv[3] else None

data = json.loads(source_path.read_text(encoding="utf-8"))
work_order_id = data.get("work_order_id", "WO-1")
safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "-", work_order_id).strip("-") or "WO-1"

worker_dir = run_dir / "raw" / "worker"
worker_dir.mkdir(parents=True, exist_ok=True)

worker_result_rel = pathlib.Path("raw") / "worker" / f"{safe_id}.worker-result.json"
worker_result_path = run_dir / worker_result_rel

raw_output_rel = pathlib.Path(data.get("raw_output_path") or f"raw/worker/{safe_id}.raw.txt")
structured_rel = pathlib.Path(data.get("structured_output_path") or str(worker_result_rel))

def ensure_relative_worker_path(rel_path: pathlib.Path, field: str) -> pathlib.Path:
    if rel_path.is_absolute() or ".." in rel_path.parts:
        raise SystemExit(f"{field} must be a relative path inside raw/worker")
    if len(rel_path.parts) < 2 or rel_path.parts[0] != "raw" or rel_path.parts[1] != "worker":
        raise SystemExit(f"{field} must be inside raw/worker")
    return rel_path

raw_output_rel = ensure_relative_worker_path(raw_output_rel, "raw_output_path")
structured_rel = ensure_relative_worker_path(structured_rel, "structured_output_path")

data["raw_output_path"] = str(raw_output_rel)
data["structured_output_path"] = str(worker_result_rel)

worker_result_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

raw_output_path = run_dir / raw_output_rel
if raw_output_source:
    if not raw_output_source.is_file():
        raise SystemExit(f"raw output source not found: {raw_output_source}")
    raw_output_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(raw_output_source, raw_output_path)
elif data.get("raw_output_path") and not raw_output_path.exists():
    raw_output_path.write_text("", encoding="utf-8")

structured_path = run_dir / structured_rel
if structured_path != worker_result_path:
    structured_path.parent.mkdir(parents=True, exist_ok=True)
    structured_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

artifacts = [str(worker_result_rel)]
if raw_output_path.exists():
    artifacts.append(str(raw_output_rel))
if structured_path.exists() and structured_path != worker_result_path:
    artifacts.append(str(structured_rel))

summary = {
    "ok": True,
    "run_dir": str(run_dir),
    "work_order_id": work_order_id,
    "worker": data.get("worker", ""),
    "status": data.get("status", ""),
    "result_type": data.get("result_type", ""),
    "worker_result_path": str(worker_result_path),
    "event": "WORKER_RESULT_RECORDED",
    "artifacts": artifacts,
}
print(json.dumps(summary, indent=2, ensure_ascii=False))
PY

ARTIFACTS=()
while IFS= read -r artifact; do
  ARTIFACTS+=("$artifact")
done < <(python3 - "$RUN_DIR" "$WORKER_RESULT" <<'PY'
import json
import pathlib
import re
import sys

run_dir = pathlib.Path(sys.argv[1]).expanduser().resolve()
source_path = pathlib.Path(sys.argv[2]).expanduser().resolve()
data = json.loads(source_path.read_text(encoding="utf-8"))
safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "-", data.get("work_order_id", "WO-1")).strip("-") or "WO-1"
for rel in (
    f"raw/worker/{safe_id}.worker-result.json",
    data.get("raw_output_path", ""),
    data.get("structured_output_path", ""),
):
    if not rel:
        continue
    path = run_dir / rel
    if path.exists() and path.is_file():
        print(rel)
PY
)

EVENT_ARGS=()
for artifact in "${ARTIFACTS[@]}"; do
  EVENT_ARGS+=(--artifact "$artifact")
done

"$SCRIPT_DIR/append-event.sh" \
  --run-dir "$RUN_DIR" \
  --event-type WORKER_RESULT_RECORDED \
  --actor harness \
  --state-after WORKER_RESULT_RECORDED \
  "${EVENT_ARGS[@]}" >/dev/null
