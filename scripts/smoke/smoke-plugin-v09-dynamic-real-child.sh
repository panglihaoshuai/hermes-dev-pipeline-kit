#!/usr/bin/env bash
# smoke-plugin-v09-dynamic-real-child.sh — proves Dynamic Workflows real one-child completion.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DYNAMIC_SOURCE="${DYNAMIC_WORKFLOWS_PLUGIN_SOURCE:-/tmp/hermes-v09-real-backend-research/hermes-dynamic-workflows}"
HERMES_AGENT_PYTHON="${HERMES_AGENT_PYTHON:-$HOME/.hermes/hermes-agent/venv/bin/python}"
TMP_ROOT="$(mktemp -d /tmp/hermes-v09-dynamic-real.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$DYNAMIC_SOURCE/plugin.yaml" ]]; then
  echo "FAIL: Dynamic Workflows plugin source missing. Set DYNAMIC_WORKFLOWS_PLUGIN_SOURCE." >&2
  exit 1
fi

mkdir -p "$TMP_ROOT/home/.hermes/plugins" "$TMP_ROOT/work"
cp -R "$DYNAMIC_SOURCE" "$TMP_ROOT/home/.hermes/plugins/dynamic-workflows"
printf 'codex-v09-dynamic-input\n' >"$TMP_ROOT/work/input.txt"

HERMES_HOME="$TMP_ROOT/home/.hermes" hermes plugins enable dynamic-workflows >/dev/null

HERMES_HOME="$TMP_ROOT/home/.hermes" \
HERMES_DYNAMIC_WORKFLOWS_HOME="$TMP_ROOT/dynamic-store" \
HERMES_DYNAMIC_WORKFLOWS_TMPDIR="$TMP_ROOT/dynamic-tmp" \
"$HERMES_AGENT_PYTHON" - <<'PY' "$TMP_ROOT" "$REPO_ROOT"
import hashlib
import importlib.util
import json
import os
import pathlib
import sys
import time

root = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
work = root / "work"
sys.path.insert(0, str(root / "home/.hermes/plugins/dynamic-workflows"))


external_e2e_path = repo_root / "plugins/hermes-evidence-runtime/integrations/external_e2e.py"
external_spec = importlib.util.spec_from_file_location("external_e2e", external_e2e_path)
if external_spec is None or external_spec.loader is None:
    raise RuntimeError(f"failed to load external E2E classifier: {external_e2e_path}")
external_e2e = importlib.util.module_from_spec(external_spec)
external_spec.loader.exec_module(external_e2e)


# Resolve provider credentials from the live user config in memory only.
# HERMES_HOME is restored to the temp HOME before Dynamic Workflows writes state.
temp_home = os.environ.pop("HERMES_HOME", None)
try:
    from hermes_cli.config import load_config
    from hermes_cli.runtime_provider import resolve_runtime_provider

    cfg = load_config() or {}
    model_cfg = cfg.get("model") or {}
    runtime = resolve_runtime_provider()
    model = model_cfg.get("default") if isinstance(model_cfg, dict) else model_cfg
    if model and not runtime.get("model"):
        runtime["model"] = model
    runtime["max_tokens"] = 512
finally:
    if temp_home:
        os.environ["HERMES_HOME"] = temp_home

from hermes_dynamic_workflows.adapters.workflow import workflow
from hermes_dynamic_workflows.core.config import PluginConfig
from hermes_dynamic_workflows.storage.store import WorkflowStore
import hermes_dynamic_workflows.run.manager as manager_mod

config = PluginConfig(
    workflow_timeout_seconds=90.0,
    child_timeout_seconds=60.0,
    default_child_toolsets=("file", "terminal"),
    blocked_child_toolsets=(
        "workflow",
        "workflows",
        "delegation",
        "code_execution",
        "memory",
        "messaging",
        "clarify",
        "web",
        "browser",
        "skills",
    ),
    require_launch_approval=False,
    child_approval_policy="approve",
    ask_fallback="approve",
    notify_on_complete=False,
    notify_result_preview_chars=500,
)
manager = manager_mod.WorkflowRunManager(store=WorkflowStore(root=root / "dynamic-store"), config=config)
manager_mod._MANAGER = manager


class ParentAgent:
    pass


parent = ParentAgent()
for key, value in runtime.items():
    setattr(parent, key, value)


class Context:
    session_id = "v09-dynamic-session"

    def inject_message(self, *_args, **_kwargs):
        return False


