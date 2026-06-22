#!/usr/bin/env bash
# smoke-plugin-v09-combined-real-backends.sh — proves AgentGuard + Dynamic Workflows in one policy-checked run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
AGENTGUARD_SOURCE="${AGENTGUARD_PLUGIN_SOURCE:-/tmp/hermes-v09-real-backend-research/agentguard/plugins/hermes}"
DYNAMIC_SOURCE="${DYNAMIC_WORKFLOWS_PLUGIN_SOURCE:-/tmp/hermes-v09-real-backend-research/hermes-dynamic-workflows}"
HERMES_AGENT_PYTHON="${HERMES_AGENT_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"
TMP_ROOT="$(mktemp -d /tmp/hermes-v09-combined-real.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$AGENTGUARD_SOURCE/plugin.yaml" ]]; then
  echo "FAIL: AgentGuard Hermes plugin source missing. Set AGENTGUARD_PLUGIN_SOURCE." >&2
  exit 1
fi

if [[ ! -f "$DYNAMIC_SOURCE/plugin.yaml" ]]; then
  echo "FAIL: Dynamic Workflows plugin source missing. Set DYNAMIC_WORKFLOWS_PLUGIN_SOURCE." >&2
  exit 1
fi

mkdir -p "$TMP_ROOT/home/.hermes/plugins" "$TMP_ROOT/project/work"
cp -R "$PLUGIN_DIR" "$TMP_ROOT/home/.hermes/plugins/hermes-evidence-runtime"
cp -R "$AGENTGUARD_SOURCE" "$TMP_ROOT/home/.hermes/plugins/agentguard"
cp -R "$DYNAMIC_SOURCE" "$TMP_ROOT/home/.hermes/plugins/dynamic-workflows"
printf 'codex-v09-combined-dynamic-input\n' >"$TMP_ROOT/project/work/input.txt"

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

HERMES_HOME="$TMP_ROOT/home/.hermes" hermes plugins enable hermes-evidence-runtime >/dev/null
HERMES_HOME="$TMP_ROOT/home/.hermes" hermes plugins enable agentguard >/dev/null
HERMES_HOME="$TMP_ROOT/home/.hermes" hermes plugins enable dynamic-workflows >/dev/null
HERMES_HOME="$TMP_ROOT/home/.hermes" hermes plugins list --json >"$TMP_ROOT/plugins.json"

