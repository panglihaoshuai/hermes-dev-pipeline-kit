# hermes-evidence-runtime

Experimental v0.5.1-v0.5.4 Hermes plugin wrapper for `hermes-dev-pipeline-kit`.

This plugin registers tools that wrap the existing Bash evidence harness:

- `evidence_doctor` wraps `scripts/doctor.sh`
- `evidence_active_run_status` reads project-local run metadata
- `evidence_run_init` wraps `scripts/run-init.sh`
- `evidence_drive_s_run` wraps `scripts/drive-s-run.sh`
- `evidence_validate_worker_result` wraps `scripts/validate-worker-result.sh`
- `evidence_record_worker_result` wraps `scripts/record-worker-result.sh`
- `evidence_normalize_worker_result` wraps `scripts/normalize-worker-result.sh`

The tools return machine-readable JSON strings.

## Boundaries

v0.5.1 plugin wrapper is experimental.
It is source-validated and temp-HOME discovery validated.
It does not install into real `~/.hermes/plugins` by default.
It does not replace built-in ClaudeCode/Codex/OpenCode skills.
It does not replace the existing dev-pipeline-orchestrator skill.
It does not capture official ClaudeCode/Codex/OpenCode output yet.

v0.5.2 adds prototype hook handlers:

- `pre_tool_call`
- `post_tool_call`
- `on_session_end`
- `on_session_finalize`
- `subagent_stop`

The hooks are non-blocking and observational only. They write
`hooks.jsonl` only when `HERMES_EVIDENCE_HOOK_LOG_DIR` is set. They redact
secret-like keys and values before logging. They do not enforce commit/push
guards, do not implement a memory provider, do not replace old skills, and do
not capture official ClaudeCode/Codex/OpenCode output yet.

The plugin is intended for source-only and temporary-home smoke validation. Do
not install it into a real `~/.hermes/plugins` directory until a separate
install flow and rollback plan are reviewed. Real Hermes runtime hook payload
shape remains UNKNOWN until a future runtime probe.

v0.5.3 adds a Worker Result Contract Adapter prototype. It validates and records
simulated worker result JSON into the existing Bash harness evidence directory.
It does not call real ClaudeCode, Codex, or OpenCode. It does not claim official
worker output capture. Worker results are raw evidence only; they cannot set
`acceptance.complete=true` and cannot replace Hermes/Codex final gates.

v0.5.4 adds an Official Worker Wrapper Prototype normalizer. The name describes
the target integration lane, not completed official capture. It normalizes
caller-supplied or simulated `claude-code`, `codex`, `opencode`, and `raw`
adapter output into the existing v0.5.3 worker-result contract.

v0.5.4 does not invoke real ClaudeCode, Codex, or OpenCode. It does not parse
real provider session stores. It does not implement a memory provider and does
not add any production hook dependency. It does not replace built-in
ClaudeCode/Codex/OpenCode skills or the existing `dev-pipeline-orchestrator`
skill.
