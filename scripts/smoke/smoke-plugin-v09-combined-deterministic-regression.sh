#!/usr/bin/env bash
# smoke-plugin-v09-combined-deterministic-regression.sh — deterministic checks for combined backend smoke safety.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMBINED="$REPO_ROOT/scripts/smoke/smoke-plugin-v09-combined-real-backends.sh"
HERMES_AGENT_PYTHON="${HERMES_AGENT_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"

python3 - <<'PY' "$COMBINED" "$HERMES_AGENT_PYTHON"
import pathlib
import subprocess
import sys
import tempfile

combined = pathlib.Path(sys.argv[1])
agent_python = pathlib.Path(sys.argv[2])
source = combined.read_text(encoding="utf-8")

required_markers = [
    "def restore_terminal_entry()",
    "terminal_registry_restored = False",
    "finally:",
    "restore_terminal_entry()",
]
missing = [marker for marker in required_markers if marker not in source]
if missing:
    raise AssertionError("combined smoke missing deterministic restore markers: " + ", ".join(missing))

tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="hermes-v09-combined-deterministic."))
probe = tmp_root / "registry_probe.py"
probe.write_text(
    r'''
import model_tools

calls = []


def original_handler(args=None, **_kwargs):
    calls.append(("original", dict(args or {})))
    return {"handler": "original"}


def canary_handler(args=None, **_kwargs):
    calls.append(("canary", dict(args or {})))
    return {"handler": "canary"}


model_tools.registry.register(
    "terminal",
    "terminal",
    {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]},
    original_handler,
    override=True,
)
original_terminal_entry = model_tools.registry.get_entry("terminal")
if original_terminal_entry is None:
    raise AssertionError("terminal entry not available before canary override")


def restore_terminal_entry():
    model_tools.registry.register(
        "terminal",
        original_terminal_entry.toolset,
        original_terminal_entry.schema,
        original_terminal_entry.handler,
        check_fn=original_terminal_entry.check_fn,
        requires_env=original_terminal_entry.requires_env,
        is_async=original_terminal_entry.is_async,
        description=original_terminal_entry.description,
        emoji=original_terminal_entry.emoji,
        max_result_size_chars=original_terminal_entry.max_result_size_chars,
        dynamic_schema_overrides=original_terminal_entry.dynamic_schema_overrides,
        override=True,
    )


model_tools.registry.register(
    "terminal",
    "terminal",
    {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]},
    canary_handler,
    override=True,
)
entry = model_tools.registry.get_entry("terminal")
if entry is None or entry.handler is not canary_handler:
    raise AssertionError("canary handler was not installed")
restore_terminal_entry()
entry = model_tools.registry.get_entry("terminal")
if entry is None or entry.handler is not original_handler:
    raise AssertionError("terminal handler was not restored after normal path")

try:
    model_tools.registry.register(
        "terminal",
        "terminal",
        {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]},
        canary_handler,
        override=True,
    )
    raise RuntimeError("synthetic failure after canary override")
except RuntimeError:
    pass
finally:
    restore_terminal_entry()

entry = model_tools.registry.get_entry("terminal")
if entry is None or entry.handler is not original_handler:
    raise AssertionError("terminal handler was not restored after exception path")

print("registry restore probe PASS")
''',
    encoding="utf-8",
)
subprocess.run([str(agent_python), str(probe)], check=True)
print("smoke-plugin-v09-combined-deterministic-regression: PASS")
PY
