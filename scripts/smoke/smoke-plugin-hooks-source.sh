#!/usr/bin/env bash
# smoke-plugin-hooks-source.sh — source-only smoke for v0.5.2 hook prototypes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="${TMPDIR:-/tmp}/hermes-evidence-hooks-source-$$"
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


class FakeCtx:
    def __init__(self):
        self.tools = []
        self.hooks = []

    def register_tool(self, name, func, **kwargs):
        self.tools.append((name, kwargs))

    def register_hook(self, name, func):
        self.hooks.append((name, func))


ctx = FakeCtx()
module.register(ctx)
expected_hooks = {
    "pre_tool_call",
    "post_tool_call",
    "on_session_end",
    "on_session_finalize",
    "subagent_stop",
}
registered = {name for name, _func in ctx.hooks}
if registered != expected_hooks:
    raise AssertionError(f"unexpected hooks registered: {sorted(registered)}")

secret_key = "OPENAI" + "_API_KEY"
secret_value = "sk-" + "test"
hooks.pre_tool_call(tool_name="bash", command="echo hello", env={secret_key: secret_value, "PATH": "/tmp/bin"})
hooks.post_tool_call(tool_name="bash", result={"exit_code": 0, "stdout": "ok"})
hooks.on_session_end(session_id="fake-session", project_root="/tmp/fake")
hooks.on_session_finalize(session_id="fake-session")
hooks.subagent_stop(agent="fake-agent", result={"status": "done"})

log_path = log_dir / "hooks.jsonl"
if not log_path.is_file() or log_path.stat().st_size == 0:
    raise AssertionError(f"missing hook log: {log_path}")

raw = log_path.read_text(encoding="utf-8")
if secret_value in raw:
    raise AssertionError("secret-like value was not redacted")
if "[REDACTED]" not in raw:
    raise AssertionError("redaction marker missing from hook log")

records = [json.loads(line) for line in raw.splitlines() if line.strip()]
if len(records) != 5:
    raise AssertionError(f"expected 5 hook records, got {len(records)}")
observed = {record.get("hook") for record in records}
if observed != expected_hooks:
    raise AssertionError(f"unexpected hook records: {sorted(observed)}")
for record in records:
    if record.get("prototype") is not True:
        raise AssertionError(f"missing prototype marker: {record}")
    if not isinstance(record.get("payload_keys"), list):
        raise AssertionError(f"missing payload_keys list: {record}")
    if not isinstance(record.get("payload_safe"), dict):
        raise AssertionError(f"missing payload_safe object: {record}")

print(json.dumps({
    "smoke": "plugin-hooks-source",
    "ok": True,
    "registered_hooks": sorted(registered),
    "records": len(records),
    "log_path": str(log_path),
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-plugin-hooks-source: PASS"
