#!/usr/bin/env bash
# smoke-plugin-hooks-v07-unit.sh — unit checks for v0.7 hook envelope/redaction.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
SCHEMA_PATH="$REPO_ROOT/schema/hook-event.schema.json"
TMP_ROOT="${TMPDIR:-/tmp}/hermes-v07-hook-unit-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT"
python3 -m py_compile "$PLUGIN_DIR"/*.py

PLUGIN_DIR="$PLUGIN_DIR" SCHEMA_PATH="$SCHEMA_PATH" TMP_ROOT="$TMP_ROOT" python3 <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import sys

plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
schema_path = pathlib.Path(os.environ["SCHEMA_PATH"]).resolve()
tmp_root = pathlib.Path(os.environ["TMP_ROOT"]).resolve()

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
redaction = importlib.import_module("hermes_evidence_runtime.redaction")


def validate_event_shape(record):
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    for key in schema["required"]:
        assert key in record, f"missing required key: {key}"
    assert record["schema_version"] == "0.7.0"
    assert record["capture_mode"] in {"real_runtime", "simulated_test"}
    assert record["provenance"]["captured_by"] == "hermes-evidence-runtime"
    assert record["provenance"]["source"] == "Hermes hook callback"
    assert record["provenance"]["log_only"] is True
    assert isinstance(record["payload"]["keys_observed"], list)


canary_token = "V07_CANARY_TOKEN_7f39e1"
canary_password = "V07_CANARY_PASSWORD_18ce42"
cycle = {}
cycle["self"] = cycle

payload = {
    "nested": {
        "Authorization": "Bearer abc.def.secret",
        "url": f"https://example.test/path?token={canary_token}&ok=1",
    },
    "password": canary_password,
    "long": "x" * 700,
    "bytes": b"secret bytes",
    "exception": RuntimeError(f"boom {canary_token}"),
    "cycle": cycle,
    "path": "/Users/example-user/project/file.txt",
}
safe, warnings = redaction.safe_serialize(payload)
raw = json.dumps(safe, ensure_ascii=False)
assert canary_token not in raw
assert canary_password not in raw
assert "Bearer abc.def.secret" not in raw
assert "/Users/example-user" not in raw
assert "x" * 600 not in raw
assert "cycle_detected" in warnings
assert "bytes_omitted" in warnings
assert "exception_serialized" in warnings

disabled_dir = tmp_root / "disabled"
os.environ.pop("HERMES_EVIDENCE_HOOK_LOG_DIR", None)
hooks.pre_tool_call(tool_name="noop", args={"token": canary_token})
assert not (disabled_dir / "hook-events.jsonl").exists()

log_dir = tmp_root / "enabled"
os.environ["HERMES_EVIDENCE_HOOK_LOG_DIR"] = str(log_dir)
os.environ["HERMES_EVIDENCE_HOOK_CAPTURE_MODE"] = "simulated_test"
hooks.pre_tool_call(
    tool_name="noop",
    args={"token": canary_token, "password": canary_password},
    session_id="session-secret",
    tool_call_id="call-secret",
)
log_path = log_dir / "hook-events.jsonl"
assert log_path.is_file() and log_path.stat().st_size > 0
records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]
assert len(records) == 1
record = records[0]
validate_event_shape(record)
assert record["capture_mode"] == "simulated_test"
assert record["hook_name"] == "pre_tool_call"
assert record["session"]["session_id_hash"].startswith("sha256:")
assert "session-secret" not in json.dumps(record, ensure_ascii=False)
assert "call-secret" not in json.dumps(record, ensure_ascii=False)
assert canary_token not in json.dumps(record, ensure_ascii=False)
assert canary_password not in json.dumps(record, ensure_ascii=False)

original_append = hooks._append_event

def raising_append(*_args, **_kwargs):
    raise RuntimeError("forced append failure")

hooks._append_event = raising_append
try:
    assert hooks.post_tool_call(tool_name="noop", result={"ok": True}) is None
finally:
    hooks._append_event = original_append

summary_path = log_dir / "hook-summary.json"
assert summary_path.is_file()
summary = json.loads(summary_path.read_text(encoding="utf-8"))
assert summary["event_count"] >= 1

print(json.dumps({
    "smoke": "plugin-hooks-v07-unit",
    "ok": True,
    "schema_validated": True,
    "redaction_checked": True,
    "fail_open_checked": True,
    "log_path": str(log_path),
}, sort_keys=True))
PY

echo "smoke-plugin-hooks-v07-unit: PASS"
