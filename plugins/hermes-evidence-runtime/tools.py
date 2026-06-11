"""Hermes tool adapters for hermes-evidence-runtime."""

from __future__ import annotations

import json
from typing import Any, Callable

from . import wrappers


def _payload(args: Any = None, **kwargs: Any) -> dict[str, Any]:
    if args is None:
        data: Any = {}
    elif isinstance(args, str):
        data = json.loads(args) if args.strip() else {}
    elif isinstance(args, dict):
        data = dict(args)
    else:
        raise ValueError("tool input must be a JSON object or JSON string")

    if kwargs:
        data.update(kwargs)
    if not isinstance(data, dict):
        raise ValueError("tool input must decode to a JSON object")
    return data


def _json_tool(fn: Callable[[dict[str, Any]], dict[str, Any]], args: Any = None, **kwargs: Any) -> str:
    try:
        result = fn(_payload(args, **kwargs))
    except Exception as exc:  # Tool calls must remain machine-readable on failure.
        result = {
            "ok": False,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }
    return json.dumps(result, ensure_ascii=False, sort_keys=True)


def evidence_doctor(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_doctor, args, **kwargs)


def evidence_active_run_status(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_active_run_status, args, **kwargs)


def evidence_run_init(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_run_init, args, **kwargs)


def evidence_drive_s_run(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_drive_s_run, args, **kwargs)


def evidence_validate_worker_result(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_validate_worker_result, args, **kwargs)


def evidence_record_worker_result(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_record_worker_result, args, **kwargs)


def evidence_normalize_worker_result(args: Any = None, **kwargs: Any) -> str:
    return _json_tool(wrappers.evidence_normalize_worker_result, args, **kwargs)
