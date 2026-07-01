"""Read-only capability detection shared by integration adapters."""

from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import subprocess
from typing import Any


def read_plugin_yaml(plugin_dir: pathlib.Path) -> dict[str, Any]:
    path = plugin_dir / "plugin.yaml"
    if not path.is_file():
        return {}
    data: dict[str, Any] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if ":" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key in {"name", "version", "description"} and value:
            data[key] = value
    return data


def importable(module: str, extra_path: str | None = None) -> bool:
    if extra_path:
        candidate = pathlib.Path(extra_path).expanduser().resolve()
        if (candidate / module.replace(".", "/")).exists() or (candidate / "__init__.py").is_file():
            return True
    return importlib.util.find_spec(module) is not None


def hermes_plugin_status(name: str, hermes_home: str | None = None) -> dict[str, Any]:
    env = os.environ.copy()
    if hermes_home:
        env["HERMES_HOME"] = str(pathlib.Path(hermes_home).expanduser())
    try:
        completed = subprocess.run(
            ["hermes", "plugins", "list", "--json"],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "discovered": False,
            "enabled": False,
            "callable": False,
            "version": "",
            "error": f"{type(exc).__name__}: {exc}",
        }
    try:
        entries = json.loads(completed.stdout or "[]")
    except json.JSONDecodeError:
        entries = []
    for entry in entries if isinstance(entries, list) else []:
        if isinstance(entry, dict) and entry.get("name") == name:
            return {
                "discovered": True,
                "enabled": entry.get("status") == "enabled",
                "callable": entry.get("status") == "enabled",
                "version": str(entry.get("version") or ""),
                "error": completed.stderr.strip(),
            }
    return {
        "discovered": False,
        "enabled": False,
        "callable": False,
        "version": "",
        "error": completed.stderr.strip(),
    }
