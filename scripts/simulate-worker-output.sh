#!/usr/bin/env bash
# simulate-worker-output.sh — Generate simulated worker raw/structured output for smokes.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: simulate-worker-output.sh --worker <claude-code|codex|opencode|raw> --out-dir <dir>

Writes:
  <out-dir>/raw.txt
  <out-dir>/structured.json

This script is smoke-only. It does not call real ClaudeCode, Codex, or OpenCode.
EOF
}

WORKER=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker) WORKER="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$WORKER" || -z "$OUT_DIR" ]]; then
  usage >&2
  exit 1
fi

case "$WORKER" in
  claude-code|codex|opencode|raw) ;;
  *) echo "Error: unsupported worker: $WORKER" >&2; exit 1 ;;
esac

mkdir -p "$OUT_DIR"

python3 - "$WORKER" "$OUT_DIR" <<'PY'
import json
import pathlib
import sys

worker = sys.argv[1]
out_dir = pathlib.Path(sys.argv[2]).expanduser().resolve()
raw_path = out_dir / "raw.txt"
structured_path = out_dir / "structured.json"

worker_labels = {
    "claude-code": "ClaudeCode",
    "codex": "Codex",
    "opencode": "OpenCode",
    "raw": "RawAdapter",
}

raw_path.write_text(
    "\n".join([
        "SIMULATED WORKER OUTPUT",
        f"simulated: true",
        f"worker: {worker_labels[worker]}",
        "work_order_id: WO-1",
        "status: completed",
        "result_type: implementation",
        "files_touched: test.js, src/todo.js",
        "commands_run: node test.js, node test.js",
        "review_verdict: UNKNOWN",
        "note: final acceptance remains outside worker ownership.",
        "",
    ]),
    encoding="utf-8",
)

structured = {
    "simulated": True,
    "worker": worker,
    "work_order_id": "WO-1",
    "status": "completed",
    "result_type": "implementation",
    "files_touched": ["test.js", "src/todo.js"],
    "commands_run": ["node test.js", "node test.js"],
    "evidence_refs": ["raw/command-log.jsonl", "raw/claudecode-result.json"],
    "review": {
        "verdict": "UNKNOWN",
        "summary": "Simulated worker output normalized for harness evidence only.",
        "blocking_findings": [],
    },
    "notes": (
        "Simulated worker evidence for v0.5.4 normalizer smoke. "
        "No official worker output capture and no final acceptance."
    ),
}
structured_path.write_text(json.dumps(structured, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print(json.dumps({
    "ok": True,
    "worker": worker,
    "simulated": True,
    "raw_output_path": str(raw_path),
    "structured_output_path": str(structured_path),
}, ensure_ascii=False, sort_keys=True))
PY
