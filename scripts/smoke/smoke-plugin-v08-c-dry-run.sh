#!/usr/bin/env bash
# smoke-plugin-v08-c-dry-run.sh — controlled-worker C-class dry-run through real Hermes tool dispatch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/plugins/hermes-evidence-runtime"
PLUGIN_NAME="hermes-evidence-runtime"
TMP_ROOT="/tmp/hermes-v08-c-dry-run"
TMP_HOME="$TMP_ROOT/home"
PROJECT_ROOT="$TMP_ROOT/project"
WORK_ROOT="$PROJECT_ROOT/work"
LOG_DIR="$TMP_ROOT/hook-log"
SUMMARY_PATH="/tmp/hermes-v08-c-dry-run-summary.json"
REAL_HOME="${HOME:-}"
HERMES_AGENT_ROOT="${HERMES_AGENT_ROOT:-$HOME/.hermes/hermes-agent}"
PYTHON_BIN="${PYTHON_BIN:-$HERMES_AGENT_ROOT/venv/bin/python}"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

resolve_hermes_bin() {
  if [[ -n "${HERMES_BIN_OVERRIDE:-}" && -x "$HERMES_BIN_OVERRIDE" ]]; then
    printf '%s\n' "$HERMES_BIN_OVERRIDE"
    return 0
  fi

  local candidate raw resolved
  candidate="$(command -v hermes 2>/dev/null || true)"
  if [[ -z "$candidate" ]]; then
    return 1
  fi
  if [[ -f "$candidate" ]]; then
    raw="$(grep -E '^HERMES_BIN=' "$candidate" 2>/dev/null | head -1 || true)"
    if [[ -n "$raw" ]]; then
      resolved="${raw#HERMES_BIN=}"
      resolved="${resolved%\"}"
      resolved="${resolved#\"}"
      resolved="${resolved//\$HOME/$REAL_HOME}"
      resolved="${resolved//\$\{HOME\}/$REAL_HOME}"
      if [[ -x "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
    raw="$(grep -E '^exec ".*hermes" "\$@"' "$candidate" 2>/dev/null | head -1 || true)"
    if [[ -n "$raw" ]]; then
      resolved="${raw#exec \"}"
      resolved="${resolved%%\"*}"
      if [[ -x "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
  fi
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

HERMES_BIN="$(resolve_hermes_bin || true)"
if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then
  echo "FAIL: hermes binary not found"
  exit 1
fi
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "FAIL: Hermes Python not found: $PYTHON_BIN"
  exit 1
fi

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_HOME/.hermes/plugins" "$WORK_ROOT" "$LOG_DIR"
cp -R "$PLUGIN_SRC" "$TMP_HOME/.hermes/plugins/$PLUGIN_NAME"

HERMES_HOME="$TMP_HOME/.hermes" "$HERMES_BIN" plugins enable "$PLUGIN_NAME" >/tmp/hermes-v08-plugin-enable.out

HERMES_HOME="$TMP_HOME/.hermes" \
HERMES_DEV_PIPELINE_KIT_ROOT="$REPO_ROOT" \
HERMES_EVIDENCE_HOOK_LOG_DIR="$LOG_DIR" \
HERMES_EVIDENCE_HOOK_CAPTURE_MODE="real_runtime" \
PYTHONPATH="$HERMES_AGENT_ROOT" \
"$PYTHON_BIN" - "$REPO_ROOT" "$PROJECT_ROOT" "$WORK_ROOT" "$LOG_DIR" "$SUMMARY_PATH" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys

from hermes_cli.plugins import discover_plugins
from model_tools import handle_function_call

repo_root = pathlib.Path(sys.argv[1]).resolve()
project_root = pathlib.Path(sys.argv[2]).resolve()
work_root = pathlib.Path(sys.argv[3]).resolve()
log_dir = pathlib.Path(sys.argv[4]).resolve()
summary_path = pathlib.Path(sys.argv[5]).resolve()

discover_plugins(force=True)


def call_tool(name, payload, *, expect_ok=True):
    result = handle_function_call(
        name,
        payload,
        task_id="v08-c-dry-run-smoke",
        session_id="v08-c-dry-run-session",
        tool_call_id=f"v08-{name}",
        turn_id="v08-turn",
        api_request_id="v08-api-request",
        enabled_toolsets=["evidence_runtime"],
    )
    data = json.loads(result)
    if not isinstance(data, dict):
        raise AssertionError(f"{name} did not return object: {result}")
    if expect_ok and data.get("ok") is not True:
        raise AssertionError(f"{name} failed: {json.dumps(data, indent=2, ensure_ascii=False)}")
    if not expect_ok and data.get("ok") is True:
        raise AssertionError(f"{name} unexpectedly passed: {json.dumps(data, indent=2, ensure_ascii=False)}")
    return data


def run_script(*args):
    subprocess.run(
        ["bash", str(repo_root / "scripts" / args[0]), *map(str, args[1:])],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def append_event(run_dir, event_type, actor, state_after, *artifacts):
    args = [
        "append-event.sh",
        "--run-dir",
        run_dir,
        "--event-type",
        event_type,
        "--actor",
        actor,
        "--state-after",
        state_after,
    ]
    for artifact in artifacts:
        args.extend(["--artifact", artifact])
    run_script(*args)


def write_json(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def prepare_run(name, *, with_worker=False, hook_path=None):
    work_dir = work_root / name
    work_dir.mkdir(parents=True, exist_ok=True)
    init = call_tool(
        "evidence_run_init",
        {
            "project_root": str(project_root),
            "task": f"v0.8 C dry-run {name}",
            "scale": "M",
            "mode": "auto_run",
            "task_type": "feature",
            "run_id": f"v08-{name}",
            "project": "v08-c-dry-run",
        },
    )
    run_dir = pathlib.Path(init["run_dir"]).resolve()
    append_event(str(run_dir), "INTAKE_RECORDED", "Hermes", "INTAKE_RECORDED", "task.md")
    append_event(str(run_dir), "WORK_ORDER_CREATED", "Hermes", "WORK_ORDER_CREATED", "work-orders/WO-1.json")
    append_event(str(run_dir), "CLAUDECODE_DELEGATED", "Hermes", "CLAUDECODE_DELEGATED", "work-orders/WO-1.json")

    (work_dir / "test.js").write_text(
        "const { add } = require('./src/add');\n"
        "if (add(2, 3) !== 5) throw new Error('bad add');\n"
        "console.log('green ok');\n",
        encoding="utf-8",
    )
    red = call_tool(
        "evidence_record_command",
        {
            "run_dir": str(run_dir),
            "work_dir": str(work_dir),
            "command": "node test.js",
            "phase": "RED",
            "step_id": "red-missing-implementation",
        },
    )
    if red.get("command_exit_code") == 0:
        raise AssertionError("RED unexpectedly passed")

    (work_dir / "src").mkdir(exist_ok=True)
    (work_dir / "src" / "add.js").write_text(
        "function add(a, b) { return a + b; }\nmodule.exports = { add };\n",
        encoding="utf-8",
    )
    green = call_tool(
        "evidence_record_command",
        {
            "run_dir": str(run_dir),
            "work_dir": str(work_dir),
            "command": "node test.js",
            "phase": "GREEN",
            "step_id": "green-correct-implementation",
        },
    )
    if green.get("command_exit_code") != 0:
        raise AssertionError(f"GREEN failed: {green}")

    (run_dir / "raw" / "files-touched.txt").write_text("test.js\nsrc/add.js\n", encoding="utf-8")
    controlled_worker_result = {
        "work_order_id": "WO-1",
        "status": "completed",
        "required_matt_skill": "tdd",
        "worker_type": "controlled_fixture",
        "capture_mode": "raw_fixture",
        "real_worker_capture": False,
        "matt_evidence": {
            "red": "node test.js failed before src/add.js existed",
            "red_exit_code": red["command_exit_code"],
            "red_not_applicable_reason": "",
            "green": "node test.js passed after src/add.js implementation",
            "green_exit_code": green["command_exit_code"],
            "commands": ["node test.js", "node test.js"],
        },
        "files_touched": ["test.js", "src/add.js"],
        "commands_run": ["node test.js", "node test.js"],
        "blocked": False,
        "notes": "Controlled worker result fixture. No real ClaudeCode/Codex/OpenCode worker was invoked. No acceptance field.",
    }
    write_json(run_dir / "raw" / "controlled-worker-result.json", controlled_worker_result)

    # Legacy compatibility alias for existing v0.4-v0.8 harness scripts.
    # This is not real ClaudeCode evidence.
    claudecode_alias = dict(controlled_worker_result)
    claudecode_alias["legacy_compatibility_alias"] = "not real ClaudeCode evidence"
    claudecode_alias["notes"] = (
        "Legacy compatibility alias for raw/controlled-worker-result.json. "
        "This is not real ClaudeCode evidence and must not be counted as official worker capture."
    )
    write_json(run_dir / "raw" / "claudecode-result.json", claudecode_alias)
    append_event(
        str(run_dir),
        "CLAUDECODE_RESULT_RECORDED",
        "harness",
        "CLAUDECODE_RESULT_RECORDED",
        "raw/controlled-worker-result.json",
        "raw/claudecode-result.json",
    )

    if with_worker:
        write_worker_result(run_dir, with_acceptance=False)
    return run_dir


def write_worker_result(run_dir, *, with_acceptance=False):
    raw_output = run_dir / "raw" / "worker-controlled.raw.txt"
    raw_output.write_text("controlled worker fixture output; no real worker spawned\n", encoding="utf-8")
    worker_result = {
        "schema_version": "0.5.3",
        "work_order_id": "WO-1",
        "worker": "unknown",
        "worker_skill": "controlled-fixture/tdd",
        "status": "completed",
        "result_type": "implementation",
        "raw_output_path": "raw/worker/WO-1.raw.txt",
        "structured_output_path": "raw/worker/WO-1.worker-result.json",
        "files_touched": ["test.js", "src/add.js"],
        "commands_run": ["node test.js", "node test.js"],
        "evidence_refs": ["raw/command-log.jsonl"],
        "review": {
            "verdict": "UNKNOWN",
            "summary": "Controlled worker fixture; not official worker capture.",
            "blocking_findings": [],
        },
        "deferred": {
            "is_deferred": False,
            "reason": "",
        },
        "real_invocation": False,
        "skipped_reason": "controlled worker fixture; no real worker spawned",
        "notes": "Synthetic controlled worker result for v0.8 dry-run only.",
    }
    if with_acceptance:
        worker_result["acceptance"] = {"complete": True}
    fixture_path = run_dir / "raw" / "worker-fixture.json"
    write_json(fixture_path, worker_result)
    result = call_tool(
        "evidence_record_worker_result",
        {
            "run_dir": str(run_dir),
            "worker_result_path": str(fixture_path),
            "raw_output_path": str(raw_output),
        },
        expect_ok=not with_acceptance,
    )
    if not with_acceptance:
        shutil.copyfile(run_dir / "raw" / "worker" / "WO-1.worker-result.json", run_dir / "raw" / "worker-result.json")
    return result


def assert_hook_log():
    hook_log = log_dir / "hook-events.jsonl"
    if not hook_log.is_file() or hook_log.stat().st_size == 0:
        raise AssertionError("missing hook-events.jsonl")
    records = [json.loads(line) for line in hook_log.read_text(encoding="utf-8").splitlines() if line.strip()]
    hooks = {item.get("hook_name") for item in records if item.get("capture_mode") == "real_runtime"}
    if not {"pre_tool_call", "post_tool_call"}.issubset(hooks):
        raise AssertionError(f"missing real pre/post hook events: {hooks}")
    for item in records:
        if item.get("capture_mode") == "real_runtime":
            if item.get("provenance", {}).get("source") != "Hermes hook callback":
                raise AssertionError("bad hook provenance")
            if item.get("provenance", {}).get("log_only") is not True:
                raise AssertionError("hook not marked log_only")
    return hook_log


positive_run = prepare_run("positive", with_worker=True)
hook_log = assert_hook_log()

generated = call_tool(
    "evidence_generate_run_state",
    {
        "run_dir": str(positive_run),
        "hook_log_path": str(hook_log),
    },
)
policy = call_tool("evidence_policy_check", {"run_dir": str(positive_run)})
if policy.get("verdict") != "PASS":
    raise AssertionError(f"policy not PASS: {policy}")
final_report = call_tool("evidence_final_report", {"run_dir": str(positive_run)})
approval = call_tool("evidence_approval_inbox", {"run_dir": str(positive_run)})

required_artifacts = [
    "run-manifest.json",
    "classification.json",
    "work-orders/WO-1.json",
    "raw/hook-events.jsonl",
    "raw/command-log.jsonl",
    "raw/controlled-worker-result.json",
    "raw/claudecode-result.json",
    "raw/worker/WO-1.worker-result.json",
    "raw/worker-result.json",
    "generated/run-state.json",
    "generated/policy-result.json",
    "generated/final-report.md",
    "generated/approval-inbox.json",
]
for rel in required_artifacts:
    path = positive_run / rel
    if not path.is_file() or path.stat().st_size == 0:
        raise AssertionError(f"missing artifact: {rel}")

state = json.loads((positive_run / "generated" / "run-state.json").read_text(encoding="utf-8"))
if state.get("runtime_integration", {}).get("verdict") != "PASS_C_DRY_RUN_CONTROLLED_WORKER":
    raise AssertionError("wrong runtime integration verdict")
if state.get("runtime_integration", {}).get("real_worker_capture") is not False:
    raise AssertionError("run-state must not claim real worker capture")
if state.get("runtime_integration", {}).get("enforcement") is not False:
    raise AssertionError("run-state must not claim enforcement")
if state.get("provenance", {}).get("generated_by") != "evidence_generate_run_state":
    raise AssertionError("wrong run-state generator provenance")
sources = set(state.get("provenance", {}).get("source_files") or [])
for rel in required_artifacts[:8]:
    if rel not in sources:
        raise AssertionError(f"source missing from provenance: {rel}")
controlled_result = json.loads((positive_run / "raw" / "controlled-worker-result.json").read_text(encoding="utf-8"))
if controlled_result.get("worker_type") != "controlled_fixture":
    raise AssertionError("controlled worker result missing worker_type=controlled_fixture")
if controlled_result.get("capture_mode") != "raw_fixture":
    raise AssertionError("controlled worker result missing capture_mode=raw_fixture")
if controlled_result.get("real_worker_capture") is not False:
    raise AssertionError("controlled worker result must not claim real capture")
legacy_alias = json.loads((positive_run / "raw" / "claudecode-result.json").read_text(encoding="utf-8"))
if legacy_alias.get("legacy_compatibility_alias") != "not real ClaudeCode evidence":
    raise AssertionError("legacy ClaudeCode alias must explicitly disclaim real ClaudeCode evidence")
if state.get("command_log_summary", {}).get("red_exit_code") == 0:
    raise AssertionError("RED exit must be non-zero")
if state.get("command_log_summary", {}).get("green_exit_code") != 0:
    raise AssertionError("GREEN exit must be zero")

inbox = json.loads((positive_run / "generated" / "approval-inbox.json").read_text(encoding="utf-8"))
if inbox.get("status") != "pending":
    raise AssertionError("approval inbox must remain pending")
if inbox["items"][0].get("approved") is not False:
    raise AssertionError("approval artifact must not be approved")

negative_results = {}

missing_worker_run = prepare_run("negative-missing-worker", with_worker=False)
negative_results["generate_before_worker_result"] = call_tool(
    "evidence_generate_run_state",
    {"run_dir": str(missing_worker_run), "hook_log_path": str(hook_log)},
    expect_ok=False,
)

negative_results["policy_before_run_state"] = call_tool(
    "evidence_policy_check",
    {"run_dir": str(missing_worker_run)},
    expect_ok=False,
)

final_before_policy_run = prepare_run("negative-final-before-policy", with_worker=True)
generate_for_final_negative = call_tool(
    "evidence_generate_run_state",
    {"run_dir": str(final_before_policy_run), "hook_log_path": str(hook_log)},
)
negative_results["final_report_before_policy"] = call_tool(
    "evidence_final_report",
    {"run_dir": str(final_before_policy_run)},
    expect_ok=False,
)

negative_results["approval_before_run_state"] = call_tool(
    "evidence_approval_inbox",
    {"run_dir": str(missing_worker_run)},
    expect_ok=False,
)

wrong_run_id = prepare_run("negative-wrong-run-id", with_worker=True)
manifest_path = wrong_run_id / "run-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["run_id"] = "wrong-run-id"
write_json(manifest_path, manifest)
negative_results["wrong_run_id"] = call_tool(
    "evidence_generate_run_state",
    {"run_dir": str(wrong_run_id), "hook_log_path": str(hook_log)},
    expect_ok=False,
)

missing_source = prepare_run("negative-missing-source", with_worker=True)
first_record = next((missing_source / "raw" / "commands").glob("*.json"))
first_record.unlink()
negative_results["missing_source_file"] = call_tool(
    "evidence_generate_run_state",
    {"run_dir": str(missing_source), "hook_log_path": str(hook_log)},
    expect_ok=False,
)

self_acceptance = prepare_run("negative-worker-self-acceptance", with_worker=False)
negative_results["worker_self_acceptance"] = write_worker_result(self_acceptance, with_acceptance=True)

green_without_red = call_tool(
    "evidence_run_init",
    {
        "project_root": str(project_root),
        "task": "v0.8 missing RED negative",
        "scale": "M",
        "mode": "auto_run",
        "task_type": "feature",
        "run_id": "v08-negative-green-without-red",
        "project": "v08-c-dry-run",
    },
)
green_run = pathlib.Path(green_without_red["run_dir"]).resolve()
append_event(str(green_run), "INTAKE_RECORDED", "Hermes", "INTAKE_RECORDED", "task.md")
append_event(str(green_run), "WORK_ORDER_CREATED", "Hermes", "WORK_ORDER_CREATED", "work-orders/WO-1.json")
append_event(str(green_run), "CLAUDECODE_DELEGATED", "Hermes", "CLAUDECODE_DELEGATED", "work-orders/WO-1.json")
green_work = work_root / "negative-green-without-red"
green_work.mkdir(parents=True, exist_ok=True)
(green_work / "test.js").write_text("console.log('no red');\n", encoding="utf-8")
negative_results["green_without_red"] = call_tool(
    "evidence_record_command",
    {
        "run_dir": str(green_run),
        "work_dir": str(green_work),
        "command": "node test.js",
        "phase": "GREEN",
        "step_id": "green-without-red",
    },
    expect_ok=False,
)

synthetic_hook_run = prepare_run("negative-synthetic-hook", with_worker=True)
synthetic_hook = synthetic_hook_run / "raw" / "synthetic-hook-events.jsonl"
synthetic_hook.write_text(
    json.dumps({
        "hook_name": "pre_tool_call",
        "capture_mode": "real_runtime",
        "provenance": {"source": "synthetic fixture", "log_only": True},
    }) + "\n" +
    json.dumps({
        "hook_name": "post_tool_call",
        "capture_mode": "real_runtime",
        "provenance": {"source": "Hermes hook callback", "log_only": True},
    }) + "\n",
    encoding="utf-8",
)
negative_results["synthetic_hook_marked_real"] = call_tool(
    "evidence_generate_run_state",
    {"run_dir": str(synthetic_hook_run), "hook_log_path": str(synthetic_hook)},
    expect_ok=False,
)

negative_results["approval_preapproved"] = call_tool(
    "evidence_approval_inbox",
    {"run_dir": str(positive_run), "approved": True},
    expect_ok=False,
)

summary = {
    "smoke": "plugin-v08-c-dry-run",
    "ok": True,
    "verdict": "PASS_C_DRY_RUN_CONTROLLED_WORKER",
    "plugin_version": "0.8.0",
    "temp_home": os.environ.get("HERMES_HOME"),
    "run_dir": str(positive_run),
    "tool_results": {
        "evidence_generate_run_state": generated,
        "evidence_policy_check": policy,
        "evidence_final_report": final_report,
        "evidence_approval_inbox": approval,
    },
    "artifacts": required_artifacts,
    "real_evidence": {
        "tool_dispatch": True,
        "command_red_exit_code": state["command_log_summary"]["red_exit_code"],
        "command_green_exit_code": state["command_log_summary"]["green_exit_code"],
        "hook_log": str(hook_log),
        "real_runtime_hooks": state["hook_evidence"]["real_runtime_hooks"],
    },
    "controlled_evidence": {
        "controlled_worker_result": "raw/controlled-worker-result.json",
        "legacy_compatibility_alias": "raw/claudecode-result.json",
        "worker_result": "raw/worker/WO-1.worker-result.json",
        "real_worker_capture": False,
    },
    "negative_tests": {name: result.get("error", result.get("verdict", "FAIL_EXPECTED")) for name, result in negative_results.items()},
}
write_json(summary_path, summary)
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
PY

python3 -m json.tool "$SUMMARY_PATH" >/dev/null
grep -q '"verdict": "PASS_C_DRY_RUN_CONTROLLED_WORKER"' "$SUMMARY_PATH"
grep -q '"real_worker_capture": false' "$SUMMARY_PATH"
grep -q '"generate_before_worker_result"' "$SUMMARY_PATH"
grep -q '"synthetic_hook_marked_real"' "$SUMMARY_PATH"
grep -q '"approval_preapproved"' "$SUMMARY_PATH"

echo "smoke-plugin-v08-c-dry-run: PASS"
