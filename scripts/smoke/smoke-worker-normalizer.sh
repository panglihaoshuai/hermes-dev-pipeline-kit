#!/usr/bin/env bash
# smoke-worker-normalizer.sh — Source-only smoke for v0.5.4 worker normalizer.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="$(mktemp -d /tmp/hermes-worker-normalizer.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

python3 -m py_compile "$PLUGIN_DIR"/*.py

REPO_ROOT="$REPO_ROOT" PLUGIN_DIR="$PLUGIN_DIR" TMP_ROOT="$TMP_ROOT" python3 <<'PY'
import importlib
import importlib.util
import json
import os
import pathlib
import subprocess
import sys

repo_root = pathlib.Path(os.environ["REPO_ROOT"]).resolve()
plugin_dir = pathlib.Path(os.environ["PLUGIN_DIR"]).resolve()
tmp_root = pathlib.Path(os.environ["TMP_ROOT"]).resolve()

spec = importlib.util.spec_from_file_location(
    "hermes_evidence_runtime",
    plugin_dir / "__init__.py",
    submodule_search_locations=[str(plugin_dir)],
)
if spec is None or spec.loader is None:
    raise SystemExit("failed to load plugin spec")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
tools = importlib.import_module("hermes_evidence_runtime.tools")


def call_json(fn, payload):
    raw = fn(json.dumps(payload))
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise AssertionError(f"tool did not return JSON object: {raw}")
    return data


for worker in ("claude-code", "codex", "opencode", "raw"):
    out_dir = tmp_root / worker
    subprocess.run(
        [
            "bash",
            str(repo_root / "scripts" / "simulate-worker-output.sh"),
            "--worker",
            worker,
            "--out-dir",
            str(out_dir),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    worker_result_path = out_dir / "worker-result.json"
    normalized = call_json(
        tools.evidence_normalize_worker_result,
        {
            "worker": worker,
            "worker_skill": f"simulated/{worker}",
            "work_order_id": f"WO-{worker}",
            "status": "completed",
            "result_type": "implementation",
            "raw_output_path": str(out_dir / "raw.txt"),
            "structured_output_path": str(out_dir / "structured.json"),
            "out_path": str(worker_result_path),
        },
    )
    if not normalized.get("ok"):
        raise AssertionError(f"normalizer failed for {worker}: {normalized}")

    worker_result = json.loads(worker_result_path.read_text(encoding="utf-8"))
    if "acceptance" in worker_result:
        raise AssertionError(f"worker result must not contain acceptance: {worker}")
    if worker == "raw":
        if worker_result.get("worker") != "unknown":
            raise AssertionError("raw adapter must map to worker=unknown")
        if worker_result.get("worker_adapter") != "raw":
            raise AssertionError("raw adapter marker missing")
    else:
        if worker_result.get("worker") != worker:
            raise AssertionError(f"worker mismatch for {worker}")
    if worker_result.get("schema_version") != "0.5.3":
        raise AssertionError("schema version mismatch")
    if worker_result.get("normalizer", {}).get("version") != "0.5.4":
        raise AssertionError("normalizer version missing")

    validate = call_json(
        tools.evidence_validate_worker_result,
        {"worker_result_path": str(worker_result_path)},
    )
    if not validate.get("ok") or validate.get("verdict") != "PASS":
        raise AssertionError(f"validate failed for {worker}: {validate}")

print(json.dumps({
    "smoke": "worker-normalizer",
    "ok": True,
    "workers": ["claude-code", "codex", "opencode", "raw"],
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-worker-normalizer: PASS"
