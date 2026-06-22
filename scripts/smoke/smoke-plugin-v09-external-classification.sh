#!/usr/bin/env bash
# smoke-plugin-v09-external-classification.sh — deterministic external E2E result classification.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

python3 - <<'PY' "$REPO_ROOT"
import importlib.util
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
module_path = repo_root / "plugins/hermes-evidence-runtime/integrations/external_e2e.py"
spec = importlib.util.spec_from_file_location("external_e2e", module_path)
if spec is None or spec.loader is None:
    raise AssertionError(f"missing external E2E classifier: {module_path}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

cases = [
    ("HTTP 429: 已达到 Token Plan 用量上限", "QUOTA_UNAVAILABLE", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("rate limit exceeded", "QUOTA_UNAVAILABLE", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("no inference provider configured", "NO_PROVIDER_CONFIG", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("401 invalid api key", "AUTH_UNAVAILABLE", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("model not found 404", "MODEL_UNAVAILABLE", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("connection refused while calling provider", "NETWORK_UNAVAILABLE", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("timeout while calling provider", "TIMEOUT", "SKIP_EXTERNAL_PROVIDER_UNAVAILABLE", 77),
    ("Dynamic Workflows child did not complete with valid structured output", "CONTRACT_FAILURE", "FAIL_CODE_OR_CONTRACT", 1),
    ("NameError: missing local variable", "CODE_FAILURE", "FAIL_CODE_OR_CONTRACT", 1),
]

for message, classification, result, exit_code in cases:
    observed = module.classify_external_error(message)
    if observed != classification:
        raise AssertionError(f"{message!r}: expected {classification}, got {observed}")
    observed_result = module.external_result_for_classification(observed)
    if observed_result != result:
        raise AssertionError(f"{classification}: expected result {result}, got {observed_result}")
    observed_exit = module.exit_code_for_external_classification(observed)
    if observed_exit != exit_code:
        raise AssertionError(f"{classification}: expected exit {exit_code}, got {observed_exit}")

if module.external_result_for_classification("QUOTA_UNAVAILABLE") == "PASS_REAL_RUNTIME":
    raise AssertionError("quota unavailable must never be counted as real runtime PASS")

print("smoke-plugin-v09-external-classification: PASS")
PY
