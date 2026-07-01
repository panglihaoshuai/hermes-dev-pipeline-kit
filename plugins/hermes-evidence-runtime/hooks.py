"""Log-only Hermes hook payload capture for hermes-evidence-runtime.

v0.7 hooks are observation-only. They must not block, mutate, approve, reject,
or synthesize tool results. Any handler failure must fail open so normal Hermes
runtime behavior continues unchanged.
"""

from __future__ import annotations

import json
import os
import pathlib
import time
import uuid
from datetime import datetime, timezone
from typing import Any

from .redaction import hash_text, safe_serialize


SCHEMA_VERSION = "0.7.0"
PLUGIN_VERSION = "0.9.0-integration-spike"
LOG_FILE_NAME = "hook-events.jsonl"
SUMMARY_FILE_NAME = "hook-summary.json"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _payload_from_args(args: tuple[Any, ...], kwargs: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = dict(kwargs)
    if args:
        payload["_args"] = list(args)
    return payload


def _capture_mode() -> str:
    raw = os.environ.get("HERMES_EVIDENCE_HOOK_CAPTURE_MODE", "simulated_test")
    if raw == "real_runtime":
        return "real_runtime"
    return "simulated_test"


def _session_hash(payload: dict[str, Any]) -> str | None:
    for key in (
        "session_id",
        "parent_session_id",
        "child_session_id",
        "session_key",
    ):
        value = payload.get(key)
        if value:
            return hash_text(value)
    return None


def _tool_call_hash(payload: dict[str, Any]) -> str | None:
    for key in ("tool_call_id", "call_id", "api_request_id"):
        value = payload.get(key)
        if value:
            return hash_text(value)
    return None


def _tool_name(payload: dict[str, Any]) -> str | None:
    value = payload.get("tool_name")
    return str(value) if value else None


def _build_event(hook_name: str, args: tuple[Any, ...], kwargs: dict[str, Any]) -> dict[str, Any]:
    payload = _payload_from_args(args, kwargs)
    redacted_payload, warnings = safe_serialize(payload)
    return {
        "schema_version": SCHEMA_VERSION,
        "plugin_version": PLUGIN_VERSION,
        "event_id": str(uuid.uuid4()),
        "hook_name": hook_name,
        "captured_at": _now(),
        "capture_mode": _capture_mode(),
        "session": {
            "session_id_hash": _session_hash(payload),
            "run_id": os.environ.get("HERMES_EVIDENCE_RUN_ID") or None,
        },
        "tool": {
            "name": _tool_name(payload),
            "call_id_hash": _tool_call_hash(payload),
        },
        "payload": {
            "keys_observed": sorted(str(key) for key in payload.keys()),
            "redacted": redacted_payload,
        },
        "provenance": {
            "captured_by": "hermes-evidence-runtime",
            "source": "Hermes hook callback",
            "log_only": True,
        },
        "warnings": warnings,
    }


def _log_dir() -> pathlib.Path | None:
    raw = os.environ.get("HERMES_EVIDENCE_HOOK_LOG_DIR")
    if not raw:
        return None
    return pathlib.Path(raw).expanduser().resolve()


def _append_event(log_dir: pathlib.Path, event: dict[str, Any]) -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    with (log_dir / LOG_FILE_NAME).open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")


def _write_summary(log_dir: pathlib.Path, event: dict[str, Any]) -> None:
    summary_path = log_dir / SUMMARY_FILE_NAME
    try:
        if summary_path.is_file():
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            if not isinstance(summary, dict):
                summary = {}
        else:
            summary = {}
    except Exception:
        summary = {}

    hooks = summary.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
    hook_name = str(event.get("hook_name", "unknown"))
    hooks[hook_name] = int(hooks.get(hook_name, 0) or 0) + 1

    modes = summary.get("capture_modes")
    if not isinstance(modes, dict):
        modes = {}
    mode = str(event.get("capture_mode", "unknown"))
    modes[mode] = int(modes.get(mode, 0) or 0) + 1

    summary.update({
        "schema_version": SCHEMA_VERSION,
        "plugin_version": PLUGIN_VERSION,
        "updated_at": _now(),
        "event_count": int(summary.get("event_count", 0) or 0) + 1,
        "hooks": hooks,
        "capture_modes": modes,
    })
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _record_hook(hook_name: str, args: tuple[Any, ...], kwargs: dict[str, Any]) -> None:
    log_dir = _log_dir()
    if log_dir is None:
        return None

    try:
        event = _build_event(hook_name, args, kwargs)
    except Exception as exc:
        event = {
            "schema_version": SCHEMA_VERSION,
            "plugin_version": PLUGIN_VERSION,
            "event_id": str(uuid.uuid4()),
            "hook_name": hook_name,
            "captured_at": _now(),
            "capture_mode": _capture_mode(),
            "session": {"session_id_hash": None, "run_id": None},
            "tool": {"name": None, "call_id_hash": None},
            "payload": {
                "keys_observed": [],
                "redacted": {
                    "serialization_error": True,
                    "error_type": type(exc).__name__,
                },
            },
            "provenance": {
                "captured_by": "hermes-evidence-runtime",
                "source": "Hermes hook callback",
                "log_only": True,
            },
            "warnings": ["serialization_error"],
        }

    try:
        _append_event(log_dir, event)
        _write_summary(log_dir, event)
    except Exception:
        # Observation-only hook capture must never break the Hermes session.
        return None
    return None


def pre_tool_call(*args: Any, **kwargs: Any) -> None:
    _record_hook("pre_tool_call", args, kwargs)
    return None


def post_tool_call(*args: Any, **kwargs: Any) -> None:
    _record_hook("post_tool_call", args, kwargs)
    return None


def on_session_start(*args: Any, **kwargs: Any) -> None:
    _record_hook("on_session_start", args, kwargs)
    return None


def on_session_end(*args: Any, **kwargs: Any) -> None:
    _record_hook("on_session_end", args, kwargs)
    return None


def on_session_finalize(*args: Any, **kwargs: Any) -> None:
    _record_hook("on_session_finalize", args, kwargs)
    return None


def subagent_stop(*args: Any, **kwargs: Any) -> None:
    _record_hook("subagent_stop", args, kwargs)
    return None
