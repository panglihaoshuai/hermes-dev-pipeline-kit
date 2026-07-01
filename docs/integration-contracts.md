# Integration Contracts

v0.9 defines optional backend contracts for raw evidence only. These contracts
do not replace `dev-pipeline-orchestrator`, policy-check, Codex review, or final
Hermes acceptance.

## Hermes Dynamic Workflows

Purpose: record orchestration evidence from `lingjiuu/hermes-dynamic-workflows`.

Raw artifact:

```text
raw/orchestration-backend-result.json
```

Boundary:

- May record backend availability, run id, status, journal path, transcript
  paths, workspace path, structured result path, and backend error.
- Must not contain `acceptance`.
- Must not be treated as Codex PASS.
- Must not prove worker completion unless the Dynamic Workflows child run
  actually completed and produced raw evidence.
- If Hermes inference provider is not configured or the child fails, the
  correct result is a precise non-PASS status such as `NO_PROVIDER_CONFIG`,
  `AUTH_UNAVAILABLE`, `MODEL_UNAVAILABLE`, `NETWORK_UNAVAILABLE`,
  `QUOTA_UNAVAILABLE`, `STRUCTURED_OUTPUT_INVALID`, or `UNKNOWN`.

## AgentGuard

Purpose: record security decision evidence from `GoPlusSecurity/agentguard`.

Raw artifact:

```text
raw/security-decisions.jsonl
```

Boundary:

- May record `allow`, `block`, or `unknown`.
- `allow` is not engineering PASS.
- `block` does not replace policy-check, Codex review, or final Hermes
  acceptance.
- Security decision records must not write `acceptance` or `policy_verdict:
  PASS`.
- Adapter-created allow/block records are contract evidence only. They must not
  be reported as AgentGuard native runtime use. Native runtime use requires the
  real AgentGuard Hermes plugin `pre_tool_call` callback and proof that a block
  short-circuited the tool handler.

## v0.9 Tool Surface

- `evidence_integration_capabilities`
- `evidence_record_orchestration_result`
- `evidence_record_security_decision`

## v0.9 Smoke Scope

`scripts/smoke/smoke-plugin-v09-integration-backends.sh` is source-only and
uses `/tmp`. It does not install global dependencies, does not call real
ClaudeCode/Codex/OpenCode workers, and does not claim C档 production readiness.
It also does not claim real Dynamic child completion or AgentGuard native hook
execution.

Explicit real-runtime gates:

- `scripts/smoke/smoke-plugin-v09-agentguard-native.sh` proves native
  AgentGuard allow/block through Hermes `pre_tool_call` and a canary terminal
  handler.
- `scripts/smoke/smoke-plugin-v09-dynamic-real-child.sh` proves a real Dynamic
  Workflows `workflow` launch, one child completion, journal/transcript/output
  files, and schema-valid structured output. It can consume provider tokens and
  is not part of default CI.
- `scripts/smoke/smoke-plugin-v09-combined-real-backends.sh` records both
  AgentGuard native allow/block evidence and Dynamic Workflows one-child
  completion into the same run, then requires generated run-state,
  policy-check, and final-report to pass. It is explicit-only because it needs
  the optional backend sources and a configured Hermes provider.
