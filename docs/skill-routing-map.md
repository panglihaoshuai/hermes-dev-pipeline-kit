# Skill Routing Map

## Canonical Entry

`dev-pipeline-orchestrator` is the only canonical entry for development
workflows.

Use it for feature development, bug fixing, refactor, integration, deployment
preparation, recovery, release preparation, code review recovery, and
multi-worker orchestration.

Other skills are internal capabilities. They must not compete as top-level
development entries.

## Optional Integration Backends

v0.9 integration backend routing is optional:

| Backend | Use For | Must Not Be Used For |
|---|---|---|
| Hermes Dynamic Workflows | raw orchestration evidence for delegated work | acceptance, Codex PASS, repair loop proof |
| AgentGuard | raw security allow/block evidence | engineering PASS, policy-check replacement, Codex review replacement |

## Internal Planning Skills

Planning skills help Hermes transform goals into plans and work orders:

- `writing-plans`: implementation plan and task sequencing.
- `plan`: lightweight plan document when applicable.
- `gstack plan-eng-review`: planning/risk review.
- `gstack plan-ceo-review`: product direction review when the goal itself is
  uncertain.
- `gstack plan-design-review`: UI/design review when user-facing experience is
  central.
- `gstack plan-devex-review`: API/SDK/developer-experience review.

These skills can inform the plan. They do not own acceptance.

## Internal Implementation Skills

Implementation work is assigned through bounded work orders:

- ClaudeCode is the default implementation worker for M/L code slices.
- Codex may be an implementation worker only when explicitly selected.
- OpenCode is optional until runtime capture is proven.
- `subagent-driven-development` is a delegation pattern, not a top-level entry.

writing-plans, test-driven-development, subagent-driven-development, gstack
skills are internal capabilities, not competing top-level entries.

## Verification Skills

Verification combines local commands, policy checks, and evidence review:

- `test-driven-development`: RED/GREEN/REFACTOR discipline and TDD evidence.
- Bash harness scripts: command recording, generated state, replay,
  policy-check, final report.
- `dev-pipeline-report`: owner-facing evidence report.

Verification must distinguish command evidence from narrative claims.

## Review Skills

Review skills provide independent pressure:

- `gstack review`: diff/PR/readiness review.
- Codex: plan review, diff review, diagnosis, risk gate.
- `github-code-review`: repository or PR review assistance when GitHub is in
  scope.

Codex can review but text-only verdict is weak evidence. A Codex deferred state
must remain deferred; Codex deferred is not Codex PASS.

## Release Skills

Release skills prepare user-approved publishing actions:

- `gstack ship`: release/publish preparation, approval required.
- GitHub publish lane: repository creation, push, PR, and public release checks.

Release skills must not run destructive or external actions without approval.

## Recovery Skills

Recovery skills are used when a prior attempt timed out, produced inconsistent
evidence, failed a policy gate, or left unclear state:

- `gstack investigate`: recovery/root cause.
- Codex diagnostic review: independent risk or root-cause check.
- Bash harness replay: state/event integrity check.

Recovery is usually C档 target because it must explain what happened, not only
patch symptoms.

## Evidence Runtime

Evidence runtime is the plugin/harness layer:

- Bash harness is the executable substrate.
- `hermes-evidence-runtime` plugin is the future Hermes runtime wrapper.
- Skill defines policy; plugin/harness enforces evidence.

Current boundary:

- plugin source exists;
- installed copy may exist;
- plugin discoverable is not plugin enabled;
- evidence tools are not proven callable unless active Hermes exposes them.

## Deprecated / Non-entry Skills

The following are not canonical development entries:

- `test-driven-development`: use only inside work orders or verification plans.
- `subagent-driven-development`: use only as a bounded delegation mechanism.
- `writing-plans`: use only as planning support.
- gstack skills: use only at specific gates.
- old dev/code-workflow entries: route to `dev-pipeline-orchestrator`.

## Routing Table

| Phase | Primary owner | Allowed skills/tools | Evidence required | Notes |
|---|---|---|---|---|
| Intake | Hermes | `dev-pipeline-orchestrator` | normalized goal, scope, non-goals, assumptions | Canonical entry starts here |
| Classification | Hermes | `dev-pipeline-orchestrator` | A/B/C and S/M/L/recovery/publish classification reason | If uncertain, upgrade |
| Planning | Hermes | `writing-plans`, `plan` | plan, tasks, acceptance criteria, risks | B/C only unless user asks |
| Plan review | Hermes + Codex/gstack | `gstack plan-eng-review`, Codex plan review | review basis, findings, pass/deferred/fail | L/high-risk M required |
| Work order | Hermes | work-order templates | allowed files, forbidden files, required skill, commands, output contract | Worker must not decide scope |
| Implementation | ClaudeCode by default | ClaudeCode, optional Codex/OpenCode | worker result, files touched, commands run | ClaudeCode can implement but cannot self-accept |
| TDD | ClaudeCode + Hermes verification | `test-driven-development`, record-command | RED non-zero, GREEN zero, or explicit not-applicable reason | TDD text alone is insufficient |
| Local verification | Hermes | shell commands, harness scripts | command, cwd, stdout/stderr path, exit code | Local grep is not acceptance |
| Review | Codex / gstack / Hermes | Codex review, `gstack review` | real repo basis, diff basis, verdict, required changes | Text-only PASS is advisory |
| Evidence generation | Harness / plugin | run-init, record-command, generate-run-state, policy-check, final-report, `evidence_*` tools | generated artifacts and provenance | C档 requires machine-verifiable evidence |
| Final report | Hermes | `dev-pipeline-report` | owner summary, skill evidence, responsibility, approval inbox | Report summarizes evidence; it is not evidence itself |
| Approval | User | approval inbox | explicit approval or explicit no-action-needed | Required for commit/push/release/global changes |
| Commit/push/release | Hermes after approval | `gstack ship`, GitHub publish lane | clean diff, staged allowlist, secret scan, user approval | Never `git add -A` |
| Recovery | Hermes + Codex/gstack | `gstack investigate`, Codex diagnostic, replay-run | root cause, failing evidence, recovery decision | Do not silently retry into completion |

## Worker Boundary

ClaudeCode can implement but cannot self-accept.

Codex can review but text-only verdict is weak evidence.

OpenCode is optional until runtime capture is proven.

Worker CLI existence is only capability evidence. It is not proof that the
worker was spawned, followed a required skill, or returned usable evidence.
