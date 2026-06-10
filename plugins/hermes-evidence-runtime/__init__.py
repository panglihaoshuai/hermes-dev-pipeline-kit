"""Hermes evidence runtime experimental plugin wrapper."""

from __future__ import annotations

from typing import Any

from . import schemas
from .tools import (
    evidence_active_run_status,
    evidence_doctor,
    evidence_drive_s_run,
    evidence_run_init,
)


def _register_tool(
    ctx: Any,
    name: str,
    func: Any,
    schema: dict[str, Any],
    description: str,
) -> None:
    """Register against known Hermes plugin API shapes without hard-coding one."""
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


def register(ctx: Any) -> None:
    """Hermes plugin registration entrypoint.

    v0.5.1 intentionally registers tools only. Hooks, memory providers, and
    skill replacement are out of scope for this experimental wrapper.
    """
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
