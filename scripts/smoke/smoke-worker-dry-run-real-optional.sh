#!/usr/bin/env bash
# smoke-worker-dry-run-real-optional.sh — Optional real worker CLI dry-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${HERMES_EVIDENCE_ALLOW_REAL_WORKER_DRY_RUN:-}" != "1" ]]; then
  echo "smoke-worker-dry-run-real-optional: SKIPPED (set HERMES_EVIDENCE_ALLOW_REAL_WORKER_DRY_RUN=1 to enable)"
  exit 0
fi

TMP_ROOT="$(mktemp -d /tmp/hermes-worker-dry-run-real.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

available=0
success=0

run_if_available() {
  local worker="$1"
  local executable="$2"
  local out_dir="$TMP_ROOT/$worker"

  if ! command -v "$executable" >/dev/null 2>&1; then
    echo "SKIPPED: $worker ($executable CLI not found)"
    return 0
  fi

  available=$((available + 1))
  bash "$REPO_ROOT/scripts/invoke-worker-dry-run.sh" \
    --worker "$worker" \
    --out-dir "$out_dir" \
    --timeout-seconds 60 \
    --allow-real-invocation yes >/dev/null

  set +e
  python3 - "$out_dir/invocation.json" "$worker" <<'PY'
import json
import sys

path, worker = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
print(json.dumps({
    "worker": worker,
    "real_invocation": data.get("real_invocation"),
    "exit_code": data.get("exit_code"),
    "skipped_reason": data.get("skipped_reason", ""),
}, ensure_ascii=False, sort_keys=True))
if data.get("real_invocation") is True and data.get("exit_code") == 0:
    sys.exit(0)
sys.exit(2)
PY
  result=$?
  set -e
  case "$result" in
    0) success=$((success + 1)) ;;
    2) ;;
  esac
}

run_if_available "claude-code" "claude"
run_if_available "codex" "codex"
run_if_available "opencode" "opencode"

if [[ "$available" -eq 0 ]]; then
  echo "smoke-worker-dry-run-real-optional: SKIPPED (no supported worker CLI found)"
  exit 0
fi

if [[ "$success" -eq 0 ]]; then
  echo "FAIL: supported worker CLI found but no real dry-run completed successfully"
  exit 1
fi

echo "smoke-worker-dry-run-real-optional: PASS ($success/$available real worker dry-runs succeeded)"
