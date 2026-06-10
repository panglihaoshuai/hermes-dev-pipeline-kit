"""Prototype non-blocking Hermes hooks for the evidence runtime plugin.

These hooks are observational only. They never enforce policy, never block a
tool call, and only write local JSONL when HERMES_EVIDENCE_HOOK_LOG_DIR is set.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
from datetime import datetime, timezone
from typing import Any


SENSITIVE_KEY_RE = re.compile(
    r"API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE_KEY|OPENAI|ANTHROPIC|GH_TOKEN|"
    r"authorization|cookie|session|bearer",
    re.IGNORECASE,
)
SENSITIVE_VALUE_RE = re.compile(
    r"bearer\s+[a-z0-9._-]+|sk-[a-z0-9._-]+|gh[pousr]_[a-z0-9_]+|"
    r"xox[baprs]-[a-z0-9-]+",
    re.IGNORECASE,
)
MAX_STRING = 300
MAX_ITEMS = 40
MAX_DEPTH = 4


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _is_sensitive_key(key: Any) -> bool:
    return isinstance(key, str) and bool(SENSITIVE_KEY_RE.search(key))


def _is_sensitive_value(value: Any) -> bool:
    return isinstance(value, str) and bool(SENSITIVE_VALUE_RE.search(value))


def _truncate(value: str) -> str:
    if len(value) <= MAX_STRING:
        return value
    return value[:MAX_STRING] + "...[truncated]"


def _safe_env(value: Any, warnings: list[str]) -> dict[str, Any] | str:
    if not isinstance(value, dict):
        warnings.append("env_payload_not_mapping")
        return "[ENV_VALUE_OMITTED]"

    safe: dict[str, Any] = {}
    for index, (key, item) in enumerate(value.items()):
        if index >= MAX_ITEMS:
            warnings.append("env_payload_truncated")
            break
        key_text = str(key)
        if _is_sensitive_key(key_text) or _is_sensitive_value(item):
            safe[key_text] = "[REDACTED]"
        else:
            safe[key_text] = "[ENV_VALUE_OMITTED]"
    warnings.append("env_values_omitted")
    return safe


def _safe_value(value: Any, warnings: list[str], *, key: str | None = None, depth: int = 0) -> Any:
    if key and _is_sensitive_key(key):
        return "[REDACTED]"
    if key and key.lower() in {"env", "environment"}:
        return _safe_env(value, warnings)
    if _is_sensitive_value(value):
        return "[REDACTED]"
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _truncate(value)
    if depth >= MAX_DEPTH:
        warnings.append("payload_depth_truncated")
        return f"[{type(value).__name__}_OMITTED]"
    if isinstance(value, dict):
        safe: dict[str, Any] = {}
        for index, (item_key, item_value) in enumerate(value.items()):
            if index >= MAX_ITEMS:
                warnings.append("payload_mapping_truncated")
                break
            key_text = str(item_key)
            safe[key_text] = _safe_value(item_value, warnings, key=key_text, depth=depth + 1)
        return safe
    if isinstance(value, (list, tuple, set)):
        items = list(value)
        if len(items) > MAX_ITEMS:
            warnings.append("payload_sequence_truncated")
        return [_safe_value(item, warnings, depth=depth + 1) for item in items[:MAX_ITEMS]]

    return _truncate(repr(value))


def _payload_from_args(args: tuple[Any, ...], kwargs: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = dict(kwargs)
    if args:
        payload["_args"] = list(args)
    return payload


def _record_hook(hook: str, args: tuple[Any, ...], kwargs: dict[str, Any]) -> None:
    warnings: list[str] = []
    payload = _payload_from_args(args, kwargs)
    record = {
        "hook": hook,
        "observed_at": _now(),
        "payload_keys": sorted(str(key) for key in payload.keys()),
        "payload_safe": _safe_value(payload, warnings),
        "warnings": sorted(set(warnings)),
        "prototype": True,
    }

    log_dir = os.environ.get("HERMES_EVIDENCE_HOOK_LOG_DIR")
    if not log_dir:
        return

    try:
        target_dir = pathlib.Path(log_dir).expanduser().resolve()
        target_dir.mkdir(parents=True, exist_ok=True)
        with (target_dir / "hooks.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception:
        # Hooks are evidence probes only. A logging failure must not affect the
        # user's tool call, session lifecycle, or subagent lifecycle.
        return


def pre_tool_call(*args: Any, **kwargs: Any) -> None:
    _record_hook("pre_tool_call", args, kwargs)
    return None


def post_tool_call(*args: Any, **kwargs: Any) -> None:
    _record_hook("post_tool_call", args, kwargs)
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
