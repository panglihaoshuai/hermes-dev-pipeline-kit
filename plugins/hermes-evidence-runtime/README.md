# hermes-evidence-runtime

Experimental v0.5.1-v0.8 Hermes plugin wrapper for `hermes-dev-pipeline-kit`.

This plugin registers tools that wrap the existing Bash evidence harness:

- `evidence_doctor` wraps `scripts/doctor.sh`
- `evidence_active_run_status` reads project-local run metadata
- `evidence_run_init` wraps `scripts/run-init.sh`
- `evidence_drive_s_run` wraps `scripts/drive-s-run.sh`
- `evidence_record_command` wraps `scripts/record-command.sh`
- `evidence_generate_run_state` wraps `scripts/generate-run-state.sh` and adds v0.8 provenance checks
- `evidence_policy_check` wraps `scripts/policy-check.sh`
- `evidence_final_report` wraps `scripts/final-report.sh`
- `evidence_approval_inbox` writes a pending approval artifact
- `evidence_validate_worker_result` wraps `scripts/validate-worker-result.sh`
- `evidence_record_worker_result` wraps `scripts/record-worker-result.sh`
- `evidence_normalize_worker_result` wraps `scripts/normalize-worker-result.sh`
- `evidence_invoke_worker_dry_run` wraps `scripts/invoke-worker-dry-run.sh`

The tools return machine-readable JSON strings.

## Boundaries

v0.6 target: plugin enabled + evidence tools callable.
v0.6 status: plugin enabled and evidence tools callable when Hermes config
enables `hermes-evidence-runtime` and the wrapper can locate the kit scripts
through source layout, current working directory, or
`HERMES_DEV_PIPELINE_KIT_ROOT`.

v0.7 captures selected Hermes hook payloads in log-only mode. The
`pre_tool_call` and `post_tool_call` handlers were verified through a real
Hermes runtime smoke using the local `model_tools.handle_function_call` path.
Other registered hooks remain simulated-only or untriggered unless separately
proven.

v0.5.1-v0.8 plugin wrapper is experimental.
It does not replace built-in ClaudeCode/Codex/OpenCode skills.
It does not replace the existing dev-pipeline-orchestrator skill.
It does not capture official ClaudeCode/Codex/OpenCode output yet.

v0.8 proves a controlled-worker C-class dry-run using real Hermes evidence tool
dispatch, real local RED/GREEN command evidence, real `pre_tool_call` and
`post_tool_call` hook evidence, generated run-state, generated policy result,
generated final report, and a pending approval inbox.

v0.8 does not prove real ClaudeCode/Codex/OpenCode worker capture. v0.8 does
not implement enforcement, does not block Hermes tool calls, does not mutate
tool parameters/results, and is not C档 production readiness.

v0.5.2 adds prototype hook handlers:

- `pre_tool_call`
- `post_tool_call`
- `on_session_start`
- `on_session_end`
- `on_session_finalize`
- `subagent_stop`

The hooks are non-blocking and observational only. They write
`hook-events.jsonl` only when `HERMES_EVIDENCE_HOOK_LOG_DIR` is set. They
redact secret-like keys and values before logging. They do not enforce
commit/push guards, do not implement a memory provider, do not replace old
skills, and do not capture official ClaudeCode/Codex/OpenCode output yet.

The plugin is intended for source-only, temporary-home, and explicit live
enablement smoke validation. `scripts/install.sh` does not install it into a
real `~/.hermes/plugins` directory. Hook payload shape remains unknown for
hooks and trigger paths not covered by the v0.7 smoke.

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

v0.5.5 adds a Real Worker Dry-run / Explicit Invocation Prototype. It writes
`raw.txt`, `structured.json`, and `invocation.json`. Real invocation is optional
and disabled by default. Default CI exercises only disabled/skipped invocation
evidence. Optional real dry-run requires:

```bash
HERMES_EVIDENCE_ALLOW_REAL_WORKER_DRY_RUN=1 bash scripts/smoke/smoke-worker-dry-run-real-optional.sh
```

v0.5.5 still does not claim official ClaudeCode/Codex/OpenCode capture. v0.6
adds plugin enablement and tool-call evidence only. v0.7 adds selected log-only
hook observation evidence only. It does not modify `~/.claude/CLAUDE.md`, does
not implement a memory provider, and does not replace the existing
`dev-pipeline-orchestrator` skill. Harness gates own final acceptance; worker
wrappers own result evidence only.
