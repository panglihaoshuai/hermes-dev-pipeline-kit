#!/usr/bin/env bash
# validate-worker-result.sh — Validate v0.5.3 worker result contract JSON.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: validate-worker-result.sh <worker-result.json>
       validate-worker-result.sh --worker-result <worker-result.json>

Prints machine-readable JSON to stdout.
Exit 0 for PASS, 1 for FAIL.
EOF
}

WORKER_RESULT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker-result) WORKER_RESULT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *)
      if [[ -z "$WORKER_RESULT" ]]; then
        WORKER_RESULT="$1"
        shift
      else
        echo "Error: unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$WORKER_RESULT" ]]; then
  usage >&2
  exit 1
fi

python3 - "$WORKER_RESULT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1]).expanduser().resolve()
errors = []
warnings = []

if not path.is_file():
    print(json.dumps({
        "ok": False,
        "verdict": "FAIL",
        "worker_result_path": str(path),
        "errors": [f"worker result file not found: {path}"],
        "warnings": [],
    }, indent=2, ensure_ascii=False))
    sys.exit(1)

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(json.dumps({
        "ok": False,
        "verdict": "FAIL",
        "worker_result_path": str(path),
        "errors": [f"invalid JSON: {exc}"],
        "warnings": [],
    }, indent=2, ensure_ascii=False))
    sys.exit(1)

if not isinstance(data, dict):
    errors.append("worker result must be a JSON object")
    data = {}

required = [
    "schema_version",
    "work_order_id",
    "worker",
    "worker_skill",
    "status",
    "result_type",
    "raw_output_path",
    "structured_output_path",
    "files_touched",
    "commands_run",
    "evidence_refs",
    "review",
    "deferred",
    "notes",
]
for key in required:
    if key not in data:
        errors.append(f"missing required field: {key}")

if data.get("schema_version") != "0.5.3":
    errors.append("schema_version must be 0.5.3")

if data.get("worker") not in {"claude-code", "codex", "opencode", "hermes", "unknown"}:
    errors.append("worker must be one of claude-code, codex, opencode, hermes, unknown")

if data.get("status") not in {"completed", "partial", "blocked", "failed", "deferred"}:
    errors.append("status must be one of completed, partial, blocked, failed, deferred")

if data.get("result_type") not in {"implementation", "review", "diagnostic", "plan", "unknown"}:
    errors.append("result_type must be one of implementation, review, diagnostic, plan, unknown")

for key in ("work_order_id", "worker_skill", "raw_output_path", "structured_output_path", "notes"):
    if key in data and not isinstance(data.get(key), str):
        errors.append(f"{key} must be a string")

for key in ("files_touched", "commands_run", "evidence_refs"):
    value = data.get(key)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        errors.append(f"{key} must be an array of strings")

review = data.get("review")
if not isinstance(review, dict):
    errors.append("review must be an object")
    review = {}
if review.get("verdict") not in {"PASS", "PARTIAL", "FAIL", "DEFERRED", "UNKNOWN"}:
    errors.append("review.verdict must be PASS, PARTIAL, FAIL, DEFERRED, or UNKNOWN")
if not isinstance(review.get("summary"), str):
    errors.append("review.summary must be a string")
if not isinstance(review.get("blocking_findings"), list):
    errors.append("review.blocking_findings must be an array")

deferred = data.get("deferred")
if not isinstance(deferred, dict):
    errors.append("deferred must be an object")
    deferred = {}
if not isinstance(deferred.get("is_deferred"), bool):
    errors.append("deferred.is_deferred must be boolean")
if not isinstance(deferred.get("reason"), str):
    errors.append("deferred.reason must be a string")

acceptance = data.get("acceptance")
if isinstance(acceptance, dict) and acceptance.get("complete") is True:
    errors.append("worker result must not set acceptance.complete=true")

is_deferred = data.get("status") == "deferred" or deferred.get("is_deferred") is True
if is_deferred and not str(deferred.get("reason", "")).strip():
    errors.append("deferred worker result requires deferred.reason")

if is_deferred and review.get("verdict") == "PASS":
    errors.append("deferred worker result must not report review.verdict=PASS")

if data.get("worker") == "codex" and is_deferred and review.get("verdict") == "PASS":
    errors.append("deferred Codex worker result must not be PASS")

if review.get("verdict") == "DEFERRED" and not is_deferred:
    errors.append("review.verdict=DEFERRED requires status=deferred or deferred.is_deferred=true")

result = {
    "ok": not errors,
    "verdict": "PASS" if not errors else "FAIL",
    "worker_result_path": str(path),
    "work_order_id": data.get("work_order_id", ""),
    "worker": data.get("worker", ""),
    "status": data.get("status", ""),
    "result_type": data.get("result_type", ""),
    "errors": errors,
    "warnings": warnings,
}
print(json.dumps(result, indent=2, ensure_ascii=False))
sys.exit(0 if not errors else 1)
PY
