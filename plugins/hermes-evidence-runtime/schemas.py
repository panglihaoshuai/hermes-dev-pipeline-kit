"""JSON schemas for hermes-evidence-runtime tool inputs."""

from __future__ import annotations

EVIDENCE_DOCTOR_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "mode": {
            "type": "string",
            "enum": ["source"],
            "default": "source",
            "description": "Only source mode is supported by the experimental plugin wrapper.",
        }
    },
}

EVIDENCE_ACTIVE_RUN_STATUS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["project_root"],
    "properties": {
        "project_root": {
            "type": "string",
            "description": "Project root containing .hermes-harness and .hermes-runs.",
        }
    },
}

EVIDENCE_RUN_INIT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["project_root", "task", "scale", "mode"],
    "properties": {
        "project_root": {"type": "string"},
        "task": {"type": "string"},
        "scale": {"type": "string", "enum": ["S", "M", "L"]},
        "mode": {"type": "string", "enum": ["dry_run", "plan_only", "auto_run"]},
        "task_type": {
            "type": "string",
            "enum": ["feature", "bugfix", "refactor", "integration", "deployment", "smoke"],
            "default": "smoke",
        },
        "run_id": {"type": "string"},
        "project": {"type": "string"},
    },
}

EVIDENCE_DRIVE_S_RUN_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir", "work_dir", "command"],
    "properties": {
        "run_dir": {"type": "string"},
        "work_dir": {"type": "string"},
        "command": {"type": "string"},
        "work_order_id": {"type": "string", "default": "WO-1"},
        "required_matt_skill": {"type": "string", "default": "tdd"},
        "step_id": {"type": "string", "default": "s-green"},
        "files_touched": {
            "type": "array",
            "items": {"type": "string"},
            "default": [],
        },
        "red_not_applicable_reason": {"type": "string"},
    },
}

EVIDENCE_VALIDATE_WORKER_RESULT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["worker_result_path"],
    "properties": {
        "worker_result_path": {
            "type": "string",
            "description": "Path to a v0.5.3 worker-result JSON file.",
        }
    },
}

EVIDENCE_RECORD_WORKER_RESULT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir", "worker_result_path"],
    "properties": {
        "run_dir": {
            "type": "string",
            "description": "Evidence run directory.",
        },
        "worker_result_path": {
            "type": "string",
            "description": "Path to a v0.5.3 worker-result JSON file.",
        },
        "raw_output_path": {
            "type": "string",
            "description": "Optional path to raw worker output to copy into the run.",
        },
    },
}
