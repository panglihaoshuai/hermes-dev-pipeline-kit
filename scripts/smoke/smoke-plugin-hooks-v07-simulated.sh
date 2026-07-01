#!/usr/bin/env bash
# smoke-plugin-hooks-v07-simulated.sh — direct callback smoke, not real runtime evidence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="${TMPDIR:-/tmp}/hermes-v07-hook-simulated-$$"
LOG_DIR="$TMP_ROOT/logs"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$LOG_DIR"
python3 -m py_compile "$PLUGIN_DIR"/*.py

PLUGIN_DIR="$PLUGIN_DIR" LOG_DIR="$LOG_DIR" python3 <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import sys

plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
log_dir = pathlib.Path(os.environ["LOG_DIR"]).resolve()
os.environ["HERMES_EVIDENCE_HOOK_LOG_DIR"] = str(log_dir)
os.environ["HERMES_EVIDENCE_HOOK_CAPTURE_MODE"] = "simulated_test"

spec = importlib.util.spec_from_file_location(
    "hermes_evidence_runtime",
    plugin_dir / "__init__.py",
    submodule_search_locations=[str(plugin_dir)],
)
if spec is None or spec.loader is None:
    raise SystemExit("failed to load plugin spec")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
hooks = importlib.import_module("hermes_evidence_runtime.hooks")

hooks.pre_tool_call(tool_name="noop", args={"x": 1}, session_id="sim-session", tool_call_id="sim-call")
hooks.post_tool_call(tool_name="noop", args={"x": 1}, result={"ok": True}, session_id="sim-session")
hooks.on_session_start(session_id="sim-session")
hooks.on_session_end(session_id="sim-session", completed=True)
hooks.on_session_finalize(session_id="sim-session")
hooks.subagent_stop(parent_session_id="sim-session", child_status="completed")

log_path = log_dir / "hook-events.jsonl"
records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
expected = {
    "pre_tool_call",
    "post_tool_call",
    "on_session_start",
    "on_session_end",
    "on_session_finalize",
    "subagent_stop",
}
observed = {record["hook_name"] for record in records}
if observed != expected:
    raise AssertionError(f"unexpected simulated hooks: {sorted(observed)}")
if {record["capture_mode"] for record in records} != {"simulated_test"}:
    raise AssertionError("simulated callback records must use capture_mode=simulated_test")

print(json.dumps({
    "smoke": "plugin-hooks-v07-simulated",
    "verdict": "SIMULATED_CALLBACK_ONLY",
    "ok": True,
    "records": len(records),
    "hooks": sorted(observed),
    "log_path": str(log_path),
}, sort_keys=True))
PY

echo "smoke-plugin-hooks-v07-simulated: PASS"
