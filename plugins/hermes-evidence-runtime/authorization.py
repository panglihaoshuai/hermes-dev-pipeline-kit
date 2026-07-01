"""Run authorization and terminal verdict helpers for Dev Pipeline tools.

This module is deliberately local and deterministic. It does not approve user
actions by itself and does not claim to govern Codex UI internals.
"""

from __future__ import annotations

import hashlib
import pathlib
import time
import uuid
from typing import Any

LIVE_ACTIONS = {
    "modify_live_home",
    "install_plugin",
    "uninstall_plugin",
    "rollback",
    "reinstall",
}

CONTINUATION_EVENTS = {
    "internal_continuation_after_terminal_report",
    "session_recovery_without_fresh_user_message",
}


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def hash_goal(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def new_authorization(
    *,
    run_id: str | None = None,
    authorization_id: str | None = None,
    goal_hash: str,
    source_message_id: str,
    source_session_id: str,
    allowed_paths: list[str],
    allowed_actions: list[str],
    forbidden_actions: list[str],
    requires_secondary_approval: list[str] | None = None,
    expires_on: list[str] | None = None,
    source_attachment_hash: str | None = None,
) -> dict[str, Any]:
    if not goal_hash:
        raise ValueError("goal_hash is required")
    if not source_message_id or not source_session_id:
        raise ValueError("source message/session are required")
    created_at = now_utc()
    data = {
        "authorization_version": "1.0",
        "artifact_version": "1.0",
        "run_id": run_id or "",
        "authorization_id": authorization_id or f"AUTH-{uuid.uuid4()}",
        "goal_hash": goal_hash,
        "source_message_id": source_message_id,
        "source_session_id": source_session_id,
        "source_attachment_hash": source_attachment_hash,
        "created_at": created_at,
        "updated_at": created_at,
        "status": "active",
        "allowed_paths": [str(pathlib.Path(item).expanduser().resolve()) for item in allowed_paths],
        "allowed_actions": list(allowed_actions),
        "forbidden_actions": list(forbidden_actions),
        "requires_secondary_approval": list(requires_secondary_approval or []),
        "expires_on": list(expires_on or []),
        "expired_at": None,
        "expiration_reason": None,
        "written_by": "hermes-evidence-runtime",
    }
    return data


def pending_authorization_request(
    *,
    goal_hash: str,
    source_message_id: str = "unavailable",
    source_session_id: str = "unavailable",
) -> dict[str, Any]:
    created_at = now_utc()
    return {
        "authorization_version": "1.0",
        "artifact_version": "1.0",
        "run_id": "",
        "authorization_id": f"PENDING-{uuid.uuid4()}",
        "goal_hash": goal_hash,
        "source_message_id": source_message_id,
        "source_session_id": source_session_id,
        "created_at": created_at,
        "updated_at": created_at,
        "status": "pending",
        "allowed_paths": [],
        "allowed_actions": [],
        "forbidden_actions": [],
        "requires_secondary_approval": [],
        "expires_on": [],
        "expired_at": None,
        "expiration_reason": "host_user_source_not_verified",
        "mutation_allowed": False,
        "written_by": "hermes-evidence-runtime",
    }


def _is_under(target: str, roots: list[str]) -> bool:
    target_path = pathlib.Path(target).expanduser().resolve()
    for root in roots:
        root_path = pathlib.Path(root).expanduser().resolve()
        try:
            target_path.relative_to(root_path)
            return True
        except ValueError:
            continue
    return False


def _block(reason: str, *, read_only_only: bool = False, detail: str = "") -> dict[str, Any]:
    return {
        "ok": True,
        "allowed": False,
        "reason": reason,
        "read_only_only": read_only_only,
        "detail": detail,
    }


def _allow() -> dict[str, Any]:
    return {
        "ok": True,
        "allowed": True,
        "reason": "allowed",
        "read_only_only": False,
    }


def prepare_live_approval(
    authorization: dict[str, Any],
    action: str,
    target_path: str,
    *,
    source_user_message_id: str,
    status: str = "pending",
) -> dict[str, Any]:
    if status == "approved":
        return {
            "ok": False,
            "reason": "agent_cannot_self_approve",
            "approval": None,
        }
    return {
        "ok": True,
        "approval": {
            "approval_id": f"APPROVAL-{uuid.uuid4()}",
            "authorization_id": authorization.get("authorization_id", ""),
            "action": action,
            "target_path": str(pathlib.Path(target_path).expanduser().resolve()),
            "requested_at": now_utc(),
            "approved_at": None,
            "status": "pending",
            "source_user_message_id": source_user_message_id,
            "expires_on_terminal_verdict": True,
        },
    }


def _validate_live_approval(
    authorization: dict[str, Any],
    action: str,
    target_path: str,
    live_approval: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if action not in LIVE_ACTIONS and action not in set(authorization.get("requires_secondary_approval") or []):
        return None
    if not live_approval:
        return _block("live_approval_missing")
    if live_approval.get("authorization_id") != authorization.get("authorization_id"):
        return _block("live_approval_authorization_mismatch")
    if live_approval.get("action") != action:
        return _block("live_approval_action_mismatch")
    expected_target = str(pathlib.Path(target_path).expanduser().resolve())
    observed_target = str(pathlib.Path(str(live_approval.get("target_path", ""))).expanduser().resolve())
    if observed_target != expected_target:
        return _block("live_approval_target_mismatch")
    if live_approval.get("status") != "approved" or not live_approval.get("approved_at"):
        return _block("live_approval_not_approved")
    return None


def check_mutation(
    authorization: dict[str, Any] | None,
    action: str,
    target_path: str,
    *,
    goal_hash: str | None = None,
    live_approval: dict[str, Any] | None = None,
    context_event: str | None = None,
    c_class_run: bool = False,
) -> dict[str, Any]:
    if not authorization:
        return _block("missing_authorization")
    if context_event in CONTINUATION_EVENTS:
        return _block("terminal_continuation_read_only", read_only_only=True)
    if authorization.get("status") not in {"active"}:
        return _block("authorization_not_active", read_only_only=True)
    if goal_hash and authorization.get("goal_hash") != goal_hash:
        return _block("goal_hash_mismatch")
    if c_class_run and not authorization.get("authorization_id"):
        return _block("missing_authorization")
    if action in set(authorization.get("forbidden_actions") or []):
        return _block("forbidden_action")
    if action not in set(authorization.get("allowed_actions") or []) and action not in LIVE_ACTIONS:
        return _block("action_not_allowed")
    approval_block = _validate_live_approval(authorization, action, target_path, live_approval)
    if approval_block:
        return approval_block
    if action not in LIVE_ACTIONS and not _is_under(target_path, list(authorization.get("allowed_paths") or [])):
        return _block("path_not_allowed")
    if action in LIVE_ACTIONS and not live_approval:
        return _block("live_approval_missing")
    return _allow()


def _terminal_next_state(verdict: str) -> tuple[str, str]:
    if verdict.startswith("PASS_"):
        return "completed", "completed"
    if verdict.startswith("FAIL_"):
        return "failed_reauth_required", "expired"
    if verdict.startswith("PARTIAL_"):
        return "paused_reauth_required", "expired"
    if verdict == "BLOCKED":
        return "blocked_reauth_required", "expired"
    return "paused_reauth_required", "expired"


def terminalize_run(
    authorization: dict[str, Any],
    *,
    run_id: str,
    verdict: str,
    canary_status: str | None = None,
) -> dict[str, Any]:
    if verdict == "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE":
        return {
            "ok": False,
            "reason": "skip_is_not_terminal_pass",
            "terminal": False,
            "continuation_allowed": False,
        }
    if verdict.startswith("PASS") and canary_status == "NOT_RUN":
        return {
            "ok": False,
            "reason": "canary_not_run",
            "terminal": False,
            "continuation_allowed": False,
        }
    next_state, auth_status = _terminal_next_state(verdict)
    updated = dict(authorization)
    updated["status"] = auth_status
    updated["expired_at"] = now_utc()
    updated["expiration_reason"] = "terminal_verdict"
    return {
        "ok": True,
        "run_id": run_id,
        "verdict": verdict,
        "terminal": True,
        "emitted_at": now_utc(),
        "next_state": next_state,
        "authorization_expired": True,
        "continuation_allowed": False,
        "next_goal_executable": False,
        "authorization": updated,
        "runtime_boundary": {
            "codex_ui_internal_continuation_controlled": False,
            "external_processes_bypassing_hermes_controlled": False,
        },
    }


def stage_update(authorization: dict[str, Any], *, run_id: str, stage_status: str) -> dict[str, Any]:
    return {
        "ok": True,
        "run_id": run_id,
        "terminal": False,
        "stage_status": stage_status,
        "continuation_allowed": authorization.get("status") == "active",
        "authorization_expired": False,
    }


def renew_authorization(
    authorization: dict[str, Any],
    *,
    authorization_id: str,
    goal_hash: str,
    source_message_id: str,
) -> dict[str, Any]:
    renewed = dict(authorization)
    renewed.update({
        "authorization_id": authorization_id,
        "goal_hash": goal_hash,
        "source_message_id": source_message_id,
        "created_at": now_utc(),
        "status": "active",
        "expired_at": None,
        "expiration_reason": None,
    })
    return renewed
