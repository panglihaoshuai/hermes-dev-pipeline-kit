# Dev Pipeline Operating Model

## Purpose

Dev Pipeline is a Hermes-led software development orchestration and verification
system.

It turns user goals into plans, work orders, worker execution, local
verification, review gates, evidence artifacts, final reports, and approval
inboxes.

The operating model exists to prevent agent self-certification. It defines who
owns product judgment, who implements, who reviews, who generates state, and
which evidence is required before work can be called complete.

## Non-goals

- It is not a code generator by itself.
- It is not a replacement for ClaudeCode/Codex/OpenCode.
- It is not a promise that every skill is runtime-enforced.
- It must not let Hermes implement and self-accept without evidence.
- It is not proof that `hermes-evidence-runtime` is enabled.
- It is not proof that `evidence_*` tools are callable.
- It is not proof that worker CLI availability means worker integration.

## Role Model

| Role | Owner | Responsibility | Must not do |
|---|---|---|---|
| User | Owner / approval authority | Defines goals, approves commit/push/release/global changes | Be treated as a passive observer |
| Hermes | Chief architect / workflow owner / QA owner | Intake, scope, architecture, work orders, evidence review, final owner report | Self-implement and self-accept without evidence |
| gstack skills | Capability layer | Planning, review, investigate, ship, retro assistance | Compete with the canonical entrypoint |
| ClaudeCode | Implementation worker | Executes bounded work orders and reports evidence | Write final acceptance |
| Codex | Review / diagnostic / risk gate / optional worker when explicitly selected | Plan review, diff review, diagnostic review, risk gate | Convert text-only review into acceptance evidence |
| OpenCode | Optional worker | Alternative execution worker after capture is proven | Be assumed integrated because CLI exists |
| dev-pipeline-report | Owner-facing reporting | Final evidence and responsibility summary | Replace raw artifacts |
| hermes-evidence-runtime plugin | Runtime evidence, tools, hooks, state | Tool wrappers, hook capture, state evidence when enabled | Be treated as enabled when only discoverable |
| Bash harness | Executable substrate until plugin runtime is fully proven | Run directory, command log, generated run-state, policy-check, final-report | Become optional for C档 evidence |

## Layer Model

```text
User
  -> Hermes dev-pipeline-orchestrator
      -> policy and workflow skills
          -> writing-plans / TDD / gstack review / gstack investigate / gstack ship
      -> worker layer
          -> ClaudeCode / Codex / OpenCode
      -> evidence layer
          -> Bash harness scripts
          -> hermes-evidence-runtime plugin tools and hooks
      -> gate layer
          -> policy-check / generated state / final report / approval inbox
```

Layer rules:

- Skill defines policy; plugin/harness enforces evidence.
- Natural-language reports are allowed only as owner-facing summaries.
- Agent may submit evidence; harness owns state generation.
- Generated run-state must include provenance.
- Plugin source exists is not runtime enablement.

## Workflow Overview

1. Intake: Hermes normalizes the user goal, identifies scope and non-goals, and
   classifies the task.
2. Planning: Hermes uses writing/planning skills and, when needed, gstack plan
   review to create a bounded plan.
3. Work order: Hermes creates worker instructions with allowed files, forbidden
   files, required skill, validation commands, and output contract.
4. Execution: ClaudeCode, Codex, or OpenCode may execute bounded work, but worker
   outputs are evidence only.
5. Verification: Hermes checks local commands, diffs, docs, generated files,
   public claims, and baseline separation.
6. Review: Codex or gstack review may inspect plan or diff when required.
7. Evidence generation: B档 may use manually collected evidence; C档 requires
   plugin/harness artifacts.
8. Final report: `dev-pipeline-report` summarizes evidence, risks, responsibility,
   approval needs, and remaining blockers.
9. Approval: commit, push, release, dependency install, deployment, global config
   edits, and public publication require user approval.

## A/B/C Workflow Classes

| Class | Name | Evidence level | Use when | Runtime requirement |
|---|---|---|---|---|
| A档 | lightweight | Minimal command evidence | Small docs edits, one-file fixes, low-risk local work | Plugin not required |
| B档 | human-auditable | Manual evidence report plus local verification | M-level features, multi-file docs, normal project work | Plugin-generated run-state not required |
| C档 | machine-verifiable | Generated artifacts, policy-check, final report | Release, public claims, L-level, recovery, worker capture, CI/CD, generated files | Plugin/harness artifacts required |

