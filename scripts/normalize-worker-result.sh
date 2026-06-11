#!/usr/bin/env bash
# normalize-worker-result.sh — Normalize worker raw/structured output to v0.5.3 worker-result JSON.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: normalize-worker-result.sh \
  --worker <claude-code|codex|opencode|raw> \
  --worker-skill <skill-name> \
  --work-order-id <id> \
  --status <completed|partial|blocked|failed|deferred> \
  --result-type <implementation|review|diagnostic|plan|unknown> \
  --raw-output <path> \
  [--structured-output <path>] \
  --out <worker-result.json>

Normalizes caller-supplied worker output into the v0.5.3 worker result contract.
This script does not invoke real ClaudeCode, Codex, or OpenCode and does not
claim official worker output capture.
EOF
}

WORKER=""
WORKER_SKILL=""
WORK_ORDER_ID=""
STATUS=""
RESULT_TYPE=""
RAW_OUTPUT=""
STRUCTURED_OUTPUT=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker) WORKER="${2:-}"; shift 2 ;;
    --worker-skill) WORKER_SKILL="${2:-}"; shift 2 ;;
    --work-order-id) WORK_ORDER_ID="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --result-type) RESULT_TYPE="${2:-}"; shift 2 ;;
    --raw-output) RAW_OUTPUT="${2:-}"; shift 2 ;;
    --structured-output) STRUCTURED_OUTPUT="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$WORKER" || -z "$WORKER_SKILL" || -z "$WORK_ORDER_ID" || -z "$STATUS" || -z "$RESULT_TYPE" || -z "$RAW_OUTPUT" || -z "$OUT" ]]; then
  usage >&2
  exit 1
fi

case "$WORKER" in
  claude-code|codex|opencode|raw) ;;
  *) echo "Error: unsupported worker: $WORKER" >&2; exit 1 ;;
esac

case "$STATUS" in
  completed|partial|blocked|failed|deferred) ;;
  *) echo "Error: unsupported status: $STATUS" >&2; exit 1 ;;
esac

case "$RESULT_TYPE" in
  implementation|review|diagnostic|plan|unknown) ;;
  *) echo "Error: unsupported result type: $RESULT_TYPE" >&2; exit 1 ;;
esac

if [[ ! -f "$RAW_OUTPUT" ]]; then
  echo "Error: raw output not found: $RAW_OUTPUT" >&2
  exit 1
fi

if [[ -n "$STRUCTURED_OUTPUT" && ! -f "$STRUCTURED_OUTPUT" ]]; then
  echo "Error: structured output not found: $STRUCTURED_OUTPUT" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$(dirname "$OUT")"

python3 - "$WORKER" "$WORKER_SKILL" "$WORK_ORDER_ID" "$STATUS" "$RESULT_TYPE" "$RAW_OUTPUT" "$STRUCTURED_OUTPUT" "$OUT" <<'PY'
import json
import pathlib
import re
import sys
from typing import Any

worker_arg, worker_skill, work_order_id, status, result_type, raw_output, structured_output, out_path = sys.argv[1:]
raw_path = pathlib.Path(raw_output).expanduser().resolve()
structured_path = pathlib.Path(structured_output).expanduser().resolve() if structured_output else None
out = pathlib.Path(out_path).expanduser().resolve()


def list_of_strings(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if isinstance(item, (str, int, float)) and str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def as_string(value: Any) -> str:
    return value if isinstance(value, str) else ""


def load_structured(path: pathlib.Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {
            "notes": "Structured output was provided but was not valid JSON; normalized from raw output only.",
        }
    return data if isinstance(data, dict) else {}


def safe_id(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-") or "WO-1"


structured = load_structured(structured_path)
safe_work_order_id = safe_id(work_order_id)
contract_worker = "unknown" if worker_arg == "raw" else worker_arg

files_touched = list_of_strings(structured.get("files_touched"))
commands_run = list_of_strings(structured.get("commands_run"))
evidence_refs = list_of_strings(structured.get("evidence_refs"))

if not evidence_refs:
    evidence_refs = [f"raw/worker/{safe_work_order_id}.raw.txt"]

review = structured.get("review") if isinstance(structured.get("review"), dict) else {}
verdict = review.get("verdict") if review.get("verdict") in {"PASS", "PARTIAL", "FAIL", "DEFERRED", "UNKNOWN"} else "UNKNOWN"
if status == "deferred" and verdict == "PASS":
    verdict = "DEFERRED"

blocking_findings = review.get("blocking_findings")
if not isinstance(blocking_findings, list):
    blocking_findings = []

deferred_reason = ""
deferred = structured.get("deferred") if isinstance(structured.get("deferred"), dict) else {}
if isinstance(deferred.get("reason"), str):
    deferred_reason = deferred["reason"]
if status == "deferred" and not deferred_reason:
    deferred_reason = "Worker result intentionally deferred by caller; final acceptance remains unavailable."

notes_parts = [
    as_string(structured.get("notes")),
    "Normalized by v0.5.4 worker normalizer prototype.",
    "This is caller-supplied or simulated worker evidence, not official worker capture.",
    "Worker result cannot claim final acceptance.",
]
if worker_arg == "raw":
    notes_parts.append("Raw adapter input mapped to worker=unknown to preserve v0.5.3 schema compatibility.")

result = {
    "schema_version": "0.5.3",
    "work_order_id": work_order_id,
    "worker": contract_worker,
    "worker_adapter": worker_arg,
    "worker_skill": worker_skill,
    "status": status,
    "result_type": result_type,
    "raw_output_path": f"raw/worker/{safe_work_order_id}.raw.txt",
    "structured_output_path": f"raw/worker/{safe_work_order_id}.structured.json",
    "files_touched": files_touched,
    "commands_run": commands_run,
    "evidence_refs": evidence_refs,
    "review": {
        "verdict": verdict,
        "summary": as_string(review.get("summary")) or "Worker output normalized as evidence only; final acceptance remains outside worker ownership.",
        "blocking_findings": [str(item) for item in blocking_findings],
    },
    "deferred": {
        "is_deferred": bool(status == "deferred" or deferred.get("is_deferred") is True),
        "reason": deferred_reason,
    },
    "notes": " ".join(part for part in notes_parts if part.strip()),
    "normalizer": {
        "version": "0.5.4",
        "source_raw_output_path": str(raw_path),
        "source_structured_output_path": str(structured_path) if structured_path else "",
        "simulated": bool(structured.get("simulated") is True),
    },
}

out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print(json.dumps({
    "ok": True,
    "worker": contract_worker,
    "worker_adapter": worker_arg,
    "work_order_id": work_order_id,
    "worker_result_path": str(out),
    "raw_output_path": str(raw_path),
    "structured_output_path": str(structured_path) if structured_path else "",
    "simulated": bool(structured.get("simulated") is True),
}, ensure_ascii=False, sort_keys=True))
PY

bash "$SCRIPT_DIR/validate-worker-result.sh" --worker-result "$OUT" >/dev/null
