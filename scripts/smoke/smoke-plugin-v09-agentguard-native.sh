#!/usr/bin/env bash
# smoke-plugin-v09-agentguard-native.sh — proves real Hermes AgentGuard pre_tool_call allow/block path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
AGENTGUARD_SOURCE="${AGENTGUARD_PLUGIN_SOURCE:-/tmp/hermes-v09-real-backend-research/agentguard/plugins/hermes}"
HERMES_AGENT_PYTHON="${HERMES_AGENT_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"
TMP_ROOT="$(mktemp -d /tmp/hermes-v09-agentguard-native.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$AGENTGUARD_SOURCE/plugin.yaml" ]]; then
  echo "FAIL: AgentGuard Hermes plugin source missing. Set AGENTGUARD_PLUGIN_SOURCE." >&2
  exit 1
fi

mkdir -p "$TMP_ROOT/.hermes/plugins" "$TMP_ROOT/project/.hermes-runs/agentguard-native/raw"
cp -R "$PLUGIN_DIR" "$TMP_ROOT/.hermes/plugins/hermes-evidence-runtime"
cp -R "$AGENTGUARD_SOURCE" "$TMP_ROOT/.hermes/plugins/agentguard"

cat >"$TMP_ROOT/agentguard-hook.js" <<'JS'
const fs = require('fs');
const crypto = require('crypto');
const payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
const command = payload?.tool_input?.command || payload?.args?.command || '';
const decision = String(command).includes('rm -rf /') ? 'block' : 'allow';
const logPath = process.env.AGENTGUARD_AUDIT_LOG;
if (logPath) {
  fs.appendFileSync(logPath, JSON.stringify({
    source: 'agentguard_native_hook_script',
    event: payload.hook_event_name || payload.event || '',
    tool_name: payload.tool_name || '',
    command_sha256: crypto.createHash('sha256').update(String(command)).digest('hex'),
    decision,
    observed_at: new Date().toISOString()
  }) + '\n');
}
if (decision === 'block') {
  process.stdout.write(JSON.stringify({
    action: 'block',
    message: 'GoPlus AgentGuard: synthetic destructive block'
  }));
} else {
  process.stdout.write('{}');
}
JS

HERMES_HOME="$TMP_ROOT/.hermes" hermes plugins enable hermes-evidence-runtime >/dev/null
HERMES_HOME="$TMP_ROOT/.hermes" hermes plugins enable agentguard >/dev/null
HERMES_HOME="$TMP_ROOT/.hermes" hermes plugins list --json >"$TMP_ROOT/plugins.json"

