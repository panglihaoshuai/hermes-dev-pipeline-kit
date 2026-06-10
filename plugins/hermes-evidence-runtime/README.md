# hermes-evidence-runtime

Experimental v0.5.1 Hermes plugin wrapper for `hermes-dev-pipeline-kit`.

This plugin registers tools that wrap the existing Bash evidence harness:

- `evidence_doctor` wraps `scripts/doctor.sh`
- `evidence_active_run_status` reads project-local run metadata
- `evidence_run_init` wraps `scripts/run-init.sh`
- `evidence_drive_s_run` wraps `scripts/drive-s-run.sh`

The tools return machine-readable JSON strings.

## Boundaries

v0.5.1 plugin wrapper is experimental.
It is source-validated and temp-HOME discovery validated.
It does not install into real `~/.hermes/plugins` by default.
It does not replace built-in ClaudeCode/Codex/OpenCode skills.
It does not implement hooks or memory provider.
It does not replace the existing dev-pipeline-orchestrator skill.
It does not capture official ClaudeCode/Codex/OpenCode output yet.

The plugin is intended for source-only and temporary-home smoke validation in
v0.5.1. Do not install it into a real `~/.hermes/plugins` directory until a
separate install flow and rollback plan are reviewed.