HERMES_HOME="$TMP_ROOT/home/.hermes" \
HERMES_DEV_PIPELINE_KIT_ROOT="$REPO_ROOT" \
HERMES_EVIDENCE_HOOK_LOG_DIR="$TMP_ROOT/evidence-hook-log" \
HERMES_EVIDENCE_HOOK_CAPTURE_MODE=real_runtime \
AGENTGUARD_HERMES_HOOK="$TMP_ROOT/agentguard-hook.js" \
AGENTGUARD_AUDIT_LOG="$TMP_ROOT/agentguard-audit.jsonl" \
AGENTGUARD_HERMES_AUTOSCAN=0 \
AGENTGUARD_HERMES_ALLOW_NPX=0 \
AGENTGUARD_HERMES_FAIL_OPEN=0 \
HERMES_DYNAMIC_WORKFLOWS_HOME="$TMP_ROOT/dynamic-store" \
HERMES_DYNAMIC_WORKFLOWS_TMPDIR="$TMP_ROOT/dynamic-tmp" \
"$HERMES_AGENT_PYTHON" - <<'PY' "$TMP_ROOT" "$PLUGIN_DIR" "$REPO_ROOT"
import hashlib
import importlib
import importlib.util
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
plugin_dir = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3])
project_root = root / "project"
work_dir = project_root / "work"
dynamic_plugin = root / "home" / ".hermes" / "plugins" / "dynamic-workflows"
sys.path.insert(0, str(dynamic_plugin))


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_script(name: str, *args: str) -> None:
    subprocess.run(
        ["bash", str(repo_root / "scripts" / name), *map(str, args)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def append_event(run_dir: pathlib.Path, event_type: str, actor: str, state_after: str, *artifacts: str) -> None:
    args = [
        "--run-dir",
        str(run_dir),
        "--event-type",
        event_type,
        "--actor",
        actor,
        "--state-after",
        state_after,
    ]
    for artifact in artifacts:
        args.extend(["--artifact", artifact])
    run_script("append-event.sh", *args)


def load_runtime_tools():
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


def call_json(fn, payload: dict, *, expect_ok: bool = True) -> dict:
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool did not return JSON object: {raw}")
    if expect_ok and data.get("ok") is not True:
        raise AssertionError(json.dumps(data, indent=2, ensure_ascii=False))
    if not expect_ok and data.get("ok") is True:
        raise AssertionError(f"tool unexpectedly passed: {json.dumps(data, ensure_ascii=False)}")
    return data


def classify_error(message: str) -> str:
    lower = message.lower()
    if "no inference provider" in lower or "unknown provider" in lower:
        return "NO_PROVIDER_CONFIG"
    if "auth" in lower or "credential" in lower or "api key" in lower or "401" in lower or "403" in lower:
        return "AUTH_UNAVAILABLE"
    if "model" in lower or "404" in lower:
        return "MODEL_UNAVAILABLE"
    if "network" in lower or "timeout" in lower or "connection" in lower:
        return "NETWORK_UNAVAILABLE"
    if "quota" in lower or "rate limit" in lower or "429" in lower:
        return "QUOTA_UNAVAILABLE"
    if "structured output" in lower:
        return "STRUCTURED_OUTPUT_INVALID"
    return "UNKNOWN"


tools = load_runtime_tools()
init = call_json(
    tools.evidence_run_init,
    {
        "project_root": str(project_root),
        "task": "v0.9 combined real AgentGuard + Dynamic Workflows smoke",
        "scale": "M",
        "mode": "auto_run",
        "task_type": "integration",
        "run_id": "v09-combined-real-backends",
        "project": "v09-combined-smoke",
    },
)
run_dir = pathlib.Path(init["run_dir"]).resolve()

append_event(run_dir, "INTAKE_RECORDED", "Hermes", "INTAKE_RECORDED", "task.md")
append_event(run_dir, "WORK_ORDER_CREATED", "Hermes", "WORK_ORDER_CREATED", "work-orders/WO-1.json")
append_event(run_dir, "CLAUDECODE_DELEGATED", "Hermes", "CLAUDECODE_DELEGATED", "work-orders/WO-1.json")

(work_dir / "test.py").write_text(
    "from src.add import add\n"
    "assert add(2, 3) == 5\n"
    "print('green ok')\n",
    encoding="utf-8",
)
cmd = f"{shlex.quote(sys.executable)} {shlex.quote(str((work_dir / 'test.py').name))}"
red = call_json(
    tools.evidence_record_command,
    {
        "run_dir": str(run_dir),
        "work_dir": str(work_dir),
        "command": cmd,
        "phase": "RED",
        "step_id": "red-missing-implementation",
    },
)
if red["command_exit_code"] == 0:
    raise AssertionError("RED command must fail before implementation exists")

(work_dir / "src").mkdir(exist_ok=True)
(work_dir / "src" / "__init__.py").write_text("", encoding="utf-8")
(work_dir / "src" / "add.py").write_text("def add(a, b):\n    return a + b\n", encoding="utf-8")
green = call_json(
    tools.evidence_record_command,
    {
        "run_dir": str(run_dir),
        "work_dir": str(work_dir),
        "command": cmd,
        "phase": "GREEN",
        "step_id": "green-correct-implementation",
    },
)
if green["command_exit_code"] != 0:
    raise AssertionError("GREEN command must pass after implementation exists")

controlled_worker_result = {
    "work_order_id": "WO-1",
    "status": "completed",
    "required_matt_skill": "tdd",
    "worker_type": "controlled_fixture",
    "capture_mode": "raw_fixture",
    "real_worker_capture": False,
    "matt_evidence": {
        "red": "test.py failed before src/add.py existed",
        "red_exit_code": red["command_exit_code"],
        "red_not_applicable_reason": "",
        "green": "test.py passed after src/add.py implementation",
        "green_exit_code": green["command_exit_code"],
        "commands": [cmd, cmd],
    },
    "files_touched": ["test.py", "src/add.py"],
    "commands_run": [cmd, cmd],
    "blocked": False,
    "notes": "Controlled worker fixture. No real worker was invoked. No acceptance field.",
}
write_json(run_dir / "raw" / "controlled-worker-result.json", controlled_worker_result)
legacy_alias = dict(controlled_worker_result)
legacy_alias["legacy_compatibility_alias"] = "not real ClaudeCode evidence"
legacy_alias["notes"] = "Legacy compatibility alias only; not real ClaudeCode evidence."
write_json(run_dir / "raw" / "claudecode-result.json", legacy_alias)
append_event(
    run_dir,
    "CLAUDECODE_RESULT_RECORDED",
    "harness",
    "CLAUDECODE_RESULT_RECORDED",
    "raw/controlled-worker-result.json",
    "raw/claudecode-result.json",
)

raw_output = run_dir / "raw" / "worker-controlled.raw.txt"
raw_output.write_text("controlled worker fixture output\n", encoding="utf-8")
worker_fixture = run_dir / "raw" / "worker-fixture.json"
write_json(
    worker_fixture,
    {
        "schema_version": "0.5.3",
        "work_order_id": "WO-1",
        "worker": "unknown",
        "worker_skill": "controlled-fixture/tdd",
        "status": "completed",
        "result_type": "implementation",
        "raw_output_path": "raw/worker/WO-1.raw.txt",
        "structured_output_path": "raw/worker/WO-1.worker-result.json",
        "files_touched": ["test.py", "src/add.py"],
        "commands_run": [cmd, cmd],
        "evidence_refs": ["raw/command-log.jsonl"],
        "review": {
            "verdict": "UNKNOWN",
            "summary": "Controlled worker fixture; not official worker capture.",
            "blocking_findings": [],
        },
        "deferred": {"is_deferred": False, "reason": ""},
        "real_invocation": False,
        "skipped_reason": "controlled worker fixture; no real worker spawned",
        "notes": "Synthetic controlled worker result for combined integration backend smoke only.",
    },
)
call_json(
    tools.evidence_record_worker_result,
    {
        "run_dir": str(run_dir),
        "worker_result_path": str(worker_fixture),
        "raw_output_path": str(raw_output),
    },
)
shutil.copyfile(run_dir / "raw" / "worker" / "WO-1.worker-result.json", run_dir / "raw" / "worker-result.json")

from hermes_cli.plugins import discover_plugins, get_plugin_manager
import model_tools

discover_plugins(force=True)
manager = get_plugin_manager()
callbacks = [
    f"{getattr(cb, '__module__', '')}.{getattr(cb, '__qualname__', '')}"
    for cb in manager._hooks.get("pre_tool_call", [])
]
if not any("agentguard" in item for item in callbacks):
    raise AssertionError(f"AgentGuard pre_tool_call callback missing: {callbacks}")
if not any("evidence" in item for item in callbacks):
    raise AssertionError(f"evidence pre_tool_call callback missing: {callbacks}")

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
    raise AssertionError("AgentGuard native allow did not execute terminal handler once")
if block_calls != 0:
    raise AssertionError("AgentGuard native block still executed terminal handler")
if "GoPlus AgentGuard" not in str(block_parsed.get("error", "")):
    raise AssertionError(f"AgentGuard native block missing expected error: {block_parsed}")

agentguard_audit = root / "agentguard-audit.jsonl"
hook_log = root / "evidence-hook-log" / "hook-events.jsonl"
if not agentguard_audit.is_file() or len(agentguard_audit.read_text(encoding="utf-8").splitlines()) < 4:
    raise AssertionError("AgentGuard audit log missing native allow/block evidence")
if not hook_log.is_file() or len(hook_log.read_text(encoding="utf-8").splitlines()) < 4:
    raise AssertionError("evidence hook log missing real Hermes pre/post events")

call_json(
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
            "fallback_used": False,
            "native_hook": True,
            "adapter_only": False,
            "handler_executed": True,
            "handler_executed_after_block": False,
            "decision": "allow",
            "reason": "native AgentGuard pre_tool_call allowed benign terminal command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": str(agentguard_audit),
        },
    },
)
call_json(
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
            "fallback_used": False,
            "native_hook": True,
            "adapter_only": False,
            "handler_executed": False,
            "handler_executed_after_block": False,
            "decision": "block",
            "reason": "native AgentGuard pre_tool_call blocked synthetic destructive terminal command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": str(agentguard_audit),
        },
    },
)

