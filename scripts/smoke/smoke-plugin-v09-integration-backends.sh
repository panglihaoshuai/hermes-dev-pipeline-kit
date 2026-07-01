#!/usr/bin/env bash
# smoke-plugin-v09-integration-backends.sh — source-only smoke for optional v0.9 integration backends.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="/tmp/hermes-v09-integration-backends-$$"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT"

python3 -m py_compile "$PLUGIN_DIR"/*.py "$PLUGIN_DIR"/integrations/*.py

PLUGIN_DIR="$PLUGIN_DIR" REPO_ROOT="$REPO_ROOT" TMP_ROOT="$TMP_ROOT" python3 <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import shutil
import shlex
import stat
import subprocess
import sys
from datetime import datetime, timezone

plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
repo_root = pathlib.Path(os.environ["REPO_ROOT"]).resolve()
tmp_root = pathlib.Path(os.environ["TMP_ROOT"]).resolve()
project_root = tmp_root / "project"
work_dir = project_root / "work"
hook_dir = tmp_root / "hook-log"
fake_bin = tmp_root / "bin"
fake_home = tmp_root / "home" / ".hermes"
dynamic_src = tmp_root / "dynamic-workflows"
agentguard_src = tmp_root / "agentguard" / "plugins" / "hermes"

for path in (work_dir, hook_dir, fake_bin, fake_home, dynamic_src / "hermes_dynamic_workflows", agentguard_src):
    path.mkdir(parents=True, exist_ok=True)

(dynamic_src / "plugin.yaml").write_text(
    "name: dynamic-workflows\nversion: 0.1.0\nkind: standalone\nprovides_tools:\n  - workflow\n",
    encoding="utf-8",
)
(dynamic_src / "hermes_dynamic_workflows" / "__init__.py").write_text("", encoding="utf-8")
(agentguard_src / "plugin.yaml").write_text(
    "name: agentguard\nversion: 1.1.28\nprovides_hooks:\n  - pre_tool_call\n  - post_tool_call\n",
    encoding="utf-8",
)

fake_hermes = fake_bin / "hermes"
fake_hermes.write_text(
    "#!/usr/bin/env bash\n"
    "set -euo pipefail\n"
    "if [[ ${1:-} == plugins && ${2:-} == list && ${3:-} == --json ]]; then\n"
    "  cat <<'JSON'\n"
    "[{\"name\":\"dynamic-workflows\",\"version\":\"0.1.0\",\"status\":\"enabled\"},{\"name\":\"agentguard\",\"version\":\"1.1.28\",\"status\":\"enabled\"}]\n"
    "JSON\n"
    "  exit 0\n"
    "fi\n"
    "if [[ ${1:-} == tools && ${2:-} == list ]]; then\n"
    "  printf '%s\\n' 'workflow' 'evidence_integration_capabilities'\n"
    "  exit 0\n"
    "fi\n"
    "exit 2\n",
    encoding="utf-8",
)
fake_hermes.chmod(fake_hermes.stat().st_mode | stat.S_IXUSR)
os.environ["PATH"] = f"{fake_bin}:{os.environ.get('PATH', '')}"
os.environ["HERMES_DEV_PIPELINE_KIT_ROOT"] = str(repo_root)
os.environ["HERMES_EVIDENCE_HOOK_LOG_DIR"] = str(hook_dir)
os.environ["HERMES_EVIDENCE_HOOK_CAPTURE_MODE"] = "real_runtime"

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
hooks = importlib.import_module("hermes_evidence_runtime.hooks")


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def call_json(fn, payload, *, expect_ok=True):
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool did not return object: {raw}")
    if expect_ok and data.get("ok") is not True:
        raise AssertionError(f"tool failed: {json.dumps(data, indent=2, ensure_ascii=False)}")
    if not expect_ok and data.get("ok") is True:
        raise AssertionError(f"tool unexpectedly passed: {json.dumps(data, indent=2, ensure_ascii=False)}")
    return data


def write_json(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_script(name, *args):
    subprocess.run(
        ["bash", str(repo_root / "scripts" / name), *map(str, args)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def append_event(run_dir, event_type, actor, state_after, *artifacts):
    args = [
        "--run-dir",
        run_dir,
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


caps = call_json(
    tools.evidence_integration_capabilities,
    {
        "hermes_home": str(fake_home),
        "dynamic_workflows_path": str(dynamic_src),
        "agentguard_path": str(agentguard_src),
    },
)
dynamic = caps["dynamic_workflows"]
guard = caps["agentguard"]
if not (dynamic["discovered"] and dynamic["enabled"] and dynamic["callable"]):
    raise AssertionError(f"Dynamic Workflows capability not callable in temp smoke: {dynamic}")
if not (guard["discovered"] and guard["enabled"] and guard["callable"]):
    raise AssertionError(f"AgentGuard capability not callable in temp smoke: {guard}")
if caps["boundary"]["dynamic_workflows_owns_acceptance"] is not False:
    raise AssertionError("Dynamic Workflows boundary must not own acceptance")
if caps["boundary"]["agentguard_allow_is_delivery_pass"] is not False:
    raise AssertionError("AgentGuard allow must not become delivery PASS")

init = call_json(
    tools.evidence_run_init,
    {
        "project_root": str(project_root),
        "task": "v0.9 integration backend smoke",
        "scale": "M",
        "mode": "auto_run",
        "task_type": "integration",
        "run_id": "v09-integration-backends",
        "project": "v09-smoke",
    },
)
run_dir = pathlib.Path(init["run_dir"]).resolve()
append_event(str(run_dir), "INTAKE_RECORDED", "Hermes", "INTAKE_RECORDED", "task.md")
append_event(str(run_dir), "WORK_ORDER_CREATED", "Hermes", "WORK_ORDER_CREATED", "work-orders/WO-1.json")
append_event(str(run_dir), "CLAUDECODE_DELEGATED", "Hermes", "CLAUDECODE_DELEGATED", "work-orders/WO-1.json")

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
    raise AssertionError("RED must fail before implementation exists")

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
    raise AssertionError(f"GREEN must pass: {green}")

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
    str(run_dir),
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
        "notes": "Synthetic controlled worker result for integration backend smoke only.",
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

hooks.pre_tool_call(tool_name="evidence_record_command", session_id="v09-session", tool_call_id="v09-pre")
hooks.post_tool_call(tool_name="evidence_record_command", session_id="v09-session", tool_call_id="v09-post")
hook_log = hook_dir / "hook-events.jsonl"
if not hook_log.is_file() or hook_log.stat().st_size == 0:
    raise AssertionError("hook log missing")

journal = tmp_root / "dynamic-workflows" / "journal.jsonl"
transcript = tmp_root / "dynamic-workflows" / "transcript.txt"
journal.parent.mkdir(parents=True, exist_ok=True)
journal.write_text('{"event":"failed","reason":"No inference provider configured"}\n', encoding="utf-8")
transcript.write_text("Dynamic Workflows launch observed; real child completion unavailable in temp HOME.\n", encoding="utf-8")
orchestration = call_json(
    tools.evidence_record_orchestration_result,
    {
        "run_dir": str(run_dir),
        "result": {
            "available": False,
            "requested": True,
            "required": False,
            "selected": False,
            "used": False,
            "fallback_used": True,
            "capability_callable": True,
            "child_completion_proven": False,
            "backend_version": "0.1.0",
            "work_order_id": "WO-1",
            "error": "No inference provider configured in temp HOME",
            "record": {
                "runId": "dw-v09-temp",
                "status": "failed",
                "cwd": str(work_dir),
                "journalFile": str(journal),
                "transcriptFiles": [str(transcript)],
                "outputFile": "",
                "startedAt": now(),
                "finishedAt": now(),
                "error": "No inference provider configured in temp HOME",
                "result": {"verdict": "BACKEND_UNAVAILABLE"},
            },
        },
    },
)
if orchestration["backend"] != "hermes_dynamic_workflows" or orchestration["status"] != "failed":
    raise AssertionError(f"unexpected orchestration result: {orchestration}")

call_json(
    tools.evidence_record_security_decision,
    {
        "run_dir": str(run_dir),
        "decision": {
            "backend": "agentguard",
            "backend_version": "1.1.28",
            "available": True,
            "requested": True,
            "required": False,
            "selected": False,
            "used": False,
            "native_hook": False,
            "adapter_only": True,
            "handler_executed": False,
            "handler_executed_after_block": False,
            "decision": "allow",
            "reason": "benign read-only command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": "agentguard-temp-hook-allow",
        },
    },
)
security_block = call_json(
    tools.evidence_record_security_decision,
    {
        "run_dir": str(run_dir),
        "decision": {
            "backend": "agentguard",
            "backend_version": "1.1.28",
            "available": True,
            "requested": True,
            "required": False,
            "selected": False,
            "used": False,
            "native_hook": False,
            "adapter_only": True,
            "handler_executed": False,
            "handler_executed_after_block": False,
            "decision": "block",
            "reason": "dangerous destructive command",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": "agentguard-temp-hook-block",
        },
    },
)
if security_block["decision"] != "block":
    raise AssertionError(f"unexpected security block result: {security_block}")

call_json(
    tools.evidence_record_orchestration_result,
    {
        "run_dir": str(run_dir),
        "result": {
            "backend": "hermes_dynamic_workflows",
            "backend_version": "0.1.0",
            "available": True,
            "run_id": "bad",
            "status": "completed",
            "capture_mode": "real_runtime",
            "work_order_id": "WO-1",
            "structured_result_path": "",
            "journal_path": "",
            "transcript_paths": [],
            "workspace_path": str(work_dir),
            "started_at": now(),
            "ended_at": now(),
            "error": "",
            "acceptance": {"complete": True},
        },
    },
    expect_ok=False,
)
call_json(
    tools.evidence_record_security_decision,
    {
        "run_dir": str(run_dir),
        "decision": {
            "backend": "agentguard",
            "backend_version": "1.1.28",
            "available": True,
            "decision": "allow",
            "reason": "must not write policy pass",
            "action_type": "shell",
            "tool_name": "terminal",
            "evaluated_at": now(),
            "audit_reference": "bad-policy-pass",
            "policy_verdict": "PASS",
        },
    },
    expect_ok=False,
)

generated = call_json(
    tools.evidence_generate_run_state,
    {"run_dir": str(run_dir), "hook_log_path": str(hook_log)},
)
policy = call_json(tools.evidence_policy_check, {"run_dir": str(run_dir)})
final = call_json(tools.evidence_final_report, {"run_dir": str(run_dir)})

required = [
    "raw/orchestration-backend-result.json",
    "raw/security-decisions.jsonl",
    "generated/run-state.json",
    "generated/policy-result.json",
    "generated/final-report.md",
]
for rel in required:
    path = run_dir / rel
    if not path.is_file() or path.stat().st_size == 0:
        raise AssertionError(f"missing artifact: {rel}")

state = json.loads((run_dir / "generated" / "run-state.json").read_text(encoding="utf-8"))
if state.get("orchestration", {}).get("backend") != "hermes_dynamic_workflows":
    raise AssertionError("run-state missing Dynamic Workflows orchestration evidence")
if state.get("orchestration", {}).get("owns_acceptance") is not False:
    raise AssertionError("orchestration must not own acceptance")
if state.get("security", {}).get("backend") != "agentguard":
    raise AssertionError("run-state missing AgentGuard security evidence")
if state.get("security", {}).get("allow_is_delivery_pass") is not False:
    raise AssertionError("AgentGuard allow must not be delivery PASS")
sources = set(state.get("provenance", {}).get("source_files") or [])
for rel in ("raw/orchestration-backend-result.json", "raw/security-decisions.jsonl"):
    if rel not in sources:
        raise AssertionError(f"missing provenance source: {rel}")

negative_dir = tmp_root / "negative-policy"
negative_dir.mkdir(parents=True, exist_ok=True)


def expect_policy_fail(name, mutate):
    bad = json.loads(json.dumps(state))
    mutate(bad)
    bad_path = negative_dir / f"{name}.json"
    bad_path.write_text(json.dumps(bad, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    proc = subprocess.run(
        ["bash", str(repo_root / "scripts" / "policy-check.sh"), "--run-state", str(bad_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode == 0:
        raise AssertionError(f"negative policy fixture unexpectedly passed: {name}\n{proc.stdout}")
    if "integration-backend-consistency" not in proc.stdout:
        raise AssertionError(f"negative policy fixture missed integration check: {name}\n{proc.stdout}")


expect_policy_fail(
    "bad-required-dynamic-unavailable",
    lambda d: d.setdefault("orchestration", {}).update({
        "required": True,
        "selected": True,
        "used": False,
        "fallback_used": False,
        "status": "failed",
        "real_runtime": True,
        "child_completion_proven": False,
    }),
)
expect_policy_fail(
    "bad-dynamic-callable-no-child-completion",
    lambda d: d.setdefault("orchestration", {}).update({
        "required": True,
        "selected": True,
        "used": True,
        "status": "running",
        "real_runtime": True,
        "capability_callable": True,
        "child_completion_proven": False,
    }),
)
expect_policy_fail(
    "bad-agentguard-adapter-only-reported-used",
    lambda d: d.setdefault("security", {}).update({
        "required": True,
        "selected": True,
        "used": True,
        "native_hook": False,
        "adapter_only": True,
        "decision": "allow",
    }),
)
expect_policy_fail(
    "bad-agentguard-block-handler-executed",
    lambda d: d.setdefault("security", {}).update({
        "required": True,
        "selected": True,
        "used": True,
        "native_hook": True,
        "adapter_only": False,
        "decision": "block",
        "handler_executed_after_block": True,
    }),
)
expect_policy_fail(
    "bad-backend-selected-used-mismatch",
    lambda d: d.setdefault("security", {}).update({
        "required": True,
        "selected": False,
        "used": True,
        "native_hook": True,
        "adapter_only": False,
        "decision": "allow",
    }),
)

print(json.dumps({
    "smoke": "plugin-v09-integration-backends",
    "ok": True,
    "verdict": "CONTRACT_SMOKE_ONLY",
    "dynamic_workflows": {
        "capability_callable": True,
        "real_child_completion": "NOT_PROVEN_IN_SOURCE_ONLY_SMOKE",
        "reason": "source-only contract smoke does not spawn real Dynamic child",
    },
    "agentguard": {
        "capability_callable": True,
        "allow_recorded": "adapter_contract_only",
        "block_recorded": "adapter_contract_only",
    },
    "run_dir": str(run_dir),
    "generated_run_state": generated["run_state_path"],
    "policy_verdict": policy["verdict"],
    "final_report": final["final_report_path"],
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-plugin-v09-integration-backends: PASS (source-only contract smoke; no real backend completion claimed)"
