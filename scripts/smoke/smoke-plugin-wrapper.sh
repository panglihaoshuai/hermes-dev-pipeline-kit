#!/usr/bin/env bash
# smoke-plugin-wrapper.sh — source-only smoke for the experimental v0.5.1 plugin wrapper.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="${TMPDIR:-/tmp}/hermes-plugin-wrapper-smoke-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT/project" "$TMP_ROOT/work"

python3 -m py_compile "$PLUGIN_DIR"/*.py

PLUGIN_DIR="$PLUGIN_DIR" TMP_ROOT="$TMP_ROOT" python3 <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import shlex
import sys

plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
tmp_root = pathlib.Path(os.environ["TMP_ROOT"]).resolve()
project_root = tmp_root / "project"
work_dir = tmp_root / "work"

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

tools = importlib.import_module("hermes_evidence_runtime.tools")

def call_json(fn, payload):
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool did not return a JSON object: {raw}")
    return data

doctor = call_json(tools.evidence_doctor, {"mode": "source"})
if not doctor.get("ok"):
    raise AssertionError(f"evidence_doctor failed: {doctor}")

init = call_json(
    tools.evidence_run_init,
    {
        "project_root": str(project_root),
        "task": "v0.5.1 plugin wrapper smoke",
        "scale": "S",
        "mode": "auto_run",
        "task_type": "smoke",
    },
)
if not init.get("ok"):
    raise AssertionError(f"evidence_run_init failed: {init}")
if init.get("state") != "CLASSIFIED":
    raise AssertionError(f"unexpected init state: {init}")

status = call_json(tools.evidence_active_run_status, {"project_root": str(project_root)})
if not status.get("ok") or status.get("state") != "active":
    raise AssertionError(f"unexpected active status after init: {status}")

test_file = work_dir / "test.py"
test_file.write_text(
    "print('plugin wrapper smoke ok')\n",
    encoding="utf-8",
)
command = f"{shlex.quote(sys.executable)} {shlex.quote(str(test_file.name))}"

drive = call_json(
    tools.evidence_drive_s_run,
    {
        "run_dir": init["run_dir"],
        "work_dir": str(work_dir),
        "command": command,
        "files_touched": ["test.py"],
    },
)
if not drive.get("ok") or drive.get("verdict") != "PASS":
    raise AssertionError(f"evidence_drive_s_run failed: {drive}")

run_dir = pathlib.Path(init["run_dir"])
required = [
    run_dir / "raw" / "command-log.jsonl",
    run_dir / "generated" / "run-state.json",
    run_dir / "generated" / "policy-result.json",
    run_dir / "generated" / "final-report.md",
]
for path in required:
    if not path.is_file() or path.stat().st_size == 0:
        raise AssertionError(f"missing or empty artifact: {path}")

status = call_json(tools.evidence_active_run_status, {"project_root": str(project_root)})
if not status.get("ok") or status.get("state") != "completed":
    raise AssertionError(f"unexpected active status after drive: {status}")

print(json.dumps({
    "smoke": "plugin-wrapper",
    "ok": True,
    "run_dir": str(run_dir),
    "artifacts_checked": [str(path.relative_to(run_dir)) for path in required],
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-plugin-wrapper: PASS"