HERMES_HOME="$TMP_ROOT/.hermes" \
HERMES_DEV_PIPELINE_KIT_ROOT="$REPO_ROOT" \
HERMES_EVIDENCE_HOOK_LOG_DIR="$TMP_ROOT/evidence-hook-log" \
HERMES_EVIDENCE_HOOK_CAPTURE_MODE=real_runtime \
AGENTGUARD_HERMES_HOOK="$TMP_ROOT/agentguard-hook.js" \
AGENTGUARD_AUDIT_LOG="$TMP_ROOT/agentguard-audit.jsonl" \
AGENTGUARD_HERMES_AUTOSCAN=0 \
AGENTGUARD_HERMES_ALLOW_NPX=0 \
AGENTGUARD_HERMES_FAIL_OPEN=0 \
"$HERMES_AGENT_PYTHON" - <<'PY' "$TMP_ROOT" "$PLUGIN_DIR"
import importlib
import importlib.util
import json
import pathlib
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
plugin_dir = pathlib.Path(sys.argv[2])
run_dir = root / "project" / ".hermes-runs" / "agentguard-native"
for name, data in {
    "run-manifest.json": {"run_id": "agentguard-native", "task": "v0.9 AgentGuard native smoke"},
    "classification.json": {"scale": "M", "task_type": "integration"},
    "state.json": {"state": "RUNNING"},
}.items():
    (run_dir / name).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_runtime_plugin():
    spec = importlib.util.spec_from_file_location(
        "hermes_evidence_runtime",
        plugin_dir / "__init__.py",
        submodule_search_locations=[str(plugin_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load hermes-evidence-runtime")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return importlib.import_module("hermes_evidence_runtime.tools")


def tool_json(fn, payload):
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("ok") is not True:
        raise AssertionError(data)
    return data


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


from hermes_cli.plugins import discover_plugins, get_plugin_manager
import model_tools

discover_plugins(force=True)
manager = get_plugin_manager()
callbacks = [
    {
        "module": getattr(cb, "__module__", ""),
        "qualname": getattr(cb, "__qualname__", ""),
    }
    for cb in manager._hooks.get("pre_tool_call", [])
]

handler_calls = []


def canary_handler(args=None, **_kwargs):
    payload = dict(args or {})
    handler_calls.append(payload)
    with (root / "handler-entered.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")
    return {"ok": True, "handler_entered": True, "args": payload}


model_tools.registry.register(
    "terminal",
    "terminal",
    {
        "type": "object",
        "properties": {"command": {"type": "string"}},
        "required": ["command"],
    },
    canary_handler,
    override=True,
)

allow_result = model_tools.handle_function_call(
    "terminal",
    {"command": "pwd"},
    task_id="agentguard-allow",
    session_id="session-allow",
    tool_call_id="call-allow",
    enabled_toolsets=["terminal"],
)
allow_calls = len(handler_calls)
block_result = model_tools.handle_function_call(
    "terminal",
    {"command": "rm -rf /"},
    task_id="agentguard-block",
    session_id="session-block",
    tool_call_id="call-block",
    enabled_toolsets=["terminal"],
)
block_calls = len(handler_calls) - allow_calls

allow_parsed = allow_result if isinstance(allow_result, dict) else json.loads(allow_result)
block_parsed = block_result if isinstance(block_result, dict) else json.loads(block_result)
if allow_calls != 1 or allow_parsed.get("handler_entered") is not True:
    raise AssertionError("AgentGuard native allow did not enter terminal handler once")
if block_calls != 0:
    raise AssertionError("AgentGuard native block still entered terminal handler")
if "GoPlus AgentGuard" not in str(block_parsed.get("error", "")):
    raise AssertionError(f"AgentGuard native block missing error: {block_parsed}")

audit_path = root / "agentguard-audit.jsonl"
hook_log_path = root / "evidence-hook-log" / "hook-events.jsonl"
if not audit_path.is_file() or len(audit_path.read_text(encoding="utf-8").splitlines()) < 4:
    raise AssertionError("AgentGuard audit log missing native pre/post decisions")
if not hook_log_path.is_file() or len(hook_log_path.read_text(encoding="utf-8").splitlines()) < 4:
    raise AssertionError("evidence hook log missing Hermes pre/post observations")

tools = load_runtime_plugin()
tool_json(
    tools.evidence_record_security_decision,
    {
        "run_dir": str(run_dir),
        "decision": {
            "backend": "agentguard",
            "backend_version": "1.1.28",
            "available": True,
            "requested": True,
            "required": True,
            "selected": True,
            "used": True,
            "native_hook": True,
            "adapter_only": False,
            "handler_executed": True,
            "handler_executed_after_block": False,
            "decision": "allow",
            "reason": "native AgentGuard pre_tool_call allowed benign terminal command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": str(audit_path),
        },
    },
)
tool_json(
    tools.evidence_record_security_decision,
    {
        "run_dir": str(run_dir),
        "decision": {
            "backend": "agentguard",
            "backend_version": "1.1.28",
            "available": True,
            "requested": True,
            "required": True,
            "selected": True,
            "used": True,
            "native_hook": True,
            "adapter_only": False,
            "handler_executed": False,
            "handler_executed_after_block": False,
            "decision": "block",
            "reason": "native AgentGuard pre_tool_call blocked synthetic destructive terminal command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": str(audit_path),
        },
    },
)

summary = {
    "smoke": "plugin-v09-agentguard-native",
    "ok": True,
    "agentguard_plugin_enabled": True,
    "evidence_plugin_enabled": True,
    "callback_order": callbacks,
    "allow_handler_calls": allow_calls,
    "block_handler_calls": block_calls,
    "security_decisions_path": str(run_dir / "raw" / "security-decisions.jsonl"),
    "agentguard_audit_path": str(audit_path),
    "evidence_hook_log_path": str(hook_log_path),
}
(root / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-plugin-v09-agentguard-native: PASS"
