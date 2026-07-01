#!/usr/bin/env bash
# smoke-plugin-v101-authorization-persistence.sh — cross-process durable authorization persistence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_ROOT="$(mktemp -d /tmp/hermes-v101-auth-persistence.XXXXXX)"
PROJECT_ROOT="$WORK_ROOT/project"
RUN_INFO="$WORK_ROOT/run-info.json"
mkdir -p "$PROJECT_ROOT"

python3 - <<'PY' "$REPO_ROOT" "$PROJECT_ROOT" "$RUN_INFO" "$WORK_ROOT/bootstrap-auth.json"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
project_root = pathlib.Path(sys.argv[2])
run_info_path = pathlib.Path(sys.argv[3])
bootstrap_path = pathlib.Path(sys.argv[4])
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"


def load_package():
    spec = importlib.util.spec_from_file_location(
        "hermes_evidence_runtime",
        plugin_dir / "__init__.py",
        submodule_search_locations=[str(plugin_dir)],
    )
    if spec is None or spec.loader is None:
        raise AssertionError("failed to load plugin package")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


load_package()
from hermes_evidence_runtime import authorization, tools  # noqa: E402


def call_tool(fn, payload):
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool returned non-object JSON: {raw}")
    if data.get("ok") is False:
        raise AssertionError(data)
    return data