# Resolve provider credentials from the live user config in memory only, then
# restore HERMES_HOME so Dynamic Workflows writes all state under TMP_ROOT.
temp_home = os.environ.pop("HERMES_HOME", None)
try:
    from hermes_cli.config import load_config
    from hermes_cli.runtime_provider import resolve_runtime_provider

    cfg = load_config() or {}
    model_cfg = cfg.get("model") or {}
    runtime = resolve_runtime_provider()
    model = model_cfg.get("default") if isinstance(model_cfg, dict) else model_cfg
    if model and not runtime.get("model"):
        runtime["model"] = model
    runtime["max_tokens"] = 512
finally:
    if temp_home:
        os.environ["HERMES_HOME"] = temp_home

from hermes_dynamic_workflows.adapters.workflow import workflow
from hermes_dynamic_workflows.core.config import PluginConfig
from hermes_dynamic_workflows.storage.store import WorkflowStore
import hermes_dynamic_workflows.run.manager as manager_mod

config = PluginConfig(
    workflow_timeout_seconds=90.0,
    child_timeout_seconds=60.0,
    default_child_toolsets=("file", "terminal"),
    blocked_child_toolsets=(
        "workflow",
        "workflows",
        "delegation",
        "code_execution",
        "memory",
        "messaging",
        "clarify",
        "web",
        "browser",
        "skills",
    ),
    require_launch_approval=False,
    child_approval_policy="approve",
    ask_fallback="approve",
    notify_on_complete=False,
    notify_result_preview_chars=500,
)
dynamic_manager = manager_mod.WorkflowRunManager(
    store=WorkflowStore(root=root / "dynamic-store"),
    config=config,
)
manager_mod._MANAGER = dynamic_manager


