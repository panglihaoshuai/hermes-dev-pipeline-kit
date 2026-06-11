"""Thin wrappers around hermes-dev-pipeline-kit shell harness scripts."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
from typing import Any


PLUGIN_DIR = pathlib.Path(__file__).resolve().parent
KIT_ROOT = PLUGIN_DIR.parents[1]
SCRIPTS_DIR = KIT_ROOT / "scripts"


class WrapperError(ValueError):
    """Raised for invalid wrapper inputs."""


def _as_path(value: Any, field: str) -> pathlib.Path:
    if not isinstance(value, str) or not value.strip():
        raise WrapperError(f"{field} must be a non-empty string")
    return pathlib.Path(value).expanduser().resolve()


def _require_script(name: str) -> pathlib.Path:
    path = SCRIPTS_DIR / name
    if not path.is_file():
        raise WrapperError(f"required script not found: {path}")
    return path


def _output_dir() -> pathlib.Path:
    return pathlib.Path(tempfile.mkdtemp(prefix="hermes-evidence-runtime-")).resolve()


def _run_script(
    args: list[str],
    *,
    cwd: pathlib.Path | None = None,
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    out_dir = _output_dir()
    stdout_path = out_dir / "stdout.txt"
    stderr_path = out_dir / "stderr.txt"

    completed = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    stdout_path.write_text(completed.stdout, encoding="utf-8")
    stderr_path.write_text(completed.stderr, encoding="utf-8")

    return {
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
    }


def _read_json(path: pathlib.Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def _write_json(path: pathlib.Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _extract_overall(stdout: str) -> str:
    match = re.search(r"Overall:\s*(PASS|PARTIAL|FAIL)", stdout)
    if match:
        return match.group(1)
    return "PASS" if "final status: PASS" in stdout else "FAIL"


def _extract_json(stdout: str) -> dict[str, Any]:
    text = stdout.strip()
    if not text:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _project_from_run_dir(run_dir: pathlib.Path) -> pathlib.Path:
    if run_dir.parent.name != ".hermes-runs":
        raise WrapperError("run_dir must be inside <project>/.hermes-runs/<run-id>")
    return run_dir.parent.parent.resolve()


def _current_state(run_dir: pathlib.Path) -> str | None:
    state = _read_json(run_dir / "state.json")
    if state:
        value = state.get("current_state")
        if isinstance(value, str) and value:
            return value
    generated = _read_json(run_dir / "generated" / "run-state.json")
    if generated:
        value = generated.get("state") or generated.get("current_state")
        if isinstance(value, str) and value:
            return value
    return None


def _write_active_run(project_root: pathlib.Path, run_dir: pathlib.Path, status: str) -> None:
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    data = {
        "run_id": run_dir.name,
        "run_dir": str(run_dir),
        "project_root": str(project_root),
        "status": status,
        "updated_at": now,
        "owner": "hermes-evidence-runtime",
    }
    active_path = project_root / ".hermes-harness" / "active-run.json"
    _write_json(active_path, data)


def evidence_doctor(payload: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = payload or {}
    mode = payload.get("mode", "source")
    if mode != "source":
        raise WrapperError("evidence_doctor only supports mode=source")

    script = _require_script("doctor.sh")
    fake_home = pathlib.Path(tempfile.mkdtemp(prefix="hermes-evidence-doctor-home-")).resolve()
    env = os.environ.copy()
    env["HOME"] = str(fake_home)
    result = _run_script(["bash", str(script)], cwd=KIT_ROOT, env=env)
    verdict = _extract_overall(result["stdout"])
    shutil.rmtree(fake_home, ignore_errors=True)

    return {
        "ok": result["exit_code"] == 0,
        "verdict": verdict,
        "script": "scripts/doctor.sh",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
        "plugin_checks": {
            "hooks_module": (PLUGIN_DIR / "hooks.py").is_file(),
            "hook_source_smoke": (KIT_ROOT / "scripts" / "smoke" / "smoke-plugin-hooks-source.sh").is_file(),
            "hook_discovery_smoke": (
                KIT_ROOT / "scripts" / "smoke" / "smoke-plugin-hooks-discovery-temp-home.sh"
            ).is_file(),
            "hooks_prototype_only": True,
            "memory_provider": False,
        },
    }


def _latest_run(project_root: pathlib.Path) -> dict[str, Any] | None:
    runs_root = project_root / ".hermes-runs"
    if not runs_root.is_dir():
        return None
    run_dirs = [p for p in runs_root.iterdir() if p.is_dir()]
    if not run_dirs:
        return None
    latest = max(run_dirs, key=lambda p: p.stat().st_mtime)
    return {
        "run_id": latest.name,
        "run_dir": str(latest),
        "state": _current_state(latest),
    }


def _missing_gates(run_dir: pathlib.Path) -> list[str]:
    checks = [
        ("command-log", run_dir / "raw" / "command-log.jsonl"),
        ("run-state", run_dir / "generated" / "run-state.json"),
        ("policy-result", run_dir / "generated" / "policy-result.json"),
        ("final-report", run_dir / "generated" / "final-report.md"),
    ]
    missing = []
    for label, path in checks:
        if not path.is_file() or path.stat().st_size == 0:
            missing.append(label)
    return missing


def evidence_active_run_status(payload: dict[str, Any]) -> dict[str, Any]:
    project_root = _as_path(payload.get("project_root"), "project_root")
    active_path = project_root / ".hermes-harness" / "active-run.json"
    active_run = _read_json(active_path)
    latest_run = _latest_run(project_root)

    state = "none"
    missing: list[str] = []
    target_run_dir: pathlib.Path | None = None

    if active_run and isinstance(active_run.get("run_dir"), str):
        target_run_dir = pathlib.Path(active_run["run_dir"]).expanduser().resolve()
        if not target_run_dir.exists():
            state = "abandoned"
        else:
            missing = _missing_gates(target_run_dir)
            if (target_run_dir / "raw" / "failure-result.json").is_file():
                state = "failed"
            elif not missing:
                state = "completed"
            else:
                state = "active"
    elif latest_run:
        target_run_dir = pathlib.Path(latest_run["run_dir"])
        missing = _missing_gates(target_run_dir)
        if not missing:
            state = "completed"
        elif (target_run_dir / "raw" / "failure-result.json").is_file():
            state = "failed"
        else:
            state = "abandoned"

    return {
        "ok": True,
        "active_run": active_run,
        "state": state,
        "latest_run": latest_run,
        "missing_gates": missing,
    }


def evidence_run_init(payload: dict[str, Any]) -> dict[str, Any]:
    project_root = _as_path(payload.get("project_root"), "project_root")
    task = payload.get("task")
    if not isinstance(task, str) or not task.strip():
        raise WrapperError("task must be a non-empty string")
    scale = payload.get("scale")
    if scale not in {"S", "M", "L"}:
        raise WrapperError("scale must be one of S, M, L")
    mode = payload.get("mode")
    if mode not in {"dry_run", "plan_only", "auto_run"}:
        raise WrapperError("mode must be dry_run, plan_only, or auto_run")

    script = _require_script("run-init.sh")
    project_root.mkdir(parents=True, exist_ok=True)
    task_dir = project_root / ".hermes-harness" / "tasks"
    task_dir.mkdir(parents=True, exist_ok=True)
    task_file = task_dir / f"task-{int(time.time() * 1000)}.md"
    task_file.write_text(task.rstrip() + "\n", encoding="utf-8")

    args = [
        "bash",
        str(script),
        "--root",
        str(project_root),
        "--task-file",
        str(task_file),
        "--scale",
        scale,
        "--mode",
        mode,
        "--task-type",
        str(payload.get("task_type", "smoke")),
    ]
    if payload.get("run_id"):
        args.extend(["--run-id", str(payload["run_id"])])
    if payload.get("project"):
        args.extend(["--project", str(payload["project"])])

    result = _run_script(args, cwd=KIT_ROOT)
    run_dir_text = result["stdout"].strip().splitlines()[-1] if result["stdout"].strip() else ""
    run_dir = pathlib.Path(run_dir_text).expanduser().resolve() if run_dir_text else None
    if result["exit_code"] == 0 and run_dir and run_dir.is_dir():
        _write_active_run(project_root, run_dir, "CLASSIFIED")

    return {
        "ok": result["exit_code"] == 0,
        "run_dir": str(run_dir) if run_dir else "",
        "run_id": run_dir.name if run_dir else "",
        "state": _current_state(run_dir) if run_dir else "",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    }


def evidence_drive_s_run(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    work_dir = _as_path(payload.get("work_dir"), "work_dir")
    command = payload.get("command")
    if not isinstance(command, str) or not command.strip():
        raise WrapperError("command must be a non-empty string")

    script = _require_script("drive-s-run.sh")
    args = [
        "bash",
        str(script),
        "--run-dir",
        str(run_dir),
        "--work-dir",
        str(work_dir),
        "--command",
        command,
        "--work-order-id",
        str(payload.get("work_order_id", "WO-1")),
        "--required-matt-skill",
        str(payload.get("required_matt_skill", "tdd")),
        "--step-id",
        str(payload.get("step_id", "s-green")),
    ]
    if payload.get("red_not_applicable_reason"):
        args.extend(["--red-not-applicable-reason", str(payload["red_not_applicable_reason"])])
    for item in payload.get("files_touched") or []:
        args.extend(["--files-touched", str(item)])

    result = _run_script(args, cwd=KIT_ROOT)
    verdict = "PASS" if "final status: PASS" in result["stdout"] else "FAIL"
    run_state_path = run_dir / "generated" / "run-state.json"
    policy_result_path = run_dir / "generated" / "policy-result.json"
    final_report_path = run_dir / "generated" / "final-report.md"

    try:
        project_root = _project_from_run_dir(run_dir)
        _write_active_run(project_root, run_dir, "completed" if result["exit_code"] == 0 else "failed")
    except WrapperError:
        pass

    return {
        "ok": result["exit_code"] == 0,
        "verdict": verdict,
        "run_state_path": str(run_state_path),
        "policy_result_path": str(policy_result_path),
        "final_report_path": str(final_report_path),
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    }


def evidence_validate_worker_result(payload: dict[str, Any]) -> dict[str, Any]:
    worker_result_path = _as_path(payload.get("worker_result_path"), "worker_result_path")
    script = _require_script("validate-worker-result.sh")
    result = _run_script(
        ["bash", str(script), "--worker-result", str(worker_result_path)],
        cwd=KIT_ROOT,
    )
    parsed = _extract_json(result["stdout"])
    if not parsed:
        parsed = {
            "ok": result["exit_code"] == 0,
            "verdict": "PASS" if result["exit_code"] == 0 else "FAIL",
        }
    else:
        parsed["ok"] = bool(parsed.get("ok")) and result["exit_code"] == 0
    parsed.update({
        "script": "scripts/validate-worker-result.sh",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    })
    return parsed


def evidence_record_worker_result(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    worker_result_path = _as_path(payload.get("worker_result_path"), "worker_result_path")
    script = _require_script("record-worker-result.sh")
    args = [
        "bash",
        str(script),
        "--run-dir",
        str(run_dir),
        "--worker-result",
        str(worker_result_path),
    ]
    if payload.get("raw_output_path"):
        args.extend(["--raw-output", str(_as_path(payload.get("raw_output_path"), "raw_output_path"))])
    result = _run_script(args, cwd=KIT_ROOT)
    parsed = _extract_json(result["stdout"])
    if not parsed:
        parsed = {
            "ok": result["exit_code"] == 0,
            "verdict": "PASS" if result["exit_code"] == 0 else "FAIL",
        }
    else:
        parsed["ok"] = bool(parsed.get("ok")) and result["exit_code"] == 0
    parsed.update({
        "script": "scripts/record-worker-result.sh",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    })
    return parsed


def evidence_normalize_worker_result(payload: dict[str, Any]) -> dict[str, Any]:
    worker = payload.get("worker")
    if worker not in {"claude-code", "codex", "opencode", "raw"}:
        raise WrapperError("worker must be one of claude-code, codex, opencode, raw")
    worker_skill = payload.get("worker_skill")
    if not isinstance(worker_skill, str) or not worker_skill.strip():
        raise WrapperError("worker_skill must be a non-empty string")
    work_order_id = payload.get("work_order_id")
    if not isinstance(work_order_id, str) or not work_order_id.strip():
        raise WrapperError("work_order_id must be a non-empty string")
    status = payload.get("status")
    if status not in {"completed", "partial", "blocked", "failed", "deferred"}:
        raise WrapperError("status must be completed, partial, blocked, failed, or deferred")
    result_type = payload.get("result_type")
    if result_type not in {"implementation", "review", "diagnostic", "plan", "unknown"}:
        raise WrapperError("result_type must be implementation, review, diagnostic, plan, or unknown")

    raw_output_path = _as_path(payload.get("raw_output_path"), "raw_output_path")
    out_path = _as_path(payload.get("out_path"), "out_path")
    script = _require_script("normalize-worker-result.sh")
    args = [
        "bash",
        str(script),
        "--worker",
        str(worker),
        "--worker-skill",
        worker_skill,
        "--work-order-id",
        work_order_id,
        "--status",
        str(status),
        "--result-type",
        str(result_type),
        "--raw-output",
        str(raw_output_path),
        "--out",
        str(out_path),
    ]
    if payload.get("structured_output_path"):
        args.extend([
            "--structured-output",
            str(_as_path(payload.get("structured_output_path"), "structured_output_path")),
        ])
    if payload.get("invocation_json_path"):
        args.extend([
            "--invocation-json",
            str(_as_path(payload.get("invocation_json_path"), "invocation_json_path")),
        ])

    result = _run_script(args, cwd=KIT_ROOT)
    parsed = _extract_json(result["stdout"])
    if not parsed:
        parsed = {
            "ok": result["exit_code"] == 0,
            "verdict": "PASS" if result["exit_code"] == 0 else "FAIL",
        }
    else:
        parsed["ok"] = bool(parsed.get("ok")) and result["exit_code"] == 0
    parsed.update({
        "script": "scripts/normalize-worker-result.sh",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    })
    return parsed


def evidence_invoke_worker_dry_run(payload: dict[str, Any]) -> dict[str, Any]:
    worker = payload.get("worker")
    if worker not in {"claude-code", "codex", "opencode", "raw"}:
        raise WrapperError("worker must be one of claude-code, codex, opencode, raw")
    out_dir = _as_path(payload.get("out_dir"), "out_dir")
    timeout_seconds = payload.get("timeout_seconds", 60)
    if not isinstance(timeout_seconds, int) or timeout_seconds < 1:
        raise WrapperError("timeout_seconds must be a positive integer")
    allow_real_invocation = payload.get("allow_real_invocation", False)
    if not isinstance(allow_real_invocation, bool):
        raise WrapperError("allow_real_invocation must be boolean")

    script = _require_script("invoke-worker-dry-run.sh")
    args = [
        "bash",
        str(script),
        "--worker",
        str(worker),
        "--out-dir",
        str(out_dir),
        "--timeout-seconds",
        str(timeout_seconds),
        "--allow-real-invocation",
        "yes" if allow_real_invocation else "no",
    ]
    if payload.get("prompt_file"):
        args.extend(["--prompt-file", str(_as_path(payload.get("prompt_file"), "prompt_file"))])

    result = _run_script(args, cwd=KIT_ROOT)
    parsed = _extract_json(result["stdout"])
    if not parsed:
        parsed = {
            "ok": result["exit_code"] == 0,
            "worker": worker,
            "real_invocation": False,
            "invocation_path": str(out_dir / "invocation.json"),
            "raw_output_path": str(out_dir / "raw.txt"),
            "structured_output_path": str(out_dir / "structured.json"),
            "skipped_reason": "wrapper failed before parsing script output",
        }
    else:
        parsed["ok"] = bool(parsed.get("ok")) and result["exit_code"] == 0
    parsed.update({
        "script": "scripts/invoke-worker-dry-run.sh",
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    })
    return parsed
