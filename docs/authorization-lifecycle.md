# Authorization Lifecycle

v0.10 adds a deterministic authorization model for selected Dev Pipeline and
Hermes mutation paths. It is a local evidence gate, not universal runtime
enforcement.

v0.10.1 makes this model durable by writing runtime-owned control artifacts
under the canonical run directory:

```text
<project>/.hermes-runs/<run-id>/control/
  authorization.json
  authorization.sha256
  approvals/<approval-id>.json
  terminal-verdict.json
  control-state.json
  events.jsonl
```

The `/tmp` bootstrap authorization used to start a local Codex session is not
the durable runtime store.

## Scope

Governed in v0.10:

- Dev Pipeline C-class mutating tools.
- Dev Pipeline install, uninstall, rollback, and reinstall helpers.
- Live mutation requests routed through the evidence runtime tools.

Not governed in v0.10:

- Codex UI internal continuation.
- Processes that bypass Hermes.
- Universal OS-level file or process mutation.
- External provider availability.

## Run Authorization

A run authorization binds:

- `run_id`
- `authorization_id`
- `goal_hash`
- `source_message_id`
- `source_session_id`
- `allowed_paths`
- `allowed_actions`
- `forbidden_actions`
- `requires_secondary_approval`
- `expires_on`

If user source cannot be verified by the host/runtime, authorization remains
pending and mutation is blocked. Agent-supplied goal text is not sufficient
authorization.

Evidence Runtime owns authorization persistence. Agents may request
authorization or approval, but ordinary worker/file mutation tools must not
write `control/**` directly. Within Dev Pipeline-managed execution, mutation
requests targeting `control/**` fail closed with
`runtime_control_artifact_protected`.

Each persisted authorization has a SHA256 sidecar. Approvals and terminal
verdicts bind to the current authorization hash. Hash mismatch, malformed JSON,
missing required artifacts, stale approval, or inconsistent run/authorization
binding fails closed.

## State Machine

```text
CREATED
→ AUTHORIZED
→ ACTIVE
→ COMPLETED

ACTIVE
→ FAILED_REAUTH_REQUIRED

ACTIVE
→ BLOCKED_REAUTH_REQUIRED

ACTIVE
→ PAUSED_REAUTH_REQUIRED
```

Terminal reports deactivate mutation authorization:

| Verdict | Next state | Authorization |
|---|---|---|
| `PASS_*` | `completed` | completed/inactive |
| `FAIL_*` | `failed_reauth_required` | expired |
| `PARTIAL_*` | `paused_reauth_required` | expired |
| `BLOCKED` | `blocked_reauth_required` | expired |

If a run will continue repairing within the original authorized scope, it must
emit a non-terminal stage update. It must not emit a final terminal report first.

## Secondary Live Approval

The following actions require exact live approval:

- `modify_live_home`
- `install_plugin`
- `uninstall_plugin`
- `rollback`
- `reinstall`

Approval must match:

- `authorization_id`
- `action`
- `target_path`
- `status=approved`
- non-empty `approved_at`

Pending approval is not approval. The agent cannot mark a pending approval as
approved. Approvals from old authorizations are stale and must be rejected.

Pending approval is durable and remains pending after process restart. Approved
approval must come from a trusted runtime/user event; the agent-facing
`evidence_prepare_live_approval` tool never self-approves.

## Continuation And Recovery

After a terminal verdict:

- `codex_internal_context source="goal"` is read-only.
- session recovery is read-only.
- task resume is read-only.
- `Next Goal` text in a report is never executable authorization.

Fresh user reauthorization must create a new authorization ID or explicit
renewal artifact.

Recovery reads from disk, not from a previous Python process. If
`terminal-verdict.json` exists, it is authoritative after restart and
`continuation_allowed=false`. If `control-state.json` is missing but a terminal
verdict exists, recovery reconstructs a terminal blocked state. If
authorization is missing, malformed, or hash-invalid, mutation is blocked with
`CONTROL_ARTIFACT_INVALID` or `CONTROL_ARTIFACT_MISSING`.

Control JSON files are written by temporary file, flush, fsync, and atomic
rename. The control directory is best-effort `0700`, control files are
best-effort `0600`, and a per-run lock file serializes control state writes with
timeout and stale-lock handling. Control events are append-only; state changes
append new events rather than rewriting history.

## External E2E Boundary

External provider failures are classified separately from code regressions.

`SKIP_EXTERNAL_PROVIDER_UNAVAILABLE` is not `PASS_REAL_RUNTIME`.

Provider quota, auth, model, network, or timeout failures defer fresh live E2E
qualification until a separately authorized run is possible.

## Boundary

The store protects consistency inside Dev Pipeline-managed execution. It is not
a cryptographic trust boundary against the same OS user, does not control
external tools that bypass Hermes, and does not directly control Codex UI
internal continuation.
