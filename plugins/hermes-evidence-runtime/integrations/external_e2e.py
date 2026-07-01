"""External live E2E classification helpers.

These helpers keep provider availability separate from deterministic code or
contract failures. They intentionally do not call any provider.
"""

from __future__ import annotations

EXTERNAL_UNAVAILABLE = {
    "NO_PROVIDER_CONFIG",
    "AUTH_UNAVAILABLE",
    "QUOTA_UNAVAILABLE",
    "MODEL_UNAVAILABLE",
    "NETWORK_UNAVAILABLE",
    "TIMEOUT",
}

CODE_OR_CONTRACT_FAILURE = {
    "CODE_FAILURE",
    "CONTRACT_FAILURE",
}


def classify_external_error(message: str) -> str:
    """Classify an external live E2E error without converting skips into PASS."""
    lower = str(message or "").lower()
    if "no inference provider" in lower or "unknown provider" in lower or "no provider" in lower:
        return "NO_PROVIDER_CONFIG"
    if (
        "auth" in lower
        or "credential" in lower
        or "api key" in lower
        or "401" in lower
        or "403" in lower
    ):
        return "AUTH_UNAVAILABLE"
    if (
        "quota" in lower
        or "rate limit" in lower
        or "ratelimit" in lower
        or "429" in lower
        or "token plan" in lower
        or "用量上限" in lower
    ):
        return "QUOTA_UNAVAILABLE"
    if "timeout" in lower or "timed out" in lower:
        return "TIMEOUT"
    if "network" in lower or "connection" in lower or "dns" in lower:
        return "NETWORK_UNAVAILABLE"
    if "model" in lower or "404" in lower:
        return "MODEL_UNAVAILABLE"
    if (
        "structured output" in lower
        or "valid structured output" in lower
        or "schema" in lower
        or "contract" in lower
    ):
        return "CONTRACT_FAILURE"
    if (
        "traceback" in lower
        or "nameerror" in lower
        or "typeerror" in lower
        or "attributeerror" in lower
        or "assertionerror" in lower
        or "runtimeerror" in lower
    ):
        return "CODE_FAILURE"
    return "UNKNOWN"


def external_result_for_classification(classification: str) -> str:
    if classification in EXTERNAL_UNAVAILABLE:
        return "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE"
    if classification in CODE_OR_CONTRACT_FAILURE:
        return "FAIL_CODE_OR_CONTRACT"
    if classification == "PASS_REAL_RUNTIME":
        return "PASS_REAL_RUNTIME"
    return "FAIL_CODE_OR_CONTRACT"


def exit_code_for_external_classification(classification: str) -> int:
    if classification == "PASS_REAL_RUNTIME":
        return 0
    if classification in EXTERNAL_UNAVAILABLE:
        return 77
    if classification in CODE_OR_CONTRACT_FAILURE:
        return 1
    return 2
