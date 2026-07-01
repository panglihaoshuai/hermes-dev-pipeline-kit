# Plugin Runtime Roadmap

## Current State

Current v0.8 boundary:

- `hermes-evidence-runtime` plugin source exists.
- An installed copy exists in some local environments.
- The plugin is enabled only when Hermes config includes
  `hermes-evidence-runtime` in `plugins.enabled`.
- v0.6 target: plugin enabled + evidence tools callable.
- v0.6 status: plugin enabled and evidence tools callable when the active
  Hermes runtime lists the `evidence_runtime` toolset and invokes the tool
  handlers successfully.
- v0.7 target: selected Hermes hook payloads captured in log-only mode.
- v0.7 status: `pre_tool_call` and `post_tool_call` were verified through a
  real Hermes runtime smoke using the local `model_tools.handle_function_call`
  path. Other registered hooks remain simulated-only or untriggered unless
  separately proven.
- v0.8 target: controlled-worker C-class dry-run with generated artifacts.
- v0.8 status: controlled-worker C-class dry-run passes with real Hermes
  evidence tool dispatch, real local command evidence, real pre/post hook
  evidence, generated run-state, generated policy result, generated final
  report, and a pending approval inbox.
- v0.9 target: optional integration backend spike for Hermes Dynamic Workflows
  and AgentGuard.
- v0.9 status: raw evidence contracts exist. The source-only adapter smoke is
  contract-only and does not claim real backend completion. Explicit real
  runtime smokes separately prove AgentGuard native Hermes allow/block hook
  behavior and Dynamic Workflows one-child completion when the optional backend
  sources and a configured Hermes provider are available. The combined explicit
  real-runtime smoke records both backend proofs into one policy-checked run.
  Dynamic Workflows orchestration evidence does not own acceptance. AgentGuard
  security decisions do not replace policy-check, Codex review, or final Hermes
  acceptance.
- Worker dry-run is explicit and disabled by default.
- Official ClaudeCode/Codex/OpenCode capture is not implemented.
- Enforcement is not implemented.
- The plugin does not implement a memory provider.
- The plugin does not replace `dev-pipeline-orchestrator`.

Required honesty rule:

```text
plugin source exists != plugin installed
plugin discoverable != plugin enabled
plugin enabled != tools callable
tools callable != hook enforcement
```

## Target State

Target C档 runtime:

- Hermes uses `dev-pipeline-orchestrator` as canonical entry.
- The plugin exposes callable evidence tools.
- Hooks capture runtime events in log-only mode first.
- Harness artifacts are generated from raw evidence.
- Policy-check and final-report are generated, not hand-written.
- Approval inbox blocks commit/push/release/global changes.
- Enforcement starts only after payload shape and false-positive risk are proven.

## Tools

Existing source tools:

- `evidence_doctor`
- `evidence_active_run_status`
- `evidence_run_init`
- `evidence_drive_s_run`
- `evidence_record_command`
- `evidence_generate_run_state`
- `evidence_policy_check`
- `evidence_final_report`
- `evidence_approval_inbox`
- `evidence_validate_worker_result`
- `evidence_record_worker_result`
- `evidence_normalize_worker_result`
- `evidence_invoke_worker_dry_run`
- `evidence_integration_capabilities`
- `evidence_record_orchestration_result`
- `evidence_record_security_decision`

Future C档 tools to add, expose, or prove callable:

- `evidence_route_check`
- `evidence_public_claim_check`
- `evidence_stub_check`

Tool behavior requirements:

- return machine-readable JSON;
- include exit codes and artifact paths;
- preserve skipped/deferred states;
- never convert worker output into acceptance;
- never write secrets into logs;
- support `/tmp` or explicit project-scoped smoke tests before real use.

## Hooks

Hook plan:

- `pre_tool_call`: initially log-only; later may block destructive commands or
  enforce harness wrappers after payload shape is proven.
- `post_tool_call`: log command/result metadata and artifact paths.
- `on_session_start`: active run detection.
- `on_session_end` / `on_session_finalize`: closure/final report reminders.
- `subagent_stop`: worker summary capture.
- `pre_gateway_dispatch`: high-risk, not first enforcement target.
- `pre_approval_request` / `post_approval_response`: approval evidence, if
  supported by the active runtime.

Hooks must start as log-only until payload shape and false-positive risk are
proven.

## State Directory

Target state layout:

```text
.hermes-runs/<run-id>/
  run-manifest.json
  classification.json
  events.jsonl
  state.json
  work-orders/
  raw/
    command-log.jsonl
    worker/
    stdout/
    stderr/
  generated/
    run-state.json
    replay-result.json
    policy-result.json
    final-report.md
  approvals/
```

Rules:

- raw evidence is append-only where practical;
- generated state is reproducible from raw evidence;
- final report is generated from state;
- synthetic fixtures live under examples, not runtime run directories.

## Policies

Policies to enforce in C档:

- no synthetic run-state;
- generated state provenance required;
- worker must not write `acceptance.complete`;
- Codex deferred is not Codex PASS;
- text-only PASS is not acceptance evidence;
- TDD RED before GREEN when TDD is required;
- public claims must map to evidence;
- stub/scaffold cannot satisfy milestone Done;
- forbidden files fail work order;
- secrets block commit/publish;
- plugin discoverable is not plugin enabled.

## Enablement Plan

| Stage | Goal | Evidence |
|---|---|---|
| E0 | source-only plugin smoke | Python compile and wrapper function calls from source |
| E1 | temp HOME enablement | plugin enabled in temp HOME only |
| E2 | `evidence_*` tools callable | active Hermes lists and calls tools successfully |
| E3 | hook payload capture log-only | v0.7 real smoke captured `pre_tool_call` and `post_tool_call`; other hooks require separate evidence |
| E4 | C档 dry-run with generated artifacts | v0.8 controlled-worker dry-run generated run-state, policy-result, final-report, and approval inbox |
| E5 | optional integration backend spike | v0.9 records Dynamic Workflows orchestration evidence and AgentGuard security decisions as raw evidence only; real backend smokes must be explicit and separate from default CI |
| E6 | selective enforcement | narrow pre_tool_call blocks with proven payload shape |

Do not skip from discoverable plugin to enforcement. v0.9 stops at optional
integration backend raw evidence. It proves AgentGuard native allow/block
callback behavior and Dynamic Workflows one-child completion only when the
explicit real-runtime smokes pass. It does not prove policy blocking, real
ClaudeCode/Codex/OpenCode worker capture, repair loops, or C档 production
readiness.

## Log-only Before Enforcement

Log-only mode must prove:

- which hook fired;
- payload shape;
- tool name and command mapping;
- redaction behavior;
- failure behavior on malformed payloads;
- false-positive rate;
- interaction with user approvals.

Only after log-only evidence is stable should any hook block commands.

## Open Questions

- Does the active Hermes runtime expose `evidence_*` tools after enabling the
  plugin?
- What is the exact payload shape for `pre_tool_call`, `post_tool_call`, and
  `subagent_stop` in real sessions?
- Can worker output be captured without relying on simulated/caller-supplied
  adapters?
- How should Codex quota/auth deferred states be represented in C档 artifacts?
- Which gstack skills write local state, and is that acceptable inside strict
  C档 runs?
- Should approval inbox be a plugin tool, a generated artifact, or both?