run = call_tool(tools.evidence_run_init, {
    "project_root": str(project_root),
    "task": "v0.10.1 durable authorization persistence smoke",
    "scale": "S",
    "mode": "auto_run",
    "task_type": "smoke",
    "run_id": "v101-auth-persistence",
})
run_dir = pathlib.Path(run["run_dir"])
goal_hash = authorization.hash_goal("v0.10.1 durable authorization persistence smoke")
auth = authorization.new_authorization(
    run_id=run["run_id"],
    authorization_id="AUTH-v101-primary",
    goal_hash=goal_hash,
    source_message_id="MSG-v101",
    source_session_id="SESSION-v101",
    allowed_paths=[str(project_root)],
    allowed_actions=["edit_repo", "run_local_deterministic_tests"],
    forbidden_actions=[],
    requires_secondary_approval=["modify_live_home", "install_plugin", "uninstall_plugin", "rollback", "reinstall"],
    expires_on=["terminal_verdict"],
)
persisted = call_tool(tools.evidence_persist_authorization, {
    "run_dir": str(run_dir),
    "authorization": auth,
})
bootstrap_path.write_text(json.dumps({"temporary": True}, indent=2) + "\n", encoding="utf-8")
run_info_path.write_text(json.dumps({
    "project_root": str(project_root),
    "run_dir": str(run_dir),
    "run_id": run["run_id"],
    "goal_hash": goal_hash,
    "authorization_id": auth["authorization_id"],
    "authorization_hash": persisted["authorization_hash"],
    "bootstrap_path": str(bootstrap_path),
}, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"process": "A-create", "ok": True, "run_dir": str(run_dir)}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import tools  # noqa: E402


def call_tool(fn, payload):
    data = json.loads(fn(json.dumps(payload)))
    if not isinstance(data, dict):
        raise AssertionError(data)
    return data


run_dir = pathlib.Path(info["run_dir"])
status = call_tool(tools.evidence_authorization_status, {
    "run_dir": str(run_dir),
    "action": "edit_repo",
    "target_path": str(pathlib.Path(info["project_root"]) / "src.txt"),
    "goal_hash": info["goal_hash"],
    "c_class_run": True,
})
assert status["ok"] is True and status["allowed"] is True, status
assert status["authorization_id"] == info["authorization_id"], status
assert status["control_state"]["authorization_status"] == "active", status
print(json.dumps({"process": "B-recover-active", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info_path = pathlib.Path(sys.argv[2])
info = json.loads(info_path.read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import tools  # noqa: E402


def call_tool(fn, payload):
    data = json.loads(fn(json.dumps(payload)))
    if not isinstance(data, dict):
        raise AssertionError(data)
    if data.get("ok") is False:
        raise AssertionError(data)
    return data


pending = call_tool(tools.evidence_prepare_live_approval, {
    "run_dir": info["run_dir"],
    "action": "modify_live_home",
    "target_path": str(pathlib.Path(info["project_root"]) / "live-home"),
    "source_user_message_id": "MSG-approval-request",
})
approval = pending["approval"]
info["approval_id"] = approval["approval_id"]
info["approval_target"] = approval["target_path"]
info_path.write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"process": "A-pending-approval", "ok": True, "approval_id": approval["approval_id"]}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import sys

repo_root = __import__("pathlib").Path(sys.argv[1])
info = json.loads(__import__("pathlib").Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import tools  # noqa: E402


data = json.loads(tools.evidence_authorization_status(json.dumps({
    "run_dir": info["run_dir"],
    "action": "modify_live_home",
    "target_path": info["approval_target"],
    "approval_id": info["approval_id"],
    "goal_hash": info["goal_hash"],
})))
assert data["ok"] is True and data["allowed"] is False and data["reason"] == "live_approval_not_approved", data
print(json.dumps({"process": "B-pending-blocked", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import control_store  # noqa: E402


approved = control_store.approve_approval(
    pathlib.Path(info["run_dir"]),
    info["approval_id"],
    source_user_message_id="MSG-trusted-approval",
)
assert approved["status"] == "approved", approved
print(json.dumps({"process": "trusted-approval-event", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import tools  # noqa: E402


def status(payload):
    return json.loads(tools.evidence_authorization_status(json.dumps(payload)))


allowed = status({
    "run_dir": info["run_dir"],
    "action": "modify_live_home",
    "target_path": info["approval_target"],
    "approval_id": info["approval_id"],
    "goal_hash": info["goal_hash"],
})
assert allowed["ok"] is True and allowed["allowed"] is True, allowed
wrong_action = status({
    "run_dir": info["run_dir"],
    "action": "install_plugin",
    "target_path": info["approval_target"],
    "approval_id": info["approval_id"],
    "goal_hash": info["goal_hash"],
})
assert wrong_action["allowed"] is False and wrong_action["reason"] == "live_approval_action_mismatch", wrong_action
wrong_target = status({
    "run_dir": info["run_dir"],
    "action": "modify_live_home",
    "target_path": str(pathlib.Path(info["project_root"]) / "other-live-home"),
    "approval_id": info["approval_id"],
    "goal_hash": info["goal_hash"],
})
assert wrong_target["allowed"] is False and wrong_target["reason"] == "live_approval_target_mismatch", wrong_target
control_write = status({
    "run_dir": info["run_dir"],
    "action": "edit_repo",
    "target_path": str(pathlib.Path(info["run_dir"]) / "control" / "authorization.json"),
    "goal_hash": info["goal_hash"],
})
assert control_write["allowed"] is False and control_write["reason"] == "runtime_control_artifact_protected", control_write
print(json.dumps({"process": "B-approved-checked", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import tools  # noqa: E402

terminal = json.loads(tools.evidence_terminalize_run(json.dumps({
    "run_dir": info["run_dir"],
    "verdict": "FAIL_TEST",
})))
assert terminal["ok"] is True and terminal["terminal"] is True, terminal
assert terminal["authorization_expired"] is True and terminal["continuation_allowed"] is False, terminal
assert pathlib.Path(terminal["terminal_verdict_path"]).is_file(), terminal
print(json.dumps({"process": "A-terminalize", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO"
import importlib.util
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import authorization, control_store, tools  # noqa: E402


run_dir = pathlib.Path(info["run_dir"])

blocked = json.loads(tools.evidence_authorization_status(json.dumps({
    "run_dir": str(run_dir),
    "action": "edit_repo",
    "target_path": str(pathlib.Path(info["project_root"]) / "after-terminal.txt"),
    "goal_hash": info["goal_hash"],
})))
assert blocked["allowed"] is False and blocked["reason"] == "terminal_verdict_exists", blocked
continued = json.loads(tools.evidence_authorization_status(json.dumps({
    "run_dir": str(run_dir),
    "action": "edit_repo",
    "target_path": str(pathlib.Path(info["project_root"]) / "after-terminal.txt"),
    "goal_hash": info["goal_hash"],
    "context_event": "internal_continuation_after_terminal_report",
})))
assert continued["allowed"] is False and continued["read_only_only"] is True, continued

fresh_root = pathlib.Path(info["project_root"])
fresh_run = pathlib.Path(info["project_root"]) / ".hermes-runs" / "v101-fresh"
fresh_run.mkdir(parents=True)
(fresh_run / "run-manifest.json").write_text(json.dumps({"run_id": "v101-fresh"}) + "\n", encoding="utf-8")
(fresh_run / "classification.json").write_text(json.dumps({"scale": "S"}) + "\n", encoding="utf-8")
(fresh_run / "state.json").write_text(json.dumps({"run_id": "v101-fresh", "current_state": "CLASSIFIED"}) + "\n", encoding="utf-8")
control_store.initialize_control_store(fresh_run)
fresh = authorization.new_authorization(
    run_id="v101-fresh",
    authorization_id="AUTH-v101-fresh",
    goal_hash=info["goal_hash"],
    source_message_id="MSG-fresh",
    source_session_id="SESSION-v101",
    allowed_paths=[str(fresh_root)],
    allowed_actions=["edit_repo"],
    forbidden_actions=[],
    requires_secondary_approval=["modify_live_home"],
    expires_on=["terminal_verdict"],
)
persisted = control_store.persist_authorization(fresh_run, fresh)
assert persisted["authorization_id"] != info["authorization_id"], persisted
old_approval = json.loads(tools.evidence_authorization_status(json.dumps({
    "run_dir": str(fresh_run),
    "action": "modify_live_home",
    "target_path": info["approval_target"],
    "approval_id": info["approval_id"],
    "goal_hash": info["goal_hash"],
})))
assert old_approval["allowed"] is False, old_approval
print(json.dumps({"process": "B-terminal-recovery", "ok": True}, sort_keys=True))
PY

python3 - <<'PY' "$REPO_ROOT" "$RUN_INFO" "$WORK_ROOT"
import importlib.util
import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import time

repo_root = pathlib.Path(sys.argv[1])
info = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
work_root = pathlib.Path(sys.argv[3])
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"
spec = importlib.util.spec_from_file_location("hermes_evidence_runtime", plugin_dir / "__init__.py", submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import control_store, tools  # noqa: E402


def status(run_dir, **extra):
    payload = {
        "run_dir": str(run_dir),
        "action": "edit_repo",
        "target_path": str(pathlib.Path(info["project_root"]) / "x.txt"),
        "goal_hash": info["goal_hash"],
    }
    payload.update(extra)
    return json.loads(tools.evidence_authorization_status(json.dumps(payload)))


def copy_case(name):
    target = work_root / name / pathlib.Path(info["run_dir"]).name
    target.parent.mkdir(parents=True)
    shutil.copytree(pathlib.Path(info["run_dir"]), target)
    return target


corrupt = copy_case("case-corrupt-json")
(corrupt / "control" / "authorization.json").write_text("{broken", encoding="utf-8")
assert status(corrupt)["reason"] == "CONTROL_ARTIFACT_INVALID", status(corrupt)

hash_mismatch = copy_case("case-hash-mismatch")
auth_path = hash_mismatch / "control" / "authorization.json"
auth = json.loads(auth_path.read_text(encoding="utf-8"))
auth["goal_hash"] = "sha256:" + "c" * 64
auth_path.write_text(json.dumps(auth, indent=2) + "\n", encoding="utf-8")
assert status(hash_mismatch)["reason"] == "CONTROL_ARTIFACT_INVALID", status(hash_mismatch)

terminal_mismatch = copy_case("case-terminal-mismatch")
term_path = terminal_mismatch / "control" / "terminal-verdict.json"
term = json.loads(term_path.read_text(encoding="utf-8"))
term["authorization_id"] = "AUTH-wrong"
term_path.write_text(json.dumps(term, indent=2) + "\n", encoding="utf-8")
assert status(terminal_mismatch)["reason"] == "CONTROL_ARTIFACT_INVALID", status(terminal_mismatch)

terminal_hash_mismatch = copy_case("case-terminal-hash-mismatch")
term_path = terminal_hash_mismatch / "control" / "terminal-verdict.json"
term = json.loads(term_path.read_text(encoding="utf-8"))
term["authorization_hash"] = "sha256:" + "d" * 64
term_path.write_text(json.dumps(term, indent=2) + "\n", encoding="utf-8")
assert status(terminal_hash_mismatch)["reason"] == "CONTROL_ARTIFACT_INVALID", status(terminal_hash_mismatch)

approval_mismatch = copy_case("case-approval-mismatch")
term = approval_mismatch / "control" / "terminal-verdict.json"
term.unlink()
approval_path = approval_mismatch / "control" / "approvals" / f"{info['approval_id']}.json"
approval = json.loads(approval_path.read_text(encoding="utf-8"))
approval["authorization_hash"] = "bad"
approval_path.write_text(json.dumps(approval, indent=2) + "\n", encoding="utf-8")
bad_approval = status(approval_mismatch, action="modify_live_home", target_path=info["approval_target"], approval_id=info["approval_id"])
assert bad_approval["reason"] == "CONTROL_ARTIFACT_INVALID", bad_approval

missing_state = copy_case("case-missing-state-terminal")
(missing_state / "control" / "control-state.json").unlink()
assert status(missing_state)["reason"] == "terminal_verdict_exists", status(missing_state)

partial_temp = copy_case("case-partial-temp")
(partial_temp / "control" / "authorization.json.tmp").write_text("{partial", encoding="utf-8")
assert status(partial_temp)["reason"] == "terminal_verdict_exists", status(partial_temp)

mode_dir = stat.S_IMODE((pathlib.Path(info["run_dir"]) / "control").stat().st_mode)
mode_auth = stat.S_IMODE((pathlib.Path(info["run_dir"]) / "control" / "authorization.json").stat().st_mode)
assert mode_dir & 0o077 == 0, oct(mode_dir)
assert mode_auth & 0o077 == 0, oct(mode_auth)

concurrent = copy_case("case-concurrent-events")
code = f"""
import importlib.util, pathlib, sys
plugin_dir = pathlib.Path({str(plugin_dir)!r})
spec = importlib.util.spec_from_file_location('hermes_evidence_runtime', plugin_dir / '__init__.py', submodule_search_locations=[str(plugin_dir)])
pkg = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pkg
spec.loader.exec_module(pkg)
from hermes_evidence_runtime import control_store
run_dir = pathlib.Path({str(concurrent)!r})
for i in range(10):
    control_store.append_control_event(run_dir, {{
        'event_type': 'concurrent_probe',
        'authorization_id': {info['authorization_id']!r},
        'previous_state': 'probe',
        'next_state': 'probe',
        'artifact_reference': 'control/events.jsonl',
    }})
"""
procs = [subprocess.Popen([sys.executable, "-c", code]) for _ in range(6)]
for proc in procs:
    assert proc.wait(timeout=20) == 0, proc.returncode
events = (concurrent / "control" / "events.jsonl").read_text(encoding="utf-8").splitlines()
assert sum('"concurrent_probe"' in line for line in events) == 60, len(events)

bootstrap = pathlib.Path(info["bootstrap_path"])
bootstrap.unlink()
assert status(pathlib.Path(info["run_dir"]))["reason"] == "terminal_verdict_exists", "bootstrap cleanup changed durable state"

print(json.dumps({"process": "integrity-cases", "ok": True}, sort_keys=True))
PY

echo "smoke-plugin-v101-authorization-persistence: PASS"
