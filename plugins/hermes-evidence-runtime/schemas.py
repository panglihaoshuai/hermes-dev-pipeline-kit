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

EVIDENCE_RECORD_COMMAND_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir", "work_dir", "command", "phase"],
    "properties": {
        "run_dir": {"type": "string"},
        "work_dir": {"type": "string"},
        "command": {"type": "string"},
        "phase": {"type": "string", "enum": ["RED", "GREEN", "VERIFY", "red", "green", "verify"]},
        "step_id": {"type": "string"},
    },
}

EVIDENCE_GENERATE_RUN_STATE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir"],
    "properties": {
        "run_dir": {"type": "string"},
        "hook_log_path": {
            "type": "string",
            "description": "Optional hook-events.jsonl path or directory to copy into raw/hook-events.jsonl before generation.",
        },
    },
}

EVIDENCE_POLICY_CHECK_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir"],
    "properties": {
        "run_dir": {"type": "string"},
    },
}

EVIDENCE_FINAL_REPORT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir"],
    "properties": {
        "run_dir": {"type": "string"},
    },
}

EVIDENCE_APPROVAL_INBOX_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir"],
    "properties": {
        "run_dir": {"type": "string"},
        "status": {
            "type": "string",
            "description": "Must not be approved/granted; the tool only emits pending approval requests.",
        },
        "approved": {
            "type": "boolean",
            "description": "Must not be true; approval artifacts are not user approval.",
        },
        "items": {
            "type": "array",
            "items": {"type": "object"},
            "description": "Optional caller items are only accepted if all are pending/unapproved.",
        },
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

EVIDENCE_NORMALIZE_WORKER_RESULT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "worker",
        "worker_skill",
        "work_order_id",
        "status",
        "result_type",
        "raw_output_path",
        "out_path",
    ],
    "properties": {
        "worker": {
            "type": "string",
            "enum": ["claude-code", "codex", "opencode", "raw"],
            "description": "Worker adapter to normalize. raw maps to worker=unknown in the v0.5.3 contract.",
        },
        "worker_skill": {
            "type": "string",
            "description": "Worker skill or mode that produced the output.",
        },
        "work_order_id": {
            "type": "string",
            "description": "Work order id associated with this worker output.",
        },
        "status": {
            "type": "string",
            "enum": ["completed", "partial", "blocked", "failed", "deferred"],
        },
        "result_type": {
            "type": "string",
            "enum": ["implementation", "review", "diagnostic", "plan", "unknown"],
        },
        "raw_output_path": {
            "type": "string",
            "description": "Path to caller-supplied raw worker output.",
        },
        "structured_output_path": {
            "type": "string",
            "description": "Optional path to caller-supplied structured JSON output.",
        },
        "invocation_json_path": {
            "type": "string",
            "description": "Optional path to invocation.json from invoke-worker-dry-run.sh.",
        },
        "out_path": {
            "type": "string",
            "description": "Destination worker-result JSON path.",
        },
    },
}

EVIDENCE_INVOKE_WORKER_DRY_RUN_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["worker", "out_dir"],
    "properties": {
        "worker": {
            "type": "string",
            "enum": ["claude-code", "codex", "opencode", "raw"],
        },
        "out_dir": {
            "type": "string",
            "description": "Output directory under /tmp for raw.txt, structured.json, and invocation.json.",
        },
        "timeout_seconds": {
            "type": "integer",
            "minimum": 1,
            "default": 60,
        },
        "allow_real_invocation": {
            "type": "boolean",
            "default": False,
            "description": "When false, no real worker CLI is invoked.",
        },
        "prompt_file": {
            "type": "string",
            "description": "Optional prompt file for real dry-run invocation.",
        },
    },
}

EVIDENCE_INTEGRATION_CAPABILITIES_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "hermes_home": {
            "type": "string",
            "description": "Optional temp HERMES_HOME to inspect with hermes plugins list --json.",
        },
        "dynamic_workflows_path": {
            "type": "string",
            "description": "Optional source/plugin directory for lingjiuu/hermes-dynamic-workflows.",
        },
        "agentguard_path": {
            "type": "string",
            "description": "Optional source/plugin directory for GoPlusSecurity/agentguard Hermes plugin.",
        },
    },
}

EVIDENCE_RECORD_ORCHESTRATION_RESULT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir", "result"],
    "properties": {
        "run_dir": {"type": "string"},
        "result": {"type": "object"},
    },
}

EVIDENCE_RECORD_SECURITY_DECISION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_dir", "decision"],
    "properties": {
        "run_dir": {"type": "string"},
        "decision": {"type": "object"},
    },
}

EVIDENCE_AUTHORIZATION_STATUS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "authorization": {"type": "object"},
        "authorization_path": {"type": "string"},
        "action": {"type": "string"},
        "target_path": {"type": "string"},
        "goal_hash": {"type": "string"},
        "live_approval": {"type": "object"},
        "context_event": {"type": "string"},
        "c_class_run": {"type": "boolean", "default": False},
    },
}

EVIDENCE_PREPARE_LIVE_APPROVAL_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["action", "target_path", "source_user_message_id"],
    "properties": {
        "authorization": {"type": "object"},
        "authorization_path": {"type": "string"},
        "action": {
            "type": "string",
            "enum": ["modify_live_home", "install_plugin", "uninstall_plugin", "rollback", "reinstall"],
        },
        "target_path": {"type": "string"},
        "source_user_message_id": {"type": "string"},
        "status": {"type": "string", "default": "pending"},
    },
}

EVIDENCE_TERMINALIZE_RUN_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["run_id", "verdict"],
    "properties": {
        "authorization": {"type": "object"},
        "authorization_path": {"type": "string"},
        "run_id": {"type": "string"},
        "verdict": {"type": "string"},
        "canary_status": {"type": "string"},
    },
}