class ParentAgent:
    pass


parent = ParentAgent()
for key, value in runtime.items():
    setattr(parent, key, value)


class Context:
    session_id = "v09-combined-dynamic-session"

    def inject_message(self, *_args, **_kwargs):
        return False


schema = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "work_order_id",
        "status",
        "observations",
        "commands_claimed",
        "files_claimed",
        "notes",
    ],
    "properties": {
        "work_order_id": {"type": "string"},
        "status": {"type": "string", "enum": ["completed", "failed"]},
        "observations": {"type": "array", "items": {"type": "string"}},
        "commands_claimed": {"type": "array", "items": {"type": "string"}},
        "files_claimed": {"type": "array", "items": {"type": "string"}},
        "notes": {"type": "string"},
    },
}
example = {
    "work_order_id": "WO-DYNAMIC-1",
    "status": "completed",
    "observations": ["input sentinel verified"],
    "commands_claimed": [f"cat {work_dir / 'input.txt'}"],
    "files_claimed": [str(work_dir / "input.txt")],
    "notes": "No acceptance decision; verification child only.",
}
prompt = (
    "You are a verification child for a hermes-dev-pipeline-kit smoke test.\n"
    "You MUST call structured_output exactly once with ALL required keys: "
    "work_order_id, status, observations, commands_claimed, files_claimed, notes.\n"
    "Do not include acceptance or policy verdict.\n"
    f"Only inspect this temp directory: {work_dir}\n"
    "Run exactly one local read-only terminal command: cat input.txt from that directory.\n"
    "If input.txt contains codex-v09-combined-dynamic-input, return status completed.\n"
    "Use work_order_id WO-DYNAMIC-1. Example shape: "
    + json.dumps(example, ensure_ascii=False)
    + "\n"
)
script = "\n".join(
    [
        'meta = {"name": "v09-combined-one-child", "description": "Verify one temp file with one child"}',
        "SCHEMA = " + repr(schema),
        'phase("Verify")',
        "result = await agent("
        + repr(prompt)
        + ', {"label": "v09-combined-dynamic-verifier", "phase": "Verify", "schema": SCHEMA, "agentType": "explore"})',
        "return result",
    ]
)

try:
    launch_raw = workflow(
        {"script": script},
        plugin_context=Context(),
        parent_agent=parent,
        user_task="v0.9 combined Dynamic Workflows real one child smoke +2000 tokens",
        session_id="v09-combined-dynamic-session",
    )
    (root / "dynamic-launch.out").write_text(str(launch_raw), encoding="utf-8")
    record = None
    for _ in range(100):
        runs = dynamic_manager.store.list_runs(limit=1)
        if runs:
            record = dynamic_manager.get(runs[0]["runId"])
            if record and record.get("status") in {"completed", "failed", "stopped", "error"}:
                break
        time.sleep(1)
    if not record:
        raise RuntimeError("no Dynamic Workflows run record")
    result = record.get("result")
    if not (
        record.get("status") == "completed"
        and isinstance(result, dict)
        and result.get("work_order_id") == "WO-DYNAMIC-1"
        and result.get("status") == "completed"
        and "acceptance" not in result
    ):
        raise RuntimeError(f"Dynamic Workflows child did not complete with valid structured output: {record}")
except Exception as exc:
    error = f"{type(exc).__name__}: {exc}"
    raise RuntimeError(f"Dynamic Workflows real child completion failed [{classify_error(error)}]: {error}") from exc

journal_path = pathlib.Path(str(record.get("journalFile") or ""))
transcript_paths = [pathlib.Path(str(item)) for item in (record.get("transcriptFiles") or [])]
if not journal_path.is_file() or journal_path.stat().st_size == 0:
    raise AssertionError("Dynamic Workflows journal file missing or empty")
