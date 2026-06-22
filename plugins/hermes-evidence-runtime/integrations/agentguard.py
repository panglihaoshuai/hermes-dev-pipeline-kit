"""Adapter helpers for GoPlusSecurity/agentguard."""

from __future__ import annotations

import pathlib
from typing import Any

from .capability import hermes_plugin_status, read_plugin_yaml


def agentguard_capability(payload: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = payload or {}
    source = str(payload.get("agentguard_path") or "").strip()
    hermes_home = str(payload.get("hermes_home") or "").strip() or None
    plugin_dir = pathlib.Path(source).expanduser().resolve() if source else pathlib.Path()
    meta = read_plugin_yaml(plugin_dir) if source else {}
    status = hermes_plugin_status("agentguard", hermes_home)
    discovered = bool(status["discovered"] or meta)
    return {
        "backend": "agentguard",
        "plugin_name": "agentguard",
        "repo": "GoPlusSecurity/agentguard",
        "discovered": discovered,
        "enabled": bool(status["enabled"]),
        "callable": bool(status["enabled"]),
        "version": str(status.get("version") or meta.get("version") or ""),
        "source_path": str(plugin_dir) if source else "",
        "error": status.get("error", ""),
    }


def security_decision(payload: dict[str, Any]) -> dict[str, Any]:
    decision = str(payload.get("decision") or "unknown").lower()
    if decision not in {"allow", "block", "unknown"}:
        decision = "unknown"
    native_hook = bool(payload.get("native_hook", False))
    adapter_only = bool(payload.get("adapter_only", not native_hook))
    used = bool(payload.get("used", native_hook))
    return {
        "backend": str(payload.get("backend") or "agentguard"),
        "backend_version": str(payload.get("backend_version") or ""),
        "available": bool(payload.get("available", True)),
        "requested": bool(payload.get("requested", True)),
        "required": bool(payload.get("required", False)),
        "selected": bool(payload.get("selected", used)),
        "used": used,
        "fallback_used": bool(payload.get("fallback_used", False)),
        "native_hook": native_hook,
        "adapter_only": adapter_only,
        "handler_executed": bool(payload.get("handler_executed", False)),
        "handler_executed_after_block": bool(payload.get("handler_executed_after_block", False)),
        "decision": decision,
        "reason": str(payload.get("reason") or ""),
        "action_type": str(payload.get("action_type") or ""),
        "tool_name": str(payload.get("tool_name") or ""),
        "evaluated_at": str(payload.get("evaluated_at") or ""),
        "audit_reference": str(payload.get("audit_reference") or ""),
        "provenance": {
            "raw_evidence_only": True,
            "allow_is_not_acceptance": True,
            "block_is_not_policy_check": True,
        },
    }
