# Authorization Lifecycle

v0.10 adds a deterministic authorization model for selected Dev Pipeline and
Hermes mutation paths. It is a local evidence gate, not universal runtime
enforcement.

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

## Continuation And Recovery

After a terminal verdict:

- `codex_internal_context source="goal"` is read-only.
- session recovery is read-only.
- task resume is read-only.
- `Next Goal` text in a report is never executable authorization.

Fresh user reauthorization must create a new authorization ID or explicit
renewal artifact.

## External E2E Boundary

External provider failures are classified separately from code regressions.

`SKIP_EXTERNAL_PROVIDER_UNAVAILABLE` is not `PASS_REAL_RUNTIME`.

Provider quota, auth, model, network, or timeout failures defer fresh live E2E
qualification until a separately authorized run is possible.
