#!/usr/bin/env bash
# invoke-worker-dry-run.sh — Explicit, timeout-bound worker dry-run wrapper.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: invoke-worker-dry-run.sh --worker <claude-code|codex|opencode|raw> --out-dir <dir> [OPTIONS]

Options:
  --timeout-seconds <n>           Defaults to 60.
  --allow-real-invocation yes|no  Defaults to no.
  --prompt-file <file>            Optional prompt override.
  --help                          Show this help.

Writes:
  <out-dir>/raw.txt
  <out-dir>/structured.json
  <out-dir>/invocation.json

This script does not modify the current repository, commit, push, open PRs, or
write real ~/.hermes / ~/.claude configuration. Real invocation is disabled by
default and is only allowed in /tmp-compatible output directories.
EOF
}

WORKER=""
OUT_DIR=""
TIMEOUT_SECONDS="60"
ALLOW_REAL_INVOCATION="no"
PROMPT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker) WORKER="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --timeout-seconds) TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
    --allow-real-invocation) ALLOW_REAL_INVOCATION="${2:-}"; shift 2 ;;
    --prompt-file) PROMPT_FILE="${2:-}"; shift 2 ;;
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

case "$ALLOW_REAL_INVOCATION" in
  yes|no) ;;
  *) echo "Error: --allow-real-invocation must be yes or no" >&2; exit 1 ;;
esac

if [[ ! "$TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "Error: --timeout-seconds must be a positive integer" >&2
  exit 1
fi

if [[ -n "$PROMPT_FILE" && ! -f "$PROMPT_FILE" ]]; then
  echo "Error: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

case "$OUT_DIR" in
  /tmp/*|/private/tmp/*) ;;
  *)
    echo "Error: worker dry-run output directory must be under /tmp" >&2
    exit 1
    ;;
esac

python3 - "$WORKER" "$OUT_DIR" "$TIMEOUT_SECONDS" "$ALLOW_REAL_INVOCATION" "$PROMPT_FILE" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any

worker, out_dir_arg, timeout_arg, allow_arg, prompt_file_arg = sys.argv[1:]
out_dir = pathlib.Path(out_dir_arg).resolve()
timeout_seconds = int(timeout_arg)
allow_real = allow_arg == "yes"
raw_path = out_dir / "raw.txt"
structured_path = out_dir / "structured.json"
invocation_path = out_dir / "invocation.json"

default_prompt = f'Reply with JSON only: {{"ok":true,"worker":"{worker}"}}'
if prompt_file_arg:
    prompt = pathlib.Path(prompt_file_arg).read_text(encoding="utf-8")
else:
    prompt = default_prompt


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def command_for(worker_name: str) -> tuple[list[str], str]:
    if worker_name == "claude-code":
        return ["claude", "-p", prompt, "--output-format", "json"], "claude"
    if worker_name == "codex":
        return ["codex", "exec", "--json", prompt], "codex"
    if worker_name == "opencode":
        return ["opencode", "run", "--format", "json", prompt], "opencode"
    return [], ""


def write_outputs(
    *,
    command: list[str],
    real_invocation: bool,
    exit_code: int,
    started_at: str,
    completed_at: str,
    duration_ms: int,
    raw_text: str,
    skipped_reason: str,
    timed_out: bool = False,
) -> dict[str, Any]:
    raw_path.write_text(raw_text, encoding="utf-8")
    status = "completed" if real_invocation and exit_code == 0 else "failed" if real_invocation else "deferred"
    review_verdict = "PASS" if real_invocation and exit_code == 0 else "FAIL" if real_invocation else "DEFERRED"
    structured = {
        "worker": worker,
        "ok": real_invocation and exit_code == 0,
        "status": status,
        "result_type": "diagnostic",
        "files_touched": [],
        "commands_run": [" ".join(command)] if command else [],
        "review": {
            "verdict": review_verdict,
            "summary": "Explicit worker dry-run invocation evidence only; harness owns acceptance.",
            "blocking_findings": [] if exit_code == 0 or not real_invocation else ["worker dry-run command exited non-zero"],
        },
        "deferred": {
            "is_deferred": not real_invocation,
            "reason": skipped_reason if not real_invocation else "",
        },
        "evidence_refs": [
            "raw/worker/WO-1.invocation.json",
            "raw/worker/WO-1.raw.txt",
            "raw/worker/WO-1.structured.json",
        ],
        "notes": f"real_invocation={str(real_invocation).lower()}; skipped_reason={skipped_reason}",
        "real_invocation": real_invocation,
        "skipped_reason": skipped_reason,
        "timed_out": timed_out,
        "simulated": not real_invocation,
    }
    structured_path.write_text(json.dumps(structured, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    invocation = {
        "worker": worker,
        "real_invocation": real_invocation,
        "command": command,
        "exit_code": exit_code,
        "started_at": started_at,
        "completed_at": completed_at,
        "duration_ms": duration_ms,
        "timeout_seconds": timeout_seconds,
        "raw_output_path": str(raw_path),
        "structured_output_path": str(structured_path),
        "skipped_reason": skipped_reason,
        "timed_out": timed_out,
    }
    invocation_path.write_text(json.dumps(invocation, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return invocation


start_wall = time.monotonic()
started_at = now()

if not allow_real:
    invocation = write_outputs(
        command=[],
        real_invocation=False,
        exit_code=0,
        started_at=started_at,
        completed_at=now(),
        duration_ms=int((time.monotonic() - start_wall) * 1000),
        raw_text="SKIPPED: real invocation disabled\n",
        skipped_reason="real invocation disabled",
    )
elif worker == "raw":
    invocation = write_outputs(
        command=[],
        real_invocation=False,
        exit_code=0,
        started_at=started_at,
        completed_at=now(),
        duration_ms=int((time.monotonic() - start_wall) * 1000),
        raw_text='{"ok":true,"worker":"raw","mode":"no-cli"}\n',
        skipped_reason="raw adapter has no real CLI invocation",
    )
else:
    command, executable = command_for(worker)
    if not shutil.which(executable):
        invocation = write_outputs(
            command=command,
            real_invocation=False,
            exit_code=0,
            started_at=started_at,
            completed_at=now(),
            duration_ms=int((time.monotonic() - start_wall) * 1000),
            raw_text=f"SKIPPED: {executable} CLI not found\n",
            skipped_reason=f"{executable} CLI not found",
        )
    else:
        timed_out = False
        try:
            completed = subprocess.run(
                command,
                cwd=str(out_dir),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=timeout_seconds,
                check=False,
            )
            exit_code = completed.returncode
            raw_text = completed.stdout
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            exit_code = 124
            raw_text = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
            raw_text += f"\nTIMEOUT after {timeout_seconds}s\n"
        invocation = write_outputs(
            command=command,
            real_invocation=True,
            exit_code=exit_code,
            started_at=started_at,
            completed_at=now(),
            duration_ms=int((time.monotonic() - start_wall) * 1000),
            raw_text=raw_text,
            skipped_reason="",
            timed_out=timed_out,
        )

print(json.dumps({
    "ok": True,
    "worker": worker,
    "real_invocation": invocation["real_invocation"],
    "invocation_path": str(invocation_path),
    "raw_output_path": str(raw_path),
    "structured_output_path": str(structured_path),
    "skipped_reason": invocation["skipped_reason"],
    "exit_code": invocation["exit_code"],
}, ensure_ascii=False, sort_keys=True))
PY