B档 may use manually collected evidence reports and local verification. B档 does
not require plugin-generated run-state.

C档 requires plugin/harness artifacts, generated state, policy-check,
final-report, and approval inbox. C档 must not be called complete unless
`evidence_*` tools are proven callable or the Bash harness artifacts are
generated and validated for the run.

## S/M/L/recovery/publish Classification

| Classification | Typical scope | Required posture |
|---|---|---|
| S | Small, low-risk, usually one file | A档 by default; concise verification |
| M | Multi-file feature, API/store/docs suite, normal integration | B档 by default; upgrade when risk is unclear |
| L | 6+ files, auth, routing, AI, generated files, CI/CD, deployment, architecture change | C档 target; Codex review gate required |
| recovery | Failed prior work, timeout, inconsistent state, broken harness | C档 target; root-cause and replay evidence |
| publish | commit/push/PR/release/public repo/deployment | C档 target; approval inbox required |

Upgrade rules:

- If API, store, routing, i18n, AI, generated files, auth, CI/CD, deployment, or
  6+ files are involved, treat as L unless explicitly scoped down with evidence.
- If the active runtime version is unclear, run Active Version / Routing Gate.
- If Codex is unavailable or deferred, record it as deferred; Codex deferred is
  not Codex PASS.

## Evidence Ownership

Evidence ownership is split by trust boundary:

- Worker submits raw results, files touched, commands run, and skill evidence.
- Hermes verifies evidence and decides whether more work is needed.
- Harness generates run-state from raw evidence.
- Policy-check evaluates generated state.
- Final report summarizes generated and manually verified evidence.

The agent may submit evidence, but the harness owns state generation. A
hand-written run-state can be a fixture, not runtime evidence.

## Worker Ownership

ClaudeCode can implement but cannot self-accept.

Codex can review but text-only verdict is weak evidence.

OpenCode is optional until runtime capture is proven.

Worker outputs must:

- identify work order id;
- list files touched;
- list commands run;
- include required skill evidence when applicable;
- avoid `acceptance.complete`;
- preserve deferred states as deferred.

## Review Ownership

Hermes owns final workflow judgment, but it must not treat its own narrative as
review evidence.

Codex review can be:

- real repo plan review;
- real repo diff review;
- diagnostic review;
- text-only advisory review;
- deferred due to quota/auth/tooling.

Only real repo review with clear basis and verdict can count toward acceptance.
Text-only PASS is advisory, not acceptance evidence.

## Approval Ownership

The user owns approval for:

- commit;
- push;
- PR creation;
- public repo publication;
- deployment;
- dependency install;
- global config changes;
- real plugin enablement;
- real worker invocation when it may touch external services.

Approval must be centralized in an approval inbox for B档 and C档 work when any
approval-gated action is pending.

## Current Runtime Boundary

Current boundary:

- `hermes-evidence-runtime` plugin source exists.
- An installed copy may exist.
- Plugin discoverable is not plugin enabled.
- Active `evidence_*` tool calls: NO EVIDENCE FOUND unless listed and invoked by
  the active Hermes runtime.
- Hook payloads: UNKNOWN until captured.
- Worker CLI exists is not worker integrated.
- B档 remains human-auditable.
- C档 remains incomplete until plugin enablement or harness artifact generation is
  proven for the run.

## Failure Modes

| Failure mode | Required response |
|---|---|
| Stub or scaffold satisfies only shape | Verdict PARTIAL or FAIL, never PASS |
| README/public claims exceed evidence | Block release/publish until corrected |
| Codex deferred written as PASS | Fail Codex Evidence Quality Gate |
| Worker writes acceptance | Fail Worker Result Gate |
| Agent hand-writes run-state | Fail No Synthetic Run-State Gate |
| B档 lacks minimum evidence | Downgrade to PARTIAL and record missing evidence |
| C档 lacks plugin/harness artifacts | C档 FAIL or BLOCKED |
| Plugin discoverable but not enabled | Do not claim complete runtime status |
| Worker CLI exists but was not invoked/captured | Do not claim worker integrated |
| Global config or memory changed unexpectedly | Fail Self-Improvement Side Effect Gate |
