#!/usr/bin/env bash
# smoke-plugin-hooks-v07-secret-canary.sh — explicit canary leak check for real hook logs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_PATH="/tmp/hermes-v07-hook-secret-canary.out"

bash "$REPO_ROOT/scripts/smoke/smoke-plugin-hooks-v07-real-runtime.sh" >"$OUT_PATH"

if grep -R "V07_CANARY_TOKEN_7f39e1\|V07_CANARY_PASSWORD_18ce42" /tmp/hermes-v07-hook-smoke; then
  echo "FAIL: canary secret leaked"
  exit 1
fi

echo "smoke-plugin-hooks-v07-secret-canary: PASS"
echo "source smoke output: $OUT_PATH"
