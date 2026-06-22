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
PLUGIN_VERSION = "0.8.0"


def _candidate_script_dirs() -> list[pathlib.Path]:
    candidates: list[pathlib.Path] = []

    env_root = os.environ.get("HERMES_DEV_PIPELINE_KIT_ROOT")
    if env_root:
        candidates.append(pathlib.Path(env_root).expanduser().resolve() / "scripts")

    if len(PLUGIN_DIR.parents) > 1:
        candidates.append(PLUGIN_DIR.parents[1] / "scripts")

    cwd = pathlib.Path.cwd().resolve()
    candidates.append(cwd / "scripts")
    for parent in cwd.parents:
        candidates.append(parent / "scripts")

    hermes_home = pathlib.Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser().resolve()
    candidates.append(
        hermes_home
        / "skills"
        / "software-development"
        / "dev-pipeline-orchestrator"
        / "bin"
    )

    unique: list[pathlib.Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key not in seen:
            seen.add(key)
            unique.append(candidate)
    return unique


def _default_scripts_dir() -> pathlib.Path:
    for candidate in _candidate_script_dirs():
        if (candidate / "run-init.sh").is_file() or (candidate / "doctor.sh").is_file():
            return candidate
    if len(PLUGIN_DIR.parents) > 1:
        return PLUGIN_DIR.parents[1] / "scripts"
    return PLUGIN_DIR / "scripts"


SCRIPTS_DIR = _default_scripts_dir()
KIT_ROOT = SCRIPTS_DIR.parent


class WrapperError(ValueError):
    """Raised for invalid wrapper inputs."""


def _as_path(value: Any, field: str) -> pathlib.Path:
    if not isinstance(value, str) or not value.strip():
        raise WrapperError(f"{field} must be a non-empty string")
    return pathlib.Path(value).expanduser().resolve()


def _require_script(name: str) -> pathlib.Path:
    checked = []
    for scripts_dir in _candidate_script_dirs():
        path = scripts_dir / name
        checked.append(str(path))
        if path.is_file():
            return path
    raise WrapperError(f"required script not found: {name}; checked: {', '.join(checked)}")


def _kit_root_for_script(script: pathlib.Path) -> pathlib.Path:
    if script.parent.name in {"scripts", "bin"}:
        return script.parent.parent
    return KIT_ROOT


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


def _read_jsonl(path: pathlib.Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    records: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        data = json.loads(line)
        if not isinstance(data, dict):
            raise WrapperError(f"JSONL record is not an object: {path}")
        records.append(data)
    return records


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


def _ensure_run_dir(run_dir: pathlib.Path) -> None:
    if not run_dir.is_dir():
        raise WrapperError(f"run_dir not found: {run_dir}")
    _project_from_run_dir(run_dir)
    if not (run_dir / "run-manifest.json").is_file():
        raise WrapperError("run_dir missing run-manifest.json")
    if not (run_dir / "classification.json").is_file():
        raise WrapperError("run_dir missing classification.json")
    if not (run_dir / "state.json").is_file():
        raise WrapperError("run_dir missing state.json")


def _resolve_under(root: pathlib.Path, value: Any, field: str) -> pathlib.Path:
    path = _as_path(value, field)
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise WrapperError(f"{field} must stay inside {root}") from exc
    return path


def _rel_to_run(run_dir: pathlib.Path, path: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(run_dir))
    except ValueError as exc:
        raise WrapperError(f"path escapes run_dir: {path}") from exc


def _now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _append_event(run_dir: pathlib.Path, event_type: str, actor: str, state_after: str, artifacts: list[str]) -> None:
    script = _require_script("append-event.sh")
    args = [
        "bash",
        str(script),
        "--run-dir",
        str(run_dir),
        "--event-type",
        event_type,
        "--actor",
        actor,
        "--state-after",
        state_after,
    ]
    for artifact in artifacts:
        args.extend(["--artifact", artifact])
    result = _run_script(args, cwd=_kit_root_for_script(script))
    if result["exit_code"] != 0:
        raise WrapperError(f"append-event failed for {event_type}: {result['stderr'].strip()}")


def _load_manifest(run_dir: pathlib.Path) -> dict[str, Any]:
    data = _read_json(run_dir / "run-manifest.json")
    if not data:
        raise WrapperError("invalid run-manifest.json")
    run_id = data.get("run_id")
    if run_id != run_dir.name:
        raise WrapperError(f"run_id mismatch: manifest={run_id!r} run_dir={run_dir.name!r}")
    return data


def _load_classification(run_dir: pathlib.Path) -> dict[str, Any]:
    data = _read_json(run_dir / "classification.json")
    if not data:
        raise WrapperError("invalid classification.json")
    if data.get("scale") not in {"S", "M", "L"}:
        raise WrapperError("classification.scale must be S, M, or L")
    return data


def _load_work_order_ids(run_dir: pathlib.Path) -> set[str]:
    ids: set[str] = set()
    for path in sorted((run_dir / "work-orders").glob("*.json")):
        data = _read_json(path)
        if data and isinstance(data.get("id"), str):
            ids.add(data["id"])
    if not ids:
        raise WrapperError("no work order JSON files found")
    return ids


def _validate_no_worker_acceptance(data: dict[str, Any], path: pathlib.Path) -> None:
    acceptance = data.get("acceptance")
    if isinstance(acceptance, dict) and acceptance.get("complete") is True:
        raise WrapperError(f"worker result attempted acceptance.complete=true: {path}")


def _worker_result_paths(run_dir: pathlib.Path) -> list[pathlib.Path]:
    paths = sorted((run_dir / "raw" / "worker").glob("*.worker-result.json"))
    single = run_dir / "raw" / "worker-result.json"
    if single.is_file():
        paths.append(single)
    unique: list[pathlib.Path] = []
    seen: set[str] = set()
    for path in paths:
        key = str(path.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def _validate_command_records(run_dir: pathlib.Path) -> tuple[list[dict[str, Any]], int | None, int | None]:
    command_log = run_dir / "raw" / "command-log.jsonl"
    records = _read_jsonl(command_log)
    if not records:
        raise WrapperError("raw/command-log.jsonl is missing or empty")
    red = [item for item in records if str(item.get("phase", "")).upper() == "RED"]
    green = [item for item in records if str(item.get("phase", "")).upper() == "GREEN"]
    if not red:
        raise WrapperError("TDD RED command missing")
    if not green:
        raise WrapperError("TDD GREEN command missing")
    red_exit = red[0].get("exit_code")
    green_exit = green[-1].get("exit_code")
    if not isinstance(red_exit, int) or red_exit == 0:
        raise WrapperError("TDD RED exit_code must be non-zero")
    if green_exit != 0:
        raise WrapperError("TDD GREEN exit_code must be 0")
    for item in records:
        for key in ("command_record_path", "stdout_path", "stderr_path"):
            rel_path = item.get(key)
            if not isinstance(rel_path, str) or not rel_path:
                raise WrapperError(f"command log record missing {key}")
            target = (run_dir / rel_path).resolve()
            try:
                target.relative_to(run_dir)
            except ValueError as exc:
                raise WrapperError(f"command artifact escapes run_dir: {rel_path}") from exc
            if not target.is_file():
                raise WrapperError(f"command artifact missing: {rel_path}")
    return records, red_exit, green_exit


def _validate_controlled_worker_result(run_dir: pathlib.Path, work_order_ids: set[str]) -> dict[str, Any]:
    path = run_dir / "raw" / "controlled-worker-result.json"
    alias_path = run_dir / "raw" / "claudecode-result.json"
    data = _read_json(path)
    if not data:
        data = _read_json(alias_path)
        if not data:
            raise WrapperError("raw/controlled-worker-result.json is required")
        if data.get("legacy_compatibility_alias") != "not real ClaudeCode evidence":
            raise WrapperError("raw/claudecode-result.json alias must be labeled as legacy compatibility alias")
    if "acceptance" in data:
        raise WrapperError("controlled-worker-result.json must not contain acceptance")
    required = {
        "work_order_id",
        "status",
        "required_matt_skill",
        "files_touched",
        "commands_run",
        "matt_evidence",
        "worker_type",
        "capture_mode",
        "real_worker_capture",
    }
    missing = sorted(required - set(data))
    if missing:
        raise WrapperError("controlled-worker-result.json missing fields: " + ", ".join(missing))
    if data.get("work_order_id") not in work_order_ids:
        raise WrapperError("controlled-worker-result work_order_id has no matching work order")
    if data.get("worker_type") != "controlled_fixture":
        raise WrapperError("controlled-worker-result worker_type must be controlled_fixture")
    if data.get("capture_mode") != "raw_fixture":
        raise WrapperError("controlled-worker-result capture_mode must be raw_fixture")
    if data.get("real_worker_capture") is not False:
        raise WrapperError("controlled-worker-result real_worker_capture must be false")
    if alias_path.exists():
        alias_data = _read_json(alias_path)
        if alias_data.get("legacy_compatibility_alias") != "not real ClaudeCode evidence":
            raise WrapperError("raw/claudecode-result.json alias must say not real ClaudeCode evidence")
    if data.get("required_matt_skill") == "tdd":
        matt = data.get("matt_evidence")
        if not isinstance(matt, dict):
            raise WrapperError("matt_evidence must be an object")
        if not isinstance(matt.get("red_exit_code"), int) or matt.get("red_exit_code") == 0:
            raise WrapperError("matt_evidence.red_exit_code must be non-zero for TDD")
        if matt.get("green_exit_code") != 0:
            raise WrapperError("matt_evidence.green_exit_code must be 0 for TDD")
    return data


def _validate_worker_results(run_dir: pathlib.Path, work_order_ids: set[str]) -> list[dict[str, Any]]:
    paths = _worker_result_paths(run_dir)
    if not paths:
        raise WrapperError("at least one worker result is required before run-state generation")
    results: list[dict[str, Any]] = []
    for path in paths:
        data = _read_json(path)
        if not data:
            raise WrapperError(f"invalid worker result JSON: {path}")
        _validate_no_worker_acceptance(data, path)
        work_order_id = data.get("work_order_id")
        if work_order_id not in work_order_ids:
            raise WrapperError(f"worker result work_order_id has no matching work order: {work_order_id}")
        if data.get("review", {}).get("verdict") == "PASS" and data.get("deferred", {}).get("is_deferred"):
            raise WrapperError(f"deferred worker result must not claim PASS: {path}")
        results.append(data)
    return results


def _copy_hook_log_if_requested(run_dir: pathlib.Path, payload: dict[str, Any]) -> pathlib.Path:
    raw_value = payload.get("hook_log_path")
    target = run_dir / "raw" / "hook-events.jsonl"
    if raw_value:
        source = _as_path(raw_value, "hook_log_path")
        if source.is_dir():
            source = source / "hook-events.jsonl"
        if not source.is_file():
            raise WrapperError(f"hook_log_path not found: {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    return target


def _validate_hook_events(run_dir: pathlib.Path, payload: dict[str, Any]) -> dict[str, Any]:
    path = _copy_hook_log_if_requested(run_dir, payload)
    records = _read_jsonl(path)
    if not records:
        raise WrapperError("raw/hook-events.jsonl is required")
    real_hooks: set[str] = set()
    simulated_hooks: set[str] = set()
    for record in records:
        hook_name = str(record.get("hook_name", "") or "")
        capture_mode = record.get("capture_mode")
        provenance = record.get("provenance") if isinstance(record.get("provenance"), dict) else {}
        if capture_mode == "real_runtime":
            if provenance.get("source") != "Hermes hook callback":
                raise WrapperError("real_runtime hook must come from Hermes hook callback provenance")
            if provenance.get("log_only") is not True:
                raise WrapperError("hook provenance must be log_only=true")
            real_hooks.add(hook_name)
        else:
            simulated_hooks.add(hook_name)
    missing = sorted({"pre_tool_call", "post_tool_call"} - real_hooks)
    if missing:
        raise WrapperError("missing required real_runtime hook evidence: " + ", ".join(missing))
    return {
        "source": "raw/hook-events.jsonl",
        "real_runtime_hooks": sorted(real_hooks),
        "simulated_or_unproven_hooks": sorted(simulated_hooks | ({"on_session_start", "on_session_end", "on_session_finalize", "subagent_stop"} - real_hooks)),
    }


def _validate_v08_preconditions(run_dir: pathlib.Path, payload: dict[str, Any]) -> dict[str, Any]:
    _ensure_run_dir(run_dir)
    manifest = _load_manifest(run_dir)
    classification = _load_classification(run_dir)
    work_order_ids = _load_work_order_ids(run_dir)
    commands, red_exit, green_exit = _validate_command_records(run_dir)
    controlled_worker_result = _validate_controlled_worker_result(run_dir, work_order_ids)
    worker_results = _validate_worker_results(run_dir, work_order_ids)
    hook_evidence = _validate_hook_events(run_dir, payload)

    if classification.get("scale") not in {"M", "L"}:
        raise WrapperError("v0.8 C dry-run requires M or L classification")

    return {
        "manifest": manifest,
        "classification": classification,
        "work_order_ids": sorted(work_order_ids),
        "command_count": len(commands),
        "red_exit_code": red_exit,
        "green_exit_code": green_exit,
        "controlled_worker_result": controlled_worker_result,
        "worker_count": len(worker_results),
        "hook_evidence": hook_evidence,
    }


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
    kit_root = _kit_root_for_script(script)
    result = _run_script(["bash", str(script)], cwd=kit_root, env=env)
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
            "hook_source_smoke": (kit_root / "scripts" / "smoke" / "smoke-plugin-hooks-source.sh").is_file(),
            "hook_discovery_smoke": (
                kit_root / "scripts" / "smoke" / "smoke-plugin-hooks-discovery-temp-home.sh"
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

    result = _run_script(args, cwd=_kit_root_for_script(script))
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

    result = _run_script(args, cwd=_kit_root_for_script(script))
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


def evidence_record_command(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    _ensure_run_dir(run_dir)
    project_root = _project_from_run_dir(run_dir)
    work_dir = _resolve_under(project_root, payload.get("work_dir"), "work_dir")
    command = payload.get("command")
    if not isinstance(command, str) or not command.strip():
        raise WrapperError("command must be a non-empty string")
    phase = str(payload.get("phase", "") or "").upper()
    if phase not in {"RED", "GREEN", "VERIFY"}:
        raise WrapperError("phase must be RED, GREEN, or VERIFY")
    step_id = str(payload.get("step_id", "") or f"{phase.lower()}-command")

    script = _require_script("record-command.sh")
    before_count = len(_read_jsonl(run_dir / "raw" / "command-log.jsonl"))
    result = _run_script(
        [
            "bash",
            str(script),
            "--run-dir",
            str(run_dir),
            "--cwd",
            str(work_dir),
            "--step-id",
            step_id,
            "--phase",
            phase,
            "--",
            "bash",
            "-lc",
            command,
        ],
        cwd=_kit_root_for_script(script),
    )
    records = _read_jsonl(run_dir / "raw" / "command-log.jsonl")
    recorded = len(records) == before_count + 1
    latest = records[-1] if records else {}
    command_record_rel = str(latest.get("command_record_path", "") or "")
    stdout_rel = str(latest.get("stdout_path", "") or "")
    stderr_rel = str(latest.get("stderr_path", "") or "")

    ok = recorded and (phase == "RED" or result["exit_code"] == 0)

    return {
        "ok": ok,
        "script": "scripts/record-command.sh",
        "run_dir": str(run_dir),
        "phase": phase,
        "step_id": step_id,
        "command": command,
        "exit_code": result["exit_code"],
        "command_exit_code": result["exit_code"],
        "command_log_path": str(run_dir / "raw" / "command-log.jsonl"),
        "command_record_path": str(run_dir / command_record_rel) if command_record_rel else "",
        "stdout_path": str(run_dir / stdout_rel) if stdout_rel else "",
        "stderr_path": str(run_dir / stderr_rel) if stderr_rel else "",
        "harness_stdout_path": result["stdout_path"],
        "harness_stderr_path": result["stderr_path"],
    }


def evidence_generate_run_state(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    preflight = _validate_v08_preconditions(run_dir, payload)

    script = _require_script("generate-run-state.sh")
    result = _run_script(["bash", str(script), str(run_dir)], cwd=_kit_root_for_script(script))
    run_state_path = run_dir / "generated" / "run-state.json"
    if result["exit_code"] != 0 or not run_state_path.is_file():
        return {
            "ok": False,
            "script": "scripts/generate-run-state.sh",
            "exit_code": result["exit_code"],
            "run_state_path": str(run_state_path),
            "stdout_path": result["stdout_path"],
            "stderr_path": result["stderr_path"],
        }

    state = _read_json(run_state_path)
    if not state:
        raise WrapperError("generated run-state is not valid JSON")

    sources = set(state.get("provenance", {}).get("source_files") or [])
    sources.update({
        "run-manifest.json",
        "classification.json",
        "raw/command-log.jsonl",
        "raw/controlled-worker-result.json",
        "raw/claudecode-result.json",
        "raw/hook-events.jsonl",
    })
    for path in _worker_result_paths(run_dir):
        sources.add(_rel_to_run(run_dir, path))
    for path in sorted((run_dir / "work-orders").glob("*.json")):
        sources.add(_rel_to_run(run_dir, path))
    for item in _read_jsonl(run_dir / "raw" / "command-log.jsonl"):
        for key in ("command_record_path", "stdout_path", "stderr_path"):
            value = item.get(key)
            if isinstance(value, str) and value:
                sources.add(value)

    for rel_path in sorted(sources):
        target = run_dir / rel_path
        if not target.is_file():
            raise WrapperError(f"run-state source file missing: {rel_path}")

    state["runtime_integration"] = {
        "version": "0.8.0",
        "class": "C",
        "mode": "dry_run",
        "verdict": "PASS_C_DRY_RUN_CONTROLLED_WORKER",
        "controlled_worker": True,
        "real_worker_capture": False,
        "enforcement": False,
        "approval_artifact_is_user_approval": False,
    }
    state["evidence_ownership"] = {
        "run_manifest": "Hermes harness",
        "classification": "Hermes harness",
        "work_order": "Hermes",
        "command_log": "evidence_record_command",
        "hook_events": "Hermes hook callback via log-only plugin",
        "worker_result": "controlled worker fixture",
        "generated_run_state": "evidence_generate_run_state",
        "policy_result": "evidence_policy_check",
        "final_report": "evidence_final_report",
        "approval_inbox": "evidence_approval_inbox",
    }
    state["hook_evidence"] = preflight["hook_evidence"]
    state["controlled_worker_evidence"] = {
        "result_path": "raw/controlled-worker-result.json",
        "legacy_compatibility_alias": "raw/claudecode-result.json",
        "worker_count": preflight["worker_count"],
        "real_worker_capture": False,
        "claim_boundary": "controlled worker result only; not official ClaudeCode/Codex/OpenCode capture",
    }
    state.setdefault("raw_evidence", {})
    state["raw_evidence"]["controlled_worker_result"] = "raw/controlled-worker-result.json"
    state["raw_evidence"]["legacy_claudecode_alias"] = "raw/claudecode-result.json"
    state["raw_evidence"]["legacy_claudecode_alias_note"] = "legacy compatibility alias; not real ClaudeCode evidence"
    state["artifact_chain"] = {
        "run_manifest": "run-manifest.json",
        "classification": "classification.json",
        "work_orders": [f"work-orders/{item}.json" for item in preflight["work_order_ids"]],
        "hook_events": "raw/hook-events.jsonl",
        "command_log": "raw/command-log.jsonl",
        "controlled_worker_result": "raw/controlled-worker-result.json",
        "legacy_compatibility_alias": "raw/claudecode-result.json",
        "worker_results": [_rel_to_run(run_dir, path) for path in _worker_result_paths(run_dir)],
        "generated_run_state": "generated/run-state.json",
        "policy_result": "generated/policy-result.json",
        "final_report": "generated/final-report.md",
        "approval_inbox": "generated/approval-inbox.json",
    }
    state["sequence_validation"] = {
        "red_exit_code": preflight["red_exit_code"],
        "green_exit_code": preflight["green_exit_code"],
        "worker_result_before_run_state": True,
        "run_state_before_policy": True,
        "policy_before_final_report": False,
        "run_state_before_approval_inbox": True,
    }
    state.setdefault("provenance", {})
    state["provenance"].update({
        "generated_by": "evidence_generate_run_state",
        "generated_at": _now_utc(),
        "generator_version": PLUGIN_VERSION,
        "source_files": sorted(sources),
    })
    _write_json(run_state_path, state)

    return {
        "ok": True,
        "script": "scripts/generate-run-state.sh",
        "run_dir": str(run_dir),
        "run_state_path": str(run_state_path),
        "exit_code": result["exit_code"],
        "verdict": state["runtime_integration"]["verdict"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    }


def evidence_policy_check(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    _ensure_run_dir(run_dir)
    run_state_path = run_dir / "generated" / "run-state.json"
    if not run_state_path.is_file():
        raise WrapperError("generated/run-state.json is required before policy-check")

    script = _require_script("policy-check.sh")
    result = _run_script(
        ["bash", str(script), "--run-state", str(run_state_path)],
        cwd=_kit_root_for_script(script),
    )
    verdict = _extract_overall(result["stdout"])
    policy_result_path = run_dir / "generated" / "policy-result.json"
    return {
        "ok": result["exit_code"] == 0,
        "script": "scripts/policy-check.sh",
        "run_dir": str(run_dir),
        "verdict": verdict,
        "policy_result_path": str(policy_result_path),
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    }


def evidence_final_report(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    _ensure_run_dir(run_dir)
    run_state_path = run_dir / "generated" / "run-state.json"
    policy_result_path = run_dir / "generated" / "policy-result.json"
    if not run_state_path.is_file():
        raise WrapperError("generated/run-state.json is required before final-report")
    if not policy_result_path.is_file():
        raise WrapperError("generated/policy-result.json is required before final-report")

    script = _require_script("final-report.sh")
    result = _run_script(["bash", str(script), str(run_state_path)], cwd=_kit_root_for_script(script))
    final_report_path = run_dir / "generated" / "final-report.md"
    return {
        "ok": result["exit_code"] == 0 and final_report_path.is_file(),
        "script": "scripts/final-report.sh",
        "run_dir": str(run_dir),
        "verdict": "PASS" if result["exit_code"] == 0 else "FAIL",
        "run_state_path": str(run_state_path),
        "policy_result_path": str(policy_result_path),
        "final_report_path": str(final_report_path),
        "exit_code": result["exit_code"],
        "stdout_path": result["stdout_path"],
        "stderr_path": result["stderr_path"],
    }


def evidence_approval_inbox(payload: dict[str, Any]) -> dict[str, Any]:
    run_dir = _as_path(payload.get("run_dir"), "run_dir")
    _ensure_run_dir(run_dir)
    run_state_path = run_dir / "generated" / "run-state.json"
    if not run_state_path.is_file():
        raise WrapperError("generated/run-state.json is required before approval inbox")
    if payload.get("approved") is True or str(payload.get("status", "")).lower() in {"approved", "granted"}:
        raise WrapperError("approval inbox tool cannot record pre-approved approval")
    for item in payload.get("items") or []:
        if isinstance(item, dict) and (item.get("approved") is True or str(item.get("status", "")).lower() in {"approved", "granted"}):
            raise WrapperError("approval inbox item cannot be pre-approved")

    manifest = _load_manifest(run_dir)
    policy_result_path = run_dir / "generated" / "policy-result.json"
    final_report_path = run_dir / "generated" / "final-report.md"
    refs = ["generated/run-state.json"]
    if policy_result_path.is_file():
        refs.append("generated/policy-result.json")
    if final_report_path.is_file():
        refs.append("generated/final-report.md")

    inbox = {
        "schema_version": "0.8.0",
        "run_id": manifest["run_id"],
        "status": "pending",
        "generated_by": "evidence_approval_inbox",
        "generated_at": _now_utc(),
        "items": [
            {
                "id": "A1",
                "action": "local_checkpoint_commit",
                "status": "pending",
                "approved": False,
                "approval_required": True,
                "reason": "Commit is a user approval gate; evidence artifacts are not user approval.",
                "artifact_refs": refs,
            }
        ],
        "provenance": {
            "source_files": refs,
            "approval_artifact_is_user_approval": False,
        },
    }
    out_path = run_dir / "generated" / "approval-inbox.json"
    _write_json(out_path, inbox)
    _append_event(run_dir, "APPROVAL_RECORDED", "harness", "APPROVAL_PENDING", ["generated/approval-inbox.json"])

    return {
        "ok": True,
        "script": "plugin:evidence_approval_inbox",
        "run_dir": str(run_dir),
        "approval_inbox_path": str(out_path),
        "state": "APPROVAL_PENDING",
        "status": "pending",
        "exit_code": 0,
    }


def evidence_validate_worker_result(payload: dict[str, Any]) -> dict[str, Any]:
    worker_result_path = _as_path(payload.get("worker_result_path"), "worker_result_path")
    script = _require_script("validate-worker-result.sh")
    result = _run_script(
        ["bash", str(script), "--worker-result", str(worker_result_path)],
        cwd=_kit_root_for_script(script),
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
    result = _run_script(args, cwd=_kit_root_for_script(script))
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

    result = _run_script(args, cwd=_kit_root_for_script(script))
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

    result = _run_script(args, cwd=_kit_root_for_script(script))
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
