"""Hermes evidence runtime experimental plugin wrapper."""

from __future__ import annotations

from typing import Any

from . import hooks, schemas
from .tools import (
    evidence_active_run_status,
    evidence_doctor,
    evidence_drive_s_run,
    evidence_invoke_worker_dry_run,
    evidence_normalize_worker_result,
    evidence_record_worker_result,
    evidence_run_init,
    evidence_validate_worker_result,
)

HOOK_REGISTRATION_RESULTS: list[dict[str, Any]] = []


def _register_tool(
    ctx: Any,
    name: str,
    func: Any,
    schema: dict[str, Any],
    description: str,
) -> None:
    """Register against known Hermes plugin API shapes without hard-coding one."""
    try:
        ctx.register_tool(
            name=name,
            toolset="evidence_runtime",
            schema=schema,
            handler=func,
            description=description,
            emoji="🧾",
        )
        return
    except TypeError:
        pass

    try:
        ctx.register_tool(name, func, schema=schema, description=description)
        return
    except TypeError:
        pass

    try:
        ctx.register_tool(name, func, schema=schema)
        return
    except TypeError:
        pass

    try:
        ctx.register_tool(name, func, description=description)
        return
    except TypeError:
        pass

    ctx.register_tool(name, func)


def _register_hook(ctx: Any, name: str, func: Any) -> None:
    result = {
        "hook": name,
        "registered": False,
        "reason": "",
    }

    register_hook = getattr(ctx, "register_hook", None)
    if not callable(register_hook):
        result["reason"] = "ctx.register_hook_unavailable"
        HOOK_REGISTRATION_RESULTS.append(result)
        return

    try:
        register_hook(name, func)
        result["registered"] = True
        result["reason"] = "registered"
    except Exception as exc:
        result["reason"] = f"{type(exc).__name__}: {exc}"
    HOOK_REGISTRATION_RESULTS.append(result)


def get_hook_registration_results() -> list[dict[str, Any]]:
    return [dict(item) for item in HOOK_REGISTRATION_RESULTS]


def register(ctx: Any) -> None:
    """Hermes plugin registration entrypoint.

    Tools wrap the existing Bash harness. v0.5.2 hook registration is
    experimental, non-blocking, and best-effort. Memory providers and skill
    replacement are out of scope.
    """
    HOOK_REGISTRATION_RESULTS.clear()
    _register_tool(
        ctx,
        "evidence_doctor",
        evidence_doctor,
        schemas.EVIDENCE_DOCTOR_SCHEMA,
        "Run the hermes-dev-pipeline-kit doctor script in source mode.",
    )
    _register_tool(
        ctx,
        "evidence_active_run_status",
        evidence_active_run_status,
        schemas.EVIDENCE_ACTIVE_RUN_STATUS_SCHEMA,
        "Read project-local active run and latest evidence run status.",
    )
    _register_tool(
        ctx,
        "evidence_run_init",
        evidence_run_init,
        schemas.EVIDENCE_RUN_INIT_SCHEMA,
        "Initialize an evidence run by wrapping scripts/run-init.sh.",
    )
    _register_tool(
        ctx,
        "evidence_drive_s_run",
        evidence_drive_s_run,
        schemas.EVIDENCE_DRIVE_S_RUN_SCHEMA,
        "Drive an S-level evidence run by wrapping scripts/drive-s-run.sh.",
    )
    _register_tool(
        ctx,
        "evidence_validate_worker_result",
        evidence_validate_worker_result,
        schemas.EVIDENCE_VALIDATE_WORKER_RESULT_SCHEMA,
        "Validate a v0.5.3 worker result contract JSON file.",
    )
    _register_tool(
        ctx,
        "evidence_record_worker_result",
        evidence_record_worker_result,
        schemas.EVIDENCE_RECORD_WORKER_RESULT_SCHEMA,
        "Record a validated v0.5.3 worker result into an evidence run.",
    )
    _register_tool(
        ctx,
        "evidence_normalize_worker_result",
        evidence_normalize_worker_result,
        schemas.EVIDENCE_NORMALIZE_WORKER_RESULT_SCHEMA,
        "Normalize caller-supplied worker output into a v0.5.3 worker result contract JSON.",
    )
    _register_tool(
        ctx,
        "evidence_invoke_worker_dry_run",
        evidence_invoke_worker_dry_run,
        schemas.EVIDENCE_INVOKE_WORKER_DRY_RUN_SCHEMA,
        "Invoke or explicitly skip a timeout-bound worker dry-run and write machine-readable evidence.",
    )

    for hook_name, hook_func in (
        ("pre_tool_call", hooks.pre_tool_call),
        ("post_tool_call", hooks.post_tool_call),
        ("on_session_end", hooks.on_session_end),
        ("on_session_finalize", hooks.on_session_finalize),
        ("subagent_stop", hooks.subagent_stop),
    ):
        _register_hook(ctx, hook_name, hook_func)