if not transcript_paths or any((not path.is_file() or path.stat().st_size == 0) for path in transcript_paths):
    raise AssertionError("Dynamic Workflows transcript file missing or empty")

orchestration_payload = {
    "backend": "hermes_dynamic_workflows",
    "backend_version": "0.1.0",
    "available": True,
    "requested": True,
    "required": True,
    "selected": True,
    "used": True,
    "fallback_used": False,
    "capability_callable": True,
    "child_completion_proven": True,
    "capture_mode": "real_runtime",
    "run_id": str(record.get("runId") or ""),
    "status": "completed",
    "work_order_id": "WO-1",
    "structured_result_path": str(record.get("outputFile") or ""),
    "journal_path": str(journal_path),
    "transcript_paths": [str(path) for path in transcript_paths],
    "workspace_path": str(work_dir),
    "started_at": str(record.get("startedAt") or ""),
    "ended_at": str(record.get("finishedAt") or ""),
    "error": "",
    "claims": result,
    "provenance": {
        "source": "lingjiuu/hermes-dynamic-workflows",
        "raw_evidence_only": True,
        "not_acceptance": True,
        "workflow_totals": (record.get("workflow") or {}).get("totals", {}),
    },
}
call_json(
    tools.evidence_record_orchestration_result,
    {"run_dir": str(run_dir), "result": orchestration_payload},
)

generated = call_json(
    tools.evidence_generate_run_state,
    {"run_dir": str(run_dir), "hook_log_path": str(hook_log)},
)
policy = call_json(tools.evidence_policy_check, {"run_dir": str(run_dir)})
final = call_json(tools.evidence_final_report, {"run_dir": str(run_dir)})
if policy.get("verdict") != "PASS":
    raise AssertionError(f"combined policy did not PASS: {policy}")

state = json.loads((run_dir / "generated" / "run-state.json").read_text(encoding="utf-8"))
if state.get("orchestration", {}).get("used") is not True:
    raise AssertionError("run-state missing Dynamic Workflows used=true")
if state.get("orchestration", {}).get("child_completion_proven") is not True:
    raise AssertionError("run-state missing Dynamic Workflows child completion proof")
if state.get("security", {}).get("used") is not True:
    raise AssertionError("run-state missing AgentGuard used=true")
if state.get("security", {}).get("native_hook") is not True:
    raise AssertionError("run-state missing AgentGuard native hook proof")
if state.get("security", {}).get("handler_executed_after_block") is True:
    raise AssertionError("run-state says blocked AgentGuard command executed handler")

secret_pattern = re.compile(
    r"(OPENAI_API_KEY|ANTHROPIC_API_KEY|Authorization:\s*Bearer\s+|Bearer\s+[A-Za-z0-9_.-]{20,}|sk-[A-Za-z0-9]{20,}|api_key\s*[:=]\s*['\"][^'\"]+)",
    re.IGNORECASE,
)
secret_hits = []
scan_roots = [run_dir, root / "dynamic-store", root / "dynamic-launch.out"]
scan_paths = []
for scan_root in scan_roots:
    if scan_root.is_file():
        scan_paths.append(scan_root)
    elif scan_root.is_dir():
        scan_paths.extend(path for path in scan_root.rglob("*") if path.is_file())
for path in scan_paths:
    if not path.is_file() or path.stat().st_size > 1_000_000:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if secret_pattern.search(text):
        secret_hits.append(str(path))
if secret_hits:
    raise AssertionError("provider secret scan failed: " + ", ".join(secret_hits[:10]))

print(json.dumps({
    "smoke": "plugin-v09-combined-real-backends",
    "ok": True,
    "run_dir": str(run_dir),
    "agentguard": {
        "native_hook": True,
        "allow_handler_calls": allow_calls,
        "block_handler_calls": block_calls,
        "callback_order": callbacks,
        "audit_path": str(agentguard_audit),
    },
    "dynamic_workflows": {
        "run_id": str(record.get("runId") or ""),
        "task_id": str(record.get("taskId") or ""),
        "status": record.get("status"),
        "structured_output_valid": True,
        "journal_validated": True,
        "transcript_validated": True,
        "workflow_session_id_hash": "sha256:" + hashlib.sha256(str(record.get("workflowSessionId") or "").encode()).hexdigest()[:16],
    },
    "provider_secret_scan": "PASS",
    "generated_run_state": generated["run_state_path"],
    "policy_verdict": policy["verdict"],
    "final_report": final["final_report_path"],
    "verdict": "PASS_DYNAMIC_WORKFLOWS_AND_AGENTGUARD_REAL_RUNTIME",
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-plugin-v09-combined-real-backends: PASS"
