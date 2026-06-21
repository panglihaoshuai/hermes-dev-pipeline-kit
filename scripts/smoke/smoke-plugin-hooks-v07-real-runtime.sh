#!/usr/bin/env bash
# smoke-plugin-hooks-v07-real-runtime.sh — real Hermes model_tools hook path smoke.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/plugins/hermes-evidence-runtime"
PLUGIN_NAME="hermes-evidence-runtime"
TMP_HOME="${TMPDIR:-/tmp}/hermes-v07-hook-runtime-home-$$"
WORK_ROOT="${TMPDIR:-/tmp}/hermes-v07-hook-runtime-work-$$"
LOG_DIR="/tmp/hermes-v07-hook-smoke"
HERMES_BIN="${HERMES_BIN_OVERRIDE:-$(command -v hermes 2>/dev/null || true)}"
HERMES_AGENT_ROOT="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}"
PYTHON_BIN="${PYTHON_BIN:-$HERMES_AGENT_ROOT/venv/bin/python}"
CANARY_TOKEN="V07_CANARY_TOKEN_7f39e1"
CANARY_PASSWORD="V07_CANARY_PASSWORD_18ce42"

cleanup() {
  rm -rf "$TMP_HOME" "$WORK_ROOT"
}
trap cleanup EXIT

if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then
  echo "FAIL: hermes binary not found"
  exit 1
fi
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "FAIL: Hermes Python not found: $PYTHON_BIN"
  exit 1
fi

rm -rf "$TMP_HOME" "$WORK_ROOT" "$LOG_DIR"
mkdir -p "$TMP_HOME/.hermes/plugins" "$WORK_ROOT" "$LOG_DIR"
cp -R "$PLUGIN_SRC" "$TMP_HOME/.hermes/plugins/$PLUGIN_NAME"

HERMES_HOME="$TMP_HOME/.hermes" "$HERMES_BIN" plugins enable "$PLUGIN_NAME" >/tmp/hermes-v07-hook-runtime-enable.out

HERMES_HOME="$TMP_HOME/.hermes" \
HERMES_DEV_PIPELINE_KIT_ROOT="$REPO_ROOT" \
HERMES_EVIDENCE_HOOK_LOG_DIR="$LOG_DIR" \
HERMES_EVIDENCE_HOOK_CAPTURE_MODE="real_runtime" \
PYTHONPATH="$HERMES_AGENT_ROOT" \
"$PYTHON_BIN" - "$WORK_ROOT" "$CANARY_TOKEN" "$CANARY_PASSWORD" <<'PY'
import json
import pathlib
import sys

from hermes_cli.plugins import discover_plugins
from model_tools import handle_function_call

work_root = pathlib.Path(sys.argv[1]).resolve()
canary_token = sys.argv[2]
canary_password = sys.argv[3]

discover_plugins(force=True)
result = handle_function_call(
    "evidence_active_run_status",
    {
        "project_root": str(work_root),
        "token": canary_token,
        "password": canary_password,
    },
    task_id="v07-real-runtime-smoke",
    session_id="v07-real-session-secret",
    tool_call_id="v07-real-call-secret",
    turn_id="v07-real-turn",
    api_request_id="v07-real-api-request",
    enabled_toolsets=["evidence_runtime"],
)
parsed = json.loads(result)
if parsed.get("ok") is not True:
    raise AssertionError(f"tool result not ok: {parsed}")
print(json.dumps({"tool_result": parsed}, sort_keys=True))
PY

test -s "$LOG_DIR/hook-events.jsonl"

python3 - "$LOG_DIR/hook-events.jsonl" "$CANARY_TOKEN" "$CANARY_PASSWORD" <<'PY'
import hashlib
import json
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
canary_token = sys.argv[2]
canary_password = sys.argv[3]
raw = log_path.read_text(encoding="utf-8")
if canary_token in raw or canary_password in raw:
    raise SystemExit("FAIL: canary secret leaked")
if "v07-real-session-secret" in raw or "v07-real-call-secret" in raw or "v07-real-api-request" in raw:
    raise SystemExit("FAIL: raw runtime identifiers leaked")
records = [json.loads(line) for line in raw.splitlines() if line.strip()]
hooks = [record.get("hook_name") for record in records]
modes = {record.get("capture_mode") for record in records}
if "pre_tool_call" not in hooks:
    raise AssertionError("missing pre_tool_call real_runtime record")
if "post_tool_call" not in hooks:
    raise AssertionError("missing post_tool_call real_runtime record")
if modes != {"real_runtime"}:
    raise AssertionError(f"unexpected capture modes: {sorted(modes)}")
for record in records:
    if record.get("provenance", {}).get("log_only") is not True:
        raise AssertionError(f"missing log_only provenance: {record}")
    if record.get("session", {}).get("session_id_hash") in {"v07-real-session-secret", ""}:
        raise AssertionError("raw session id leaked")

digest = hashlib.sha256(log_path.read_bytes()).hexdigest()
print(json.dumps({
    "smoke": "plugin-hooks-v07-real-runtime",
    "ok": True,
    "event_count": len(records),
    "hooks": sorted(set(hooks)),
    "capture_modes": sorted(modes),
    "log_path": str(log_path),
    "sha256": digest,
}, sort_keys=True))
for record in records[:2]:
    print(json.dumps({
        "hook_name": record.get("hook_name"),
        "capture_mode": record.get("capture_mode"),
        "captured_at": record.get("captured_at"),
        "payload_keys": record.get("payload", {}).get("keys_observed", []),
    }, sort_keys=True))
PY

if grep -R "V07_CANARY_TOKEN_7f39e1\|V07_CANARY_PASSWORD_18ce42" "$LOG_DIR"; then
  echo "FAIL: canary secret leaked"
  exit 1
fi

echo "smoke-plugin-hooks-v07-real-runtime: PASS"
