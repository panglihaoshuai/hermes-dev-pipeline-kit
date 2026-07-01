#!/usr/bin/env bash
# smoke-plugin-v10-authorization-lifecycle.sh — deterministic authorization lifecycle and terminal verdict gates.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

python3 - <<'PY' "$REPO_ROOT"
import importlib.util
import json
import pathlib
import sys
import tempfile

repo_root = pathlib.Path(sys.argv[1])
plugin_dir = repo_root / "plugins/hermes-evidence-runtime"


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"missing module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


authorization = load_module("authorization", plugin_dir / "authorization.py")

tools_spec = importlib.util.spec_from_file_location(
    "hermes_evidence_runtime",
    plugin_dir / "__init__.py",
    submodule_search_locations=[str(plugin_dir)],
)
if tools_spec is None or tools_spec.loader is None:
    raise AssertionError("failed to load plugin package")
pkg = importlib.util.module_from_spec(tools_spec)
sys.modules[tools_spec.name] = pkg
tools_spec.loader.exec_module(pkg)
tools = __import__("hermes_evidence_runtime.tools", fromlist=["tools"])


tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="hermes-v10-authorization."))
project = tmp_root / "project"
project.mkdir()
outside = tmp_root / "outside"
outside.mkdir()
goal_hash = "sha256:" + "a" * 64
new_goal_hash = "sha256:" + "b" * 64


def call_tool(fn, payload: dict) -> dict:
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool returned non-object JSON: {raw}")
    return data


def require(label: str, condition: bool, detail: object = None) -> None:
    if not condition:
        raise AssertionError(f"{label} failed: {detail!r}")


base_auth = authorization.new_authorization(
    authorization_id="AUTH-v10-smoke",
    goal_hash=goal_hash,
    source_message_id="MSG-1",
    source_session_id="SESSION-1",
    allowed_paths=[str(project)],
    allowed_actions=["read_repo", "edit_repo", "run_local_deterministic_tests"],
    forbidden_actions=["modify_live_home", "install_plugin", "rollback_live_state"],
    requires_secondary_approval=["modify_live_home", "install_plugin", "uninstall_plugin", "rollback", "reinstall"],
    expires_on=[
        "terminal_verdict",
        "blocked",
        "scope_change",
        "session_recovery_without_fresh_user_message",
        "internal_continuation_after_terminal_report",
    ],
)

# 1. no umbrella authorization -> block C-class mutation
result = authorization.check_mutation(None, "edit_repo", str(project / "a.txt"), goal_hash=goal_hash, c_class_run=True)
require("no umbrella authorization blocks mutation", result["allowed"] is False and result["reason"] == "missing_authorization", result)

# 2. active authorization + allowed path/action -> allow
result = authorization.check_mutation(base_auth, "edit_repo", str(project / "a.txt"), goal_hash=goal_hash, c_class_run=True)
require("active auth allowed mutation", result["allowed"] is True, result)

# 3. allowed path outside -> block
result = authorization.check_mutation(base_auth, "edit_repo", str(outside / "a.txt"), goal_hash=goal_hash, c_class_run=True)
require("outside path blocked", result["allowed"] is False and result["reason"] == "path_not_allowed", result)

# 4. forbidden action -> block
result = authorization.check_mutation(base_auth, "install_plugin", str(project), goal_hash=goal_hash, c_class_run=True)
require("forbidden action blocked", result["allowed"] is False and result["reason"] == "forbidden_action", result)

# 5. goal hash mismatch -> block
result = authorization.check_mutation(base_auth, "edit_repo", str(project / "a.txt"), goal_hash=new_goal_hash, c_class_run=True)
require("goal hash mismatch blocked", result["allowed"] is False and result["reason"] == "goal_hash_mismatch", result)

# 6. live mutation without approval -> block
result = authorization.check_mutation(base_auth, "modify_live_home", str(project), goal_hash=goal_hash, c_class_run=True)
require("live mutation without approval blocked", result["allowed"] is False and result["reason"] == "forbidden_action", result)

live_auth = dict(base_auth)
live_auth["forbidden_actions"] = []

# 7. pending approval -> block
pending_result = authorization.prepare_live_approval(live_auth, "modify_live_home", str(project), source_user_message_id="MSG-2")
pending = pending_result["approval"]
result = authorization.check_mutation(live_auth, "modify_live_home", str(project), goal_hash=goal_hash, live_approval=pending)
require("pending approval blocked", result["allowed"] is False and result["reason"] == "live_approval_not_approved", result)

# 8. approved but target different -> block
approved = dict(pending, status="approved", approved_at="2026-06-22T00:00:00Z")
result = authorization.check_mutation(live_auth, "modify_live_home", str(project / "other"), goal_hash=goal_hash, live_approval=approved)
require("approved wrong target blocked", result["allowed"] is False and result["reason"] == "live_approval_target_mismatch", result)

# 9. approved but action different -> block
result = authorization.check_mutation(live_auth, "install_plugin", str(project), goal_hash=goal_hash, live_approval=approved)
require("approved wrong action blocked", result["allowed"] is False and result["reason"] == "live_approval_action_mismatch", result)

