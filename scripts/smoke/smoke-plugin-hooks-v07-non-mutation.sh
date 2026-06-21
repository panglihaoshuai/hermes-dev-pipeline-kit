#!/usr/bin/env bash
# smoke-plugin-hooks-v07-non-mutation.sh — A/B result comparison for hook logging.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/plugins/hermes-evidence-runtime"
PLUGIN_NAME="hermes-evidence-runtime"
TMP_HOME="${TMPDIR:-/tmp}/hermes-v07-hook-ab-home-$$"
WORK_ROOT="${TMPDIR:-/tmp}/hermes-v07-hook-ab-work-$$"
LOG_DIR="${TMPDIR:-/tmp}/hermes-v07-hook-ab-log-$$"
HERMES_BIN="${HERMES_BIN_OVERRIDE:-$(command -v hermes 2>/dev/null || true)}"
HERMES_AGENT_ROOT="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}"
PYTHON_BIN="${PYTHON_BIN:-$HERMES_AGENT_ROOT/venv/bin/python}"

cleanup() {
  rm -rf "$TMP_HOME" "$WORK_ROOT" "$LOG_DIR"
}
trap cleanup EXIT

if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then
  echo "FAIL: hermes binary not found"
  exit 1
fi
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "FAIL: Hermes Python not found: $PYTHON_BIN"
  exit 1
fi

rm -rf "$TMP_HOME" "$WORK_ROOT" "$LOG_DIR"
mkdir -p "$TMP_HOME/.hermes/plugins" "$WORK_ROOT"
cp -R "$PLUGIN_SRC" "$TMP_HOME/.hermes/plugins/$PLUGIN_NAME"
HERMES_HOME="$TMP_HOME/.hermes" "$HERMES_BIN" plugins enable "$PLUGIN_NAME" >/tmp/hermes-v07-hook-ab-enable.out

HERMES_HOME="$TMP_HOME/.hermes" \
HERMES_DEV_PIPELINE_KIT_ROOT="$REPO_ROOT" \
PYTHONPATH="$HERMES_AGENT_ROOT" \
"$PYTHON_BIN" - "$WORK_ROOT" "$LOG_DIR" <<'PY'
import json
import os
import pathlib
import sys

from hermes_cli.plugins import discover_plugins
from model_tools import handle_function_call

work_root = pathlib.Path(sys.argv[1]).resolve()
log_dir = pathlib.Path(sys.argv[2]).resolve()

discover_plugins(force=True)

def call_tool(label):
    result = handle_function_call(
        "evidence_active_run_status",
        {"project_root": str(work_root)},
        task_id=f"v07-ab-{label}",
        session_id="v07-ab-session",
        tool_call_id=f"v07-ab-call-{label}",
        turn_id=f"v07-ab-turn-{label}",
        enabled_toolsets=["evidence_runtime"],
    )
    return json.loads(result)

os.environ.pop("HERMES_EVIDENCE_HOOK_LOG_DIR", None)
os.environ["HERMES_EVIDENCE_HOOK_CAPTURE_MODE"] = "real_runtime"
control = call_tool("control")

os.environ["HERMES_EVIDENCE_HOOK_LOG_DIR"] = str(log_dir)
capture = call_tool("capture")

if control != capture:
    raise AssertionError({"control": control, "capture": capture})
log_path = log_dir / "hook-events.jsonl"
if not log_path.is_file() or log_path.stat().st_size == 0:
    raise AssertionError("capture log not written")

print(json.dumps({
    "smoke": "plugin-hooks-v07-non-mutation",
    "ok": True,
    "control": control,
    "capture": capture,
    "comparison": "identical",
    "log_path": str(log_path),
}, sort_keys=True))
PY

echo "smoke-plugin-hooks-v07-non-mutation: PASS"
