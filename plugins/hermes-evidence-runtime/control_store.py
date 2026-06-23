"""Durable control store for Dev Pipeline run authorization.

The store is scoped to a canonical evidence run directory:

    <project>/.hermes-runs/<run-id>/control/

It provides consistency for Dev Pipeline-managed mutation paths. It is not a
cryptographic boundary against the same OS user and does not control processes
that bypass Hermes.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import pathlib
import tempfile
import time
import uuid
from typing import Any, Iterator

from . import authorization

CONTROL_DIR_MODE = 0o700
CONTROL_FILE_MODE = 0o600
LOCK_TIMEOUT_SECONDS = 10.0
STALE_LOCK_SECONDS = 30.0
RUNTIME_OWNER = "hermes-evidence-runtime"


class ControlStoreError(RuntimeError):
    """Fail-closed control artifact error."""

    def __init__(self, reason: str, detail: str = "") -> None:
        super().__init__(detail or reason)
        self.reason = reason
        self.detail = detail


def now_utc() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def control_dir(run_dir: str | pathlib.Path) -> pathlib.Path:
    return pathlib.Path(run_dir).expanduser().resolve() / "control"


def _run_id(run_dir: pathlib.Path) -> str:
    return run_dir.expanduser().resolve().name


def _set_private(path: pathlib.Path, mode: int) -> None:
    try:
        os.chmod(path, mode)
    except OSError:
        # Permission hardening is best effort across platforms.
        return


def _ensure_control_dirs(run_dir: pathlib.Path) -> pathlib.Path:
    cdir = control_dir(run_dir)
    approvals = cdir / "approvals"
    cdir.mkdir(parents=True, exist_ok=True)
    approvals.mkdir(parents=True, exist_ok=True)
    _set_private(cdir, CONTROL_DIR_MODE)
    _set_private(approvals, CONTROL_DIR_MODE)
    return cdir


def _canonical_bytes(data: dict[str, Any]) -> bytes:
    return (json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def artifact_hash(data: dict[str, Any]) -> str:
    return "sha256:" + hashlib.sha256(_canonical_bytes(data)).hexdigest()


def file_hash(path: pathlib.Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _atomic_write_bytes(path: pathlib.Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        _set_private(tmp, CONTROL_FILE_MODE)
        os.replace(tmp, path)
        _set_private(path, CONTROL_FILE_MODE)
        with contextlib.suppress(OSError):
            dir_fd = os.open(str(path.parent), os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
    finally:
        if tmp.exists():
            with contextlib.suppress(OSError):
                tmp.unlink()


def _atomic_write_json(path: pathlib.Path, data: dict[str, Any]) -> None:
    _atomic_write_bytes(path, _canonical_bytes(data))


def _load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ControlStoreError("CONTROL_ARTIFACT_MISSING", str(path)) from exc
    except json.JSONDecodeError as exc:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", f"malformed JSON: {path}") from exc
    if not isinstance(data, dict):
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", f"JSON artifact is not an object: {path}")
    return data


@contextlib.contextmanager
def control_lock(run_dir: str | pathlib.Path, timeout: float = LOCK_TIMEOUT_SECONDS) -> Iterator[None]:
    cdir = _ensure_control_dirs(pathlib.Path(run_dir))
    lock_path = cdir / ".control.lock"
    start = time.monotonic()
    while True:
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, CONTROL_FILE_MODE)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(json.dumps({"pid": os.getpid(), "created_at": now_utc()}) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            break
        except FileExistsError:
            try:
                age = time.time() - lock_path.stat().st_mtime
            except OSError:
                age = 0
            if age > STALE_LOCK_SECONDS:
                with contextlib.suppress(OSError):
                    lock_path.unlink()
                continue
            if time.monotonic() - start > timeout:
                raise ControlStoreError("CONTROL_LOCK_TIMEOUT", str(lock_path))
            time.sleep(0.05)
    try:
        yield
    finally:
        with contextlib.suppress(OSError):
            lock_path.unlink()


def initialize_control_store(run_dir: str | pathlib.Path) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    cdir = _ensure_control_dirs(run_path)
    state_path = cdir / "control-state.json"
    events_path = cdir / "events.jsonl"
    if not events_path.exists():
        _atomic_write_bytes(events_path, b"")
    if not state_path.exists():
        state = {
            "artifact_version": "1.0",
            "run_id": _run_id(run_path),
            "authorization_id": "",
            "authorization_status": "pending",
            "current_state": "unauthorized",
            "terminal": False,
            "continuation_allowed": False,
            "secondary_approvals": [],
            "updated_at": now_utc(),
            "last_event_id": "",
            "written_by": RUNTIME_OWNER,
        }
        _atomic_write_json(state_path, state)
    _set_private(events_path, CONTROL_FILE_MODE)
    return load_control_state(run_path)


def _required(data: dict[str, Any], keys: list[str], artifact: str) -> None:
    missing = [key for key in keys if key not in data]
    if missing:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", f"{artifact} missing keys: {', '.join(missing)}")


def _authorization_path(run_dir: pathlib.Path) -> pathlib.Path:
    return control_dir(run_dir) / "authorization.json"


def _authorization_hash_path(run_dir: pathlib.Path) -> pathlib.Path:
    return control_dir(run_dir) / "authorization.sha256"


def persist_authorization(run_dir: str | pathlib.Path, auth: dict[str, Any]) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    with control_lock(run_path):
        initialize_control_store(run_path)
        data = dict(auth)
        run_id = _run_id(run_path)
        if data.get("run_id") not in {None, "", run_id}:
            raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "authorization run_id mismatch")
        data.update({
            "artifact_version": "1.0",
            "authorization_version": data.get("authorization_version", "1.0"),
            "run_id": run_id,
            "updated_at": now_utc(),
            "written_by": RUNTIME_OWNER,
        })
        if "created_at" not in data:
            data["created_at"] = now_utc()
        _required(data, [
            "artifact_version",
            "run_id",
            "authorization_id",
            "goal_hash",
            "source_message_id",
            "source_session_id",
            "created_at",
            "updated_at",
            "status",
            "allowed_paths",
            "allowed_actions",
            "forbidden_actions",
            "requires_secondary_approval",
            "expires_on",
            "expired_at",
            "expiration_reason",
            "written_by",
        ], "authorization")
        auth_path = _authorization_path(run_path)
        auth_hash = artifact_hash(data)
        _atomic_write_json(auth_path, data)
        _atomic_write_bytes(_authorization_hash_path(run_path), (auth_hash + "\n").encode("utf-8"))
        state = _state_from_authorization(run_path, data, current_state="active" if data["status"] == "active" else data["status"])
        _write_control_state(run_path, state)
        _append_control_event_unlocked(run_path, {
            "event_type": "authorization_created" if data["status"] == "active" else "authorization_updated",
            "authorization_id": data["authorization_id"],
            "previous_state": "unauthorized",
            "next_state": state["current_state"],
            "artifact_reference": "control/authorization.json",
        })
        if data["status"] == "active":
            _append_control_event_unlocked(run_path, {
                "event_type": "authorization_activated",
                "authorization_id": data["authorization_id"],
                "previous_state": "authorized",
                "next_state": "active",
                "artifact_reference": "control/authorization.json",
            })
        return {
            "ok": True,
            "run_id": run_id,
            "authorization_id": data["authorization_id"],
            "authorization_path": str(auth_path),
            "authorization_hash_path": str(_authorization_hash_path(run_path)),
            "authorization_hash": auth_hash,
            "control_state_path": str(control_dir(run_path) / "control-state.json"),
        }


def load_authorization(run_dir: str | pathlib.Path) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    auth_path = _authorization_path(run_path)
    sidecar = _authorization_hash_path(run_path)
    data = _load_json(auth_path)
    expected = sidecar.read_text(encoding="utf-8").strip() if sidecar.exists() else ""
    observed = file_hash(auth_path)
    canonical_observed = artifact_hash(data)
    if expected and expected not in {observed, canonical_observed}:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "authorization hash mismatch")
    _required(data, [
        "artifact_version",
        "run_id",
        "authorization_id",
        "goal_hash",
        "source_message_id",
        "source_session_id",
        "status",
        "allowed_paths",
        "allowed_actions",
        "forbidden_actions",
        "requires_secondary_approval",
        "expires_on",
        "written_by",
    ], "authorization")
    if data["run_id"] != _run_id(run_path) or data["written_by"] != RUNTIME_OWNER:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "authorization binding mismatch")
    data["_authorization_hash"] = expected or canonical_observed
    return data


def current_authorization_hash(run_dir: str | pathlib.Path) -> str:
    return load_authorization(run_dir)["_authorization_hash"]


def _state_from_authorization(run_dir: pathlib.Path, auth: dict[str, Any], *, current_state: str) -> dict[str, Any]:
    return {
        "artifact_version": "1.0",
        "run_id": _run_id(run_dir),
        "authorization_id": auth.get("authorization_id", ""),
        "authorization_status": auth.get("status", ""),
        "current_state": current_state,
        "terminal": False,
        "continuation_allowed": auth.get("status") == "active",
        "secondary_approvals": [],
        "updated_at": now_utc(),
        "last_event_id": "",
        "written_by": RUNTIME_OWNER,
    }


def _write_control_state(run_dir: pathlib.Path, state: dict[str, Any]) -> None:
    state = dict(state)
    state["updated_at"] = now_utc()
    state["written_by"] = RUNTIME_OWNER
    _atomic_write_json(control_dir(run_dir) / "control-state.json", state)


def load_control_state(run_dir: str | pathlib.Path) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    state = _load_json(control_dir(run_path) / "control-state.json")
    _required(state, [
        "run_id",
        "authorization_status",
        "current_state",
        "terminal",
        "continuation_allowed",
        "updated_at",
        "written_by",
    ], "control-state")
    if state["run_id"] != _run_id(run_path) or state["written_by"] != RUNTIME_OWNER:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "control-state binding mismatch")
    return state


def _append_control_event_unlocked(run_dir: pathlib.Path, event: dict[str, Any]) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    cdir = _ensure_control_dirs(run_path)
    event_data = {
        "event_id": event.get("event_id") or f"EV-{uuid.uuid4()}",
        "run_id": _run_id(run_path),
        "authorization_id": event.get("authorization_id", ""),
        "event_type": event.get("event_type", ""),
        "timestamp": event.get("timestamp") or now_utc(),
        "previous_state": event.get("previous_state", ""),
        "next_state": event.get("next_state", ""),
        "artifact_reference": event.get("artifact_reference", ""),
        "written_by": RUNTIME_OWNER,
    }
    line = json.dumps(event_data, sort_keys=True, ensure_ascii=False) + "\n"
    path = cdir / "events.jsonl"
    fd = os.open(str(path), os.O_CREAT | os.O_APPEND | os.O_WRONLY, CONTROL_FILE_MODE)
    with os.fdopen(fd, "a", encoding="utf-8") as handle:
        handle.write(line)
        handle.flush()
        os.fsync(handle.fileno())
    _set_private(path, CONTROL_FILE_MODE)
    state_path = cdir / "control-state.json"
    if state_path.exists():
        state = _load_json(state_path)
        state["last_event_id"] = event_data["event_id"]
        state["updated_at"] = now_utc()
        _atomic_write_json(state_path, state)
    return event_data


def append_control_event(run_dir: str | pathlib.Path, event: dict[str, Any]) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    with control_lock(run_path):
        return _append_control_event_unlocked(run_path, event)


def persist_approval(run_dir: str | pathlib.Path, approval: dict[str, Any]) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    with control_lock(run_path):
        auth = load_authorization(run_path)
        auth_hash = auth["_authorization_hash"]
        data = dict(approval)
        data.update({
            "artifact_version": "1.0",
            "run_id": _run_id(run_path),
            "authorization_id": auth["authorization_id"],
            "authorization_hash": auth_hash,
            "written_by": RUNTIME_OWNER,
        })
        if "requested_at" not in data:
            data["requested_at"] = now_utc()
        if "approved_at" not in data:
            data["approved_at"] = None
        _required(data, [
            "artifact_version",
            "run_id",
            "approval_id",
            "authorization_id",
            "authorization_hash",
            "action",
            "target_path",
            "requested_at",
            "approved_at",
            "status",
            "source_user_message_id",
            "written_by",
        ], "approval")
        if data["status"] == "approved" and not data["approved_at"]:
            raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "approved approval requires approved_at")
        out = control_dir(run_path) / "approvals" / f"{data['approval_id']}.json"
        _atomic_write_json(out, data)
        state = load_control_state(run_path)
        approvals = [item for item in state.get("secondary_approvals", []) if item.get("approval_id") != data["approval_id"]]
        approvals.append({
            "approval_id": data["approval_id"],
            "status": data["status"],
            "action": data["action"],
            "target_path": data["target_path"],
        })
        state["secondary_approvals"] = approvals
        _write_control_state(run_path, state)
        event_type = {
            "pending": "approval_requested",
            "approved": "approval_approved",
            "denied": "approval_denied",
            "expired": "approval_expired",
        }.get(data["status"], "approval_updated")
        _append_control_event_unlocked(run_path, {
            "event_type": event_type,
            "authorization_id": auth["authorization_id"],
            "previous_state": state["current_state"],
            "next_state": state["current_state"],
            "artifact_reference": f"control/approvals/{data['approval_id']}.json",
        })
        return {
            "ok": True,
            "run_id": _run_id(run_path),
            "approval_id": data["approval_id"],
            "approval_path": str(out),
            "authorization_hash": auth_hash,
            "status": data["status"],
        }


def load_approval(run_dir: str | pathlib.Path, approval_id: str) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    if not approval_id:
        raise ControlStoreError("CONTROL_ARTIFACT_MISSING", "approval_id is required")
    data = _load_json(control_dir(run_path) / "approvals" / f"{approval_id}.json")
    auth = load_authorization(run_path)
    _required(data, [
        "artifact_version",
        "run_id",
        "approval_id",
        "authorization_id",
        "authorization_hash",
        "action",
        "target_path",
        "requested_at",
        "approved_at",
        "status",
        "source_user_message_id",
        "written_by",
    ], "approval")
    if data["written_by"] != RUNTIME_OWNER or data["run_id"] != _run_id(run_path):
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "approval binding mismatch")
    if data["authorization_id"] != auth["authorization_id"] or data["authorization_hash"] != auth["_authorization_hash"]:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "approval authorization binding mismatch")
    return data


def approve_approval(run_dir: str | pathlib.Path, approval_id: str, *, source_user_message_id: str) -> dict[str, Any]:
    approval = load_approval(run_dir, approval_id)
    approval["status"] = "approved"
    approval["approved_at"] = now_utc()
    approval["source_user_message_id"] = source_user_message_id
    return persist_approval(run_dir, approval)


def persist_terminal_verdict(run_dir: str | pathlib.Path, verdict: dict[str, Any]) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    with control_lock(run_path):
        auth = load_authorization(run_path)
        terminal = dict(verdict)
        auth_hash = auth["_authorization_hash"]
        terminal.update({
            "artifact_version": "1.0",
            "run_id": _run_id(run_path),
            "authorization_id": auth["authorization_id"],
            "authorization_hash": auth_hash,
            "terminal": True,
            "authorization_expired": True,
            "continuation_allowed": False,
            "written_by": RUNTIME_OWNER,
        })
        if "emitted_at" not in terminal:
            terminal["emitted_at"] = now_utc()
        _required(terminal, [
            "artifact_version",
            "run_id",
            "authorization_id",
            "authorization_hash",
            "verdict",
            "terminal",
            "emitted_at",
            "next_state",
            "authorization_expired",
            "continuation_allowed",
            "written_by",
        ], "terminal-verdict")
        out = control_dir(run_path) / "terminal-verdict.json"
        _atomic_write_json(out, terminal)

        updated_auth = dict(auth)
        updated_auth.pop("_authorization_hash", None)
        updated_auth["status"] = "completed" if str(terminal["verdict"]).startswith("PASS_") else "expired"
        updated_auth["expired_at"] = terminal["emitted_at"]
        updated_auth["expiration_reason"] = "terminal_verdict"
        updated_auth["updated_at"] = now_utc()
        new_hash = artifact_hash(updated_auth)
        _atomic_write_json(_authorization_path(run_path), updated_auth)
        _atomic_write_bytes(_authorization_hash_path(run_path), (new_hash + "\n").encode("utf-8"))

        state = {
            "artifact_version": "1.0",
            "run_id": _run_id(run_path),
            "authorization_id": auth["authorization_id"],
            "terminal_authorization_hash": auth_hash,
            "authorization_status": updated_auth["status"],
            "current_state": terminal["next_state"],
            "terminal": True,
            "continuation_allowed": False,
            "secondary_approvals": load_control_state(run_path).get("secondary_approvals", []),
            "updated_at": now_utc(),
            "last_event_id": "",
            "written_by": RUNTIME_OWNER,
        }
        _write_control_state(run_path, state)
        _append_control_event_unlocked(run_path, {
            "event_type": "authorization_expired",
            "authorization_id": auth["authorization_id"],
            "previous_state": "active",
            "next_state": terminal["next_state"],
            "artifact_reference": "control/authorization.json",
        })
        _append_control_event_unlocked(run_path, {
            "event_type": "terminal_verdict_emitted",
            "authorization_id": auth["authorization_id"],
            "previous_state": "active",
            "next_state": terminal["next_state"],
            "artifact_reference": "control/terminal-verdict.json",
        })
        return {
            "ok": True,
            "run_id": _run_id(run_path),
            "terminal_verdict_path": str(out),
            "terminal_verdict_hash": artifact_hash(terminal),
            "authorization_hash": new_hash,
        }


def load_terminal_verdict(run_dir: str | pathlib.Path) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    path = control_dir(run_path) / "terminal-verdict.json"
    data = _load_json(path)
    auth = load_authorization(run_path)
    _required(data, [
        "artifact_version",
        "run_id",
        "authorization_id",
        "authorization_hash",
        "verdict",
        "terminal",
        "emitted_at",
        "next_state",
        "authorization_expired",
        "continuation_allowed",
        "written_by",
    ], "terminal-verdict")
    if data["run_id"] != _run_id(run_path) or data["written_by"] != RUNTIME_OWNER:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "terminal run binding mismatch")
    if data["authorization_id"] != auth["authorization_id"]:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "terminal authorization id mismatch")
    # The terminal binds the pre-expiration authorization hash; validate that it
    # matches the persisted terminal control-state hash when that state exists.
    if not str(data["authorization_hash"]).startswith("sha256:"):
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "terminal authorization hash missing")
    try:
        state = load_control_state(run_path)
    except ControlStoreError:
        state = {}
    recorded_hash = state.get("terminal_authorization_hash")
    if recorded_hash and recorded_hash != data["authorization_hash"]:
        raise ControlStoreError("CONTROL_ARTIFACT_INVALID", "terminal authorization hash mismatch")
    return data


def recover_control_state(run_dir: str | pathlib.Path) -> dict[str, Any]:
    run_path = pathlib.Path(run_dir).expanduser().resolve()
    try:
        terminal_path = control_dir(run_path) / "terminal-verdict.json"
        if terminal_path.exists():
            terminal = load_terminal_verdict(run_path)
            state: dict[str, Any]
            try:
                state = load_control_state(run_path)
            except ControlStoreError:
                state = {
                    "run_id": _run_id(run_path),
                    "authorization_id": terminal["authorization_id"],
                    "authorization_status": "expired",
                    "current_state": terminal["next_state"],
                    "terminal": True,
                    "continuation_allowed": False,
                    "secondary_approvals": [],
                    "updated_at": now_utc(),
                    "last_event_id": "",
                    "written_by": RUNTIME_OWNER,
                }
            return {
                "ok": True,
                "state": state,
                "authorization": load_authorization(run_path),
                "terminal": terminal,
                "mutation_allowed": False,
                "reason": "terminal_verdict_exists",
            }
        auth = load_authorization(run_path)
        state = load_control_state(run_path)
        append_control_event(run_path, {
            "event_type": "recovery_loaded",
            "authorization_id": auth["authorization_id"],
            "previous_state": state["current_state"],
            "next_state": state["current_state"],
            "artifact_reference": "control/control-state.json",
        })
        return {
            "ok": True,
            "state": state,
            "authorization": auth,
            "terminal": None,
            "mutation_allowed": auth.get("status") == "active",
            "reason": "active_authorization" if auth.get("status") == "active" else "authorization_not_active",
        }
    except ControlStoreError as exc:
        with contextlib.suppress(Exception):
            append_control_event(run_path, {
                "event_type": "recovery_blocked",
                "authorization_id": "",
                "previous_state": "",
                "next_state": "blocked",
                "artifact_reference": str(exc),
            })
        return {
            "ok": False,
            "state": None,
            "authorization": None,
            "terminal": None,
            "mutation_allowed": False,
            "reason": exc.reason,
            "detail": exc.detail,
        }


def is_control_path(run_dir: str | pathlib.Path, target_path: str | pathlib.Path) -> bool:
    cdir = control_dir(run_dir)
    target = pathlib.Path(target_path).expanduser().resolve()
    try:
        target.relative_to(cdir)
        return True
    except ValueError:
        return False