# 10. stale authorization approval -> block
stale = dict(approved, authorization_id="AUTH-old")
result = authorization.check_mutation(live_auth, "modify_live_home", str(project), goal_hash=goal_hash, live_approval=stale)
require("stale approval blocked", result["allowed"] is False and result["reason"] == "live_approval_authorization_mismatch", result)

# 11. agent self-approval -> block
self_approved = authorization.prepare_live_approval(live_auth, "modify_live_home", str(project), source_user_message_id="MSG-2", status="approved")
require("agent self approval rejected", self_approved["ok"] is False and self_approved["reason"] == "agent_cannot_self_approve", self_approved)

# 12-15. terminal verdicts expire or complete authorization
for verdict, next_state in [
    ("FAIL_CLEAN_CLONE", "failed_reauth_required"),
    ("PARTIAL_LIVE_INSTALL_BACKEND_MISSING", "paused_reauth_required"),
    ("BLOCKED", "blocked_reauth_required"),
    ("PASS_AUTHORIZATION_LIFECYCLE", "completed"),
]:
    terminal = authorization.terminalize_run(live_auth, run_id="RUN-1", verdict=verdict)
    require(f"{verdict} terminal", terminal["terminal"] is True, terminal)
    require(f"{verdict} next_state", terminal["next_state"] == next_state, terminal)
    require(f"{verdict} continuation disabled", terminal["continuation_allowed"] is False, terminal)
    require(f"{verdict} auth inactive", terminal["authorization"]["status"] in {"expired", "completed"}, terminal)
    require(f"{verdict} no next goal execution", terminal["next_goal_executable"] is False, terminal)

failed_terminal = authorization.terminalize_run(live_auth, run_id="RUN-2", verdict="FAIL_TEST")
expired_auth = failed_terminal["authorization"]

# 16-17. internal continuation/session recovery after terminal -> read-only
for event in ["internal_continuation_after_terminal_report", "session_recovery_without_fresh_user_message"]:
    result = authorization.check_mutation(expired_auth, "edit_repo", str(project / "a.txt"), goal_hash=goal_hash, context_event=event)
    require(f"{event} read-only", result["allowed"] is False and result["read_only_only"] is True, result)

# 18. fresh renewal -> new authorization id
renewed = authorization.renew_authorization(expired_auth, authorization_id="AUTH-v10-renewed", goal_hash=goal_hash, source_message_id="MSG-3")
require("fresh renewal id", renewed["authorization_id"] != expired_auth["authorization_id"], renewed)
require("fresh renewal active", renewed["status"] == "active", renewed)

# 19. non-terminal repair update may continue within existing scope
repair = authorization.stage_update(live_auth, run_id="RUN-3", stage_status="repairing")
require("repair non-terminal", repair["terminal"] is False and repair["continuation_allowed"] is True, repair)
result = authorization.check_mutation(live_auth, "edit_repo", str(project / "repair.txt"), goal_hash=goal_hash)
require("repair mutation in scope allowed", result["allowed"] is True, result)

# 20. NOT_RUN canary cannot be marked completed
terminal = authorization.terminalize_run(live_auth, run_id="RUN-4", verdict="PASS_CANARY", canary_status="NOT_RUN")
require("not-run canary cannot complete", terminal["ok"] is False and terminal["reason"] == "canary_not_run", terminal)

# 21. external provider SKIP must not be PASS
terminal = authorization.terminalize_run(live_auth, run_id="RUN-5", verdict="SKIP_EXTERNAL_PROVIDER_UNAVAILABLE")
require("external skip not pass", terminal["ok"] is False and terminal["reason"] == "skip_is_not_terminal_pass", terminal)

# Tool wrappers are machine-readable and preserve blocking behavior.
tool_pending = call_tool(tools.evidence_prepare_live_approval, {
    "authorization": live_auth,
    "action": "modify_live_home",
    "target_path": str(project),
    "source_user_message_id": "MSG-2",
})
require("tool pending approval", tool_pending["ok"] is True and tool_pending["approval"]["status"] == "pending", tool_pending)

tool_status = call_tool(tools.evidence_authorization_status, {
    "authorization": live_auth,
    "action": "edit_repo",
    "target_path": str(project / "tool.txt"),
    "goal_hash": goal_hash,
})
require("tool status allow", tool_status["ok"] is True and tool_status["allowed"] is True, tool_status)

tool_terminal = call_tool(tools.evidence_terminalize_run, {
    "authorization": live_auth,
    "run_id": "RUN-tool",
    "verdict": "FAIL_TOOL",
})
require("tool terminalize", tool_terminal["ok"] is True and tool_terminal["continuation_allowed"] is False, tool_terminal)

print(json.dumps({
    "ok": True,
    "smoke": "plugin-v10-authorization-lifecycle",
    "cases": 24,
    "verdict": "PASS_AUTHORIZATION_LIFECYCLE_WITH_EXTERNAL_RUNTIME_BOUNDARY",
}, sort_keys=True))
PY
