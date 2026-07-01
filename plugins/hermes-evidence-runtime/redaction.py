"""Redaction helpers for hermes-evidence-runtime hook evidence.

v0.7 hooks are observation-only. Redaction must be conservative because hook
payloads can contain prompts, session identifiers, command output, credentials,
environment dictionaries, or arbitrary Python objects.
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import traceback
from typing import Any


MAX_STRING = 512
MAX_DEPTH = 6
MAX_LIST_ENTRIES = 50
MAX_DICT_KEYS = 100

SENSITIVE_KEY_RE = re.compile(
    r"token|secret|password|passwd|authorization|cookie|api_key|apikey|"
    r"private_key|access_key|refresh_token|session|credential|"
    r"tool_call_id|call_id|api_request_id|request_id|turn_id",
    re.IGNORECASE,
)
CONTENT_KEY_RE = re.compile(
    r"prompt|message|conversation|history|stdout|stderr|output|file_body|"
    r"body|content|result",
    re.IGNORECASE,
)
BEARER_RE = re.compile(r"bearer\s+[A-Za-z0-9._~+/=-]+", re.IGNORECASE)
SECRET_ASSIGNMENT_RE = re.compile(
    r"(?i)(token|secret|password|passwd|authorization|cookie|api_key|apikey|"
    r"private_key|access_key|refresh_token|credential)=([^&\s]+)"
)
QUERY_SECRET_RE = re.compile(
    r"(?i)([?&](?:token|secret|password|passwd|authorization|cookie|api_key|"
    r"apikey|private_key|access_key|refresh_token|credential)=)([^&#\s]+)"
)
PEM_PRIVATE_KEY_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.IGNORECASE | re.DOTALL,
)
CANARY_RE = re.compile(r"V07_CANARY_(?:TOKEN|PASSWORD)_[A-Za-z0-9]+")
USER_PATH_RE = re.compile(r"/Users/([^/\s]+)")


def hash_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    if not text:
        return None
    digest = hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()
    return f"sha256:{digest[:16]}"


def _truncate(text: str, warnings: list[str]) -> str:
    if len(text) <= MAX_STRING:
        return text
    warnings.append("string_truncated")
    return text[:MAX_STRING] + "...[truncated]"


def redact_string(value: str, warnings: list[str]) -> str:
    text = value
    text = PEM_PRIVATE_KEY_RE.sub("[REDACTED_PRIVATE_KEY]", text)
    text = BEARER_RE.sub("Bearer [REDACTED]", text)
    text = QUERY_SECRET_RE.sub(lambda match: match.group(1) + "[REDACTED]", text)
    text = SECRET_ASSIGNMENT_RE.sub(lambda match: match.group(1) + "=[REDACTED]", text)
    text = CANARY_RE.sub("[REDACTED_CANARY]", text)
    text = USER_PATH_RE.sub("/Users/[USER]", text)
    return _truncate(text, warnings)


def _content_placeholder(key: str, value: Any) -> dict[str, Any]:
    try:
        size = len(value)  # type: ignore[arg-type]
    except Exception:
        size = None
    result: dict[str, Any] = {
        "omitted": True,
        "reason": f"{key}_content_not_logged",
        "type": type(value).__name__,
    }
    if isinstance(size, int):
        result["length"] = size
    return result


def safe_serialize(value: Any) -> tuple[Any, list[str]]:
    warnings: list[str] = []
    seen: set[int] = set()
    try:
        return _safe_value(value, warnings, key=None, depth=0, seen=seen), sorted(set(warnings))
    except Exception as exc:
        return {
            "serialization_error": True,
            "error_type": type(exc).__name__,
            "error": redact_string(str(exc), warnings),
        }, sorted(set(warnings + ["serialization_error"]))


def _safe_value(
    value: Any,
    warnings: list[str],
    *,
    key: str | None,
    depth: int,
    seen: set[int],
) -> Any:
    if key and SENSITIVE_KEY_RE.search(key):
        return "[REDACTED]"
    if key and key.lower() in {"env", "environment", "environ"}:
        warnings.append("environment_omitted")
        return "[ENVIRONMENT_OMITTED]"
    if key and CONTENT_KEY_RE.search(key):
        warnings.append("content_omitted")
        return _content_placeholder(key, value)

    if value is None or isinstance(value, (bool, int, float)):
        return value

    if isinstance(value, str):
        return redact_string(value, warnings)

    if isinstance(value, bytes):
        warnings.append("bytes_omitted")
        return {"omitted": True, "type": "bytes", "length": len(value)}

    if isinstance(value, BaseException):
        warnings.append("exception_serialized")
        return {
            "type": type(value).__name__,
            "message": redact_string(str(value), warnings),
        }

    if isinstance(value, pathlib.Path):
        return redact_string(str(value), warnings)

    value_id = id(value)
    if isinstance(value, (dict, list, tuple, set)):
        if value_id in seen:
            warnings.append("cycle_detected")
            return "[CYCLE]"
        seen.add(value_id)

    if depth >= MAX_DEPTH:
        warnings.append("payload_depth_truncated")
        return f"[{type(value).__name__}_OMITTED]"

    if isinstance(value, dict):
        safe: dict[str, Any] = {}
        for index, (item_key, item_value) in enumerate(value.items()):
            if index >= MAX_DICT_KEYS:
                warnings.append("dict_keys_truncated")
                break
            key_text = redact_string(str(item_key), warnings)
            safe[key_text] = _safe_value(
                item_value,
                warnings,
                key=str(item_key),
                depth=depth + 1,
                seen=seen,
            )
        seen.discard(value_id)
        return safe

    if isinstance(value, (list, tuple, set)):
        items = list(value)
        if len(items) > MAX_LIST_ENTRIES:
            warnings.append("list_entries_truncated")
        safe_items = [
            _safe_value(item, warnings, key=None, depth=depth + 1, seen=seen)
            for item in items[:MAX_LIST_ENTRIES]
        ]
        seen.discard(value_id)
        return safe_items

    try:
        return redact_string(repr(value), warnings)
    except Exception as exc:
        warnings.append("repr_failed")
        return {
            "serialization_error": True,
            "error_type": type(exc).__name__,
            "traceback_type": traceback.format_exception_only(type(exc), exc)[-1].strip(),
        }
