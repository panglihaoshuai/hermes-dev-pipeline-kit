#!/usr/bin/env bash
# smoke-worker-dry-run-disabled.sh — Verify worker dry-run wrapper skips real invocation by default.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/hermes-evidence-runtime"
TMP_ROOT="$(mktemp -d /tmp/hermes-worker-dry-run-disabled.XXXXXX)"

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
    result = call_json(
        tools.evidence_invoke_worker_dry_run,
        {
            "worker": worker,
            "out_dir": str(out_dir),
            "timeout_seconds": 15,
            "allow_real_invocation": False,
        },
    )
    if not result.get("ok"):
        raise AssertionError(f"dry-run wrapper failed for {worker}: {result}")
    if result.get("real_invocation") is not False:
        raise AssertionError(f"real invocation should be false for {worker}: {result}")
    if not result.get("skipped_reason"):
        raise AssertionError(f"skipped_reason missing for {worker}: {result}")
    for name in ("raw.txt", "structured.json", "invocation.json"):
        path = out_dir / name
        if not path.is_file() or path.stat().st_size == 0:
            raise AssertionError(f"missing {name} for {worker}")
    invocation = json.loads((out_dir / "invocation.json").read_text(encoding="utf-8"))
    structured = json.loads((out_dir / "structured.json").read_text(encoding="utf-8"))
    if invocation.get("real_invocation") is not False:
        raise AssertionError(f"invocation truth mismatch for {worker}")
    if structured.get("real_invocation") is not False:
        raise AssertionError(f"structured truth mismatch for {worker}")

print(json.dumps({
    "smoke": "worker-dry-run-disabled",
    "ok": True,
    "workers": ["claude-code", "codex", "opencode", "raw"],
    "real_invocation": False,
}, ensure_ascii=False, sort_keys=True))
PY

echo "smoke-worker-dry-run-disabled: PASS"