schema = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "work_order_id",
        "status",
        "observations",
        "commands_claimed",
        "files_claimed",
        "notes",
    ],
    "properties": {
        "work_order_id": {"type": "string"},
        "status": {"type": "string", "enum": ["completed", "failed"]},
        "observations": {"type": "array", "items": {"type": "string"}},
        "commands_claimed": {"type": "array", "items": {"type": "string"}},
        "files_claimed": {"type": "array", "items": {"type": "string"}},
        "notes": {"type": "string"},
    },
}
example = {
    "work_order_id": "WO-DYNAMIC-1",
    "status": "completed",
    "observations": ["input sentinel verified"],
    "commands_claimed": [f"cat {work / 'input.txt'}"],
    "files_claimed": [str(work / "input.txt")],
    "notes": "No acceptance decision; verification child only.",
}
prompt = (
    "You are a verification child for a hermes-dev-pipeline-kit smoke test.\n"
    "You MUST call structured_output exactly once with ALL required keys: "
    "work_order_id, status, observations, commands_claimed, files_claimed, notes.\n"
    "Do not include acceptance or policy verdict.\n"
    f"Only inspect this temp directory: {work}\n"
    "Run exactly one local read-only terminal command: cat input.txt from that directory.\n"
    "If input.txt contains codex-v09-dynamic-input, return status completed.\n"
    "Use work_order_id WO-DYNAMIC-1. Example shape: "
    + json.dumps(example, ensure_ascii=False)
    + "\n"
)
script = "\n".join(
    [
        'meta = {"name": "v09-one-child-smoke", "description": "Verify one temp file with one child", "phases": [{"title": "Verify"}]}',
        "SCHEMA = " + repr(schema),
        'phase("Verify")',
        "result = await agent("
        + repr(prompt)
        + ', {"label": "v09-dynamic-verifier", "phase": "Verify", "schema": SCHEMA, "agentType": "explore"})',
        "return result",
    ]
)

try:
    launch_raw = workflow(
        {"script": script},
        plugin_context=Context(),
        parent_agent=parent,
        user_task="v0.9 dynamic real one child smoke +2000 tokens",
        session_id="v09-dynamic-session",
    )
    (root / "launch.out").write_text(str(launch_raw), encoding="utf-8")
    record = None
    for _ in range(100):
        runs = manager.store.list_runs(limit=1)
        if runs:
            record = manager.get(runs[0]["runId"])
            if record and record.get("status") in {"completed", "failed", "stopped", "error"}:
                break
        time.sleep(1)
    if not record:
        raise RuntimeError("no run record")
    result = record.get("result")
    ok = (
        record.get("status") == "completed"
        and isinstance(result, dict)
        and result.get("work_order_id") == "WO-DYNAMIC-1"
        and result.get("status") == "completed"
        and "acceptance" not in result
    )
    summary = {
        "smoke": "plugin-v09-dynamic-real-child",
        "ok": ok,
        "backend": "hermes_dynamic_workflows",
        "backend_version": "0.1.0",
        "status": record.get("status"),
        "run_id": record.get("runId"),
        "task_id": record.get("taskId"),
        "workflow_session_id_hash": "sha256:"
        + hashlib.sha256(str(record.get("workflowSessionId") or "").encode()).hexdigest()[:16],
        "journal_path": record.get("journalFile"),
        "transcript_paths": record.get("transcriptFiles") or [],
        "output_file": record.get("outputFile") or "",
        "structured_result": result if isinstance(result, dict) else None,
        "started_at": record.get("startedAt"),
        "ended_at": record.get("finishedAt"),
        "launch_message_present": "Workflow launched in background" in str(launch_raw),
        "workflow_totals": (record.get("workflow") or {}).get("totals", {}),
        "error_classification": None,
    }
    if not ok:
        summary["error_classification"] = external_e2e.classify_external_error(str(record.get("error") or ""))
        summary["error"] = str(record.get("error") or "")[:1200]
except Exception as exc:
    summary = {
        "smoke": "plugin-v09-dynamic-real-child",
        "ok": False,
        "backend": "hermes_dynamic_workflows",
        "backend_version": "0.1.0",
        "status": "failed",
        "error_classification": external_e2e.classify_external_error(str(exc)),
        "error": f"{type(exc).__name__}: {exc}"[:1200],
    }

(root / "dynamic-result.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
public = {key: value for key, value in summary.items() if key != "error"}
if summary.get("ok"):
    public["external_result"] = "PASS_REAL_RUNTIME"
    public["external_exit_code"] = 0
else:
    public["external_result"] = external_e2e.external_result_for_classification(
        str(summary.get("error_classification") or "UNKNOWN")
    )
    public["external_exit_code"] = external_e2e.exit_code_for_external_classification(
        str(summary.get("error_classification") or "UNKNOWN")
    )
print(json.dumps(public, ensure_ascii=False, sort_keys=True))
if not summary.get("ok"):
    raise SystemExit(public["external_exit_code"])
PY

echo "smoke-plugin-v09-dynamic-real-child: PASS"
