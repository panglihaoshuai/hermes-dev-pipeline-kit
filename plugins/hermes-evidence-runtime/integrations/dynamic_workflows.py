"""Adapter helpers for lingjiuu/hermes-dynamic-workflows."""

from __future__ import annotations

import pathlib
from typing import Any

from .capability import hermes_plugin_status, importable, read_plugin_yaml


def dynamic_workflows_capability(payload: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = payload or {}
    source = str(payload.get("dynamic_workflows_path") or "").strip()
    hermes_home = str(payload.get("hermes_home") or "").strip() or None
    plugin_dir = pathlib.Path(source).expanduser().resolve() if source else pathlib.Path()
    meta = read_plugin_yaml(plugin_dir) if source else {}
    status = hermes_plugin_status("dynamic-workflows", hermes_home)
    module_importable = importable("hermes_dynamic_workflows", source or None)
    return {
        "backend": "hermes_dynamic_workflows",
        "plugin_name": "dynamic-workflows",
        "repo": "lingjiuu/hermes-dynamic-workflows",
        "discovered": bool(status["discovered"] or meta or module_importable),
        "enabled": bool(status["enabled"]),
        "callable": bool(status["callable"] and module_importable),
        "version": str(status.get("version") or meta.get("version") or ""),
        "module_importable": module_importable,
        "source_path": str(plugin_dir) if source else "",
        "error": status.get("error", ""),
    }


def orchestration_result(payload: dict[str, Any]) -> dict[str, Any]:
    record = dict(payload.get("record") or {})
    result = record.get("result")
    claims = result if isinstance(result, dict) else {"raw_result": result}
    status = str(record.get("status") or "unknown")
    if status not in {"queued", "running", "completed", "failed", "stopped", "unknown"}:
        status = "unknown"
    child_completion = bool(payload.get("child_completion_proven", status == "completed"))
    used = bool(payload.get("used", status == "completed" and child_completion))
    return {
        "backend": "hermes_dynamic_workflows",
        "backend_version": str(payload.get("backend_version") or ""),
        "available": bool(payload.get("available", status == "completed")),
        "requested": bool(payload.get("requested", True)),
        "required": bool(payload.get("required", False)),
        "selected": bool(payload.get("selected", used)),
        "used": used,
        "fallback_used": bool(payload.get("fallback_used", False)),
        "capability_callable": bool(payload.get("capability_callable", payload.get("available", status == "completed"))),
        "child_completion_proven": child_completion,
        "run_id": str(record.get("runId") or payload.get("run_id") or ""),
        "status": status,
        "capture_mode": "real_runtime",
        "work_order_id": str(payload.get("work_order_id") or "WO-1"),
        "structured_result_path": str(payload.get("structured_result_path") or record.get("outputFile") or ""),
        "journal_path": str(record.get("journalFile") or payload.get("journal_path") or ""),
        "transcript_paths": list(record.get("transcriptFiles") or payload.get("transcript_paths") or []),
        "workspace_path": str(record.get("cwd") or payload.get("workspace_path") or ""),
        "started_at": str(record.get("startedAt") or ""),
        "ended_at": str(record.get("finishedAt") or ""),
        "error": record.get("error") if record.get("error") else payload.get("error"),
        "claims": claims if isinstance(claims, dict) else {"raw_result": claims},
        "provenance": {
            "source": "lingjiuu/hermes-dynamic-workflows",
            "raw_evidence_only": True,
            "not_acceptance": True,
        },
    }
