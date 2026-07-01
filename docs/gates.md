# Dev Pipeline Gates

## Gate Philosophy

Gates exist to prevent agent self-certification.

A gate is valid only when it has:

- a problem it prevents;
- an owner;
- required evidence;
- clear pass criteria;
- failure behavior.

Natural-language gates are not enough. B档 can be human-auditable, but it still
needs concrete evidence. C档 is machine-verifiable and requires generated
artifacts.

## Gate Matrix

| Gate | Problem prevented | Required evidence | A | B | C | Failure behavior |
|---|---|---|---:|---:|---:|---|
| Stub / Scaffold Gate | Scaffold, placeholder, or shape-only work marked complete | implementation files, integration path, smoke/test evidence | warn | block | block | If a milestone's central feature is stubbed, verdict must be PARTIAL or FAIL, never PASS |
| Public Claim Gate | README/docs/product claims exceed implementation | claim list mapped to files/tests/artifacts | warn | block | block | If README claims exceed implementation evidence, release/publish is blocked |
| Milestone Definition of Done Gate | Vague M4/M5/M6 style milestones pass without real integration | milestone checklist, expected behavior, verification command | optional | block | block | Missing DoD means PARTIAL until criteria and evidence exist |
| Codex Evidence Quality Gate | Text-only PASS, stale review, or deferred review treated as acceptance | review command/source, repo path, diff basis, timestamp, verdict | optional | warn/block by risk | block | Text-only Codex PASS is advisory, not acceptance; Codex deferred must remain deferred, not PASS |
| Worker Result Gate | Worker self-certifies completion or delegation is fabricated | worker-result, raw output path, files touched, commands run, skill evidence | optional | block for delegated work | block | Worker output must not contain `acceptance.complete`; missing result downgrades or fails |
| TDD Evidence Gate | RED/GREEN skipped or faked | command-log RED exit non-zero, GREEN exit zero, or reason | optional | block when TDD required | block | RED exit 0 without reason fails TDD evidence |
| Active Version / Routing Gate | Wrong source/runtime/backup skill used | source HEAD, installed skill/plugin version, enabled list, active entry | optional | block when routing matters | block | Unknown active version prevents acceptance |
| Plugin Enablement Gate | Plugin source/discovery mistaken for runtime enforcement | plugin enabled list, `evidence_*` tool visibility, temp-HOME/live smoke | no | optional | block | Plugin discoverable is not plugin enabled; C档 cannot claim plugin runtime |
| Hook Payload Observation Gate | Hook source or simulated callback mistaken for runtime capture | hook JSONL, capture_mode, trigger path, redaction evidence, non-mutation evidence | no | optional | block when hooks are cited | Only captured hooks count; v0.7 covers `pre_tool_call` and `post_tool_call` only |
| Controlled C Dry-run Gate | Controlled worker fixture mistaken for production C档 readiness | real evidence tool calls, RED/GREEN command log, real pre/post hook log, worker fixture marked controlled, generated run-state, policy result, final report, approval inbox | no | optional | block for v0.8 C dry-run claims | v0.8 may claim controlled-worker dry-run only, not real worker capture or enforcement |
| Optional Backend Evidence Gate | Optional backend evidence is treated as acceptance | raw orchestration/security evidence, policy result, Codex review | warn | block | block | Dynamic Workflows and AgentGuard evidence are raw inputs only; they cannot close acceptance |
| Approval Inbox Gate | Commit/push/release/global edits happen without user approval | approval item, risk, default recommendation, user decision | optional | block if approval needed | block | Stop before gated action and wait for user |
| Release / Publish Gate | Public release without complete evidence | final report, policy PASS, Codex gate, clean git, secret scan | no | optional | block | Release/publish blocked until evidence and approvals pass |
| Generated State Provenance Gate | Generated state has no trace to raw evidence | `generated/run-state.json` with provenance source files | no | optional | block | Missing provenance means generated state is invalid |
| No Synthetic Run-State Gate | Agent hand-writes compliant-looking state | generator metadata, source files, script invocation | no | block for M/L run-state | block | Synthetic run-state is fixture only, not runtime evidence |
| Self-Improvement Side Effect Gate | Agent modifies memory/global config/rules outside scope | git diff, HOME diff if relevant, explicit approval | warn | block | block | Unexpected side effect must be reverted or reported as blocker |
| Forbidden Files Gate | Worker changes files outside work order | work order allowlist/denylist and `git diff --name-status` | optional | block | block | Forbidden-file violation fails work order |
| Secret Scan Gate | Secrets or personal data committed/published | grep/secret scan output, staged file list | optional | block | block | Any suspected secret blocks commit/publish until resolved |

## A档 Gates

A档 is lightweight. It is appropriate for small, low-risk edits.

Required A档 gates:

- classification;
- scope boundary;
- local verification where applicable;
- final concise report;
- approval inbox if commit/push/release/global changes are needed.

A档 does not require plugin-generated run-state. A档 should still avoid public
overclaims and obvious scaffold completion claims.

## B档 Gates

B档 is human-auditable.

Required B档 gates:

- classification and routing;
- planning or structured task brief;
- work order or equivalent task boundary;
- local verification evidence;
- Worker Result Gate when work is delegated;
- TDD Evidence Gate when TDD is required;
- Stub / Scaffold Gate;
- Public Claim Gate for docs/README/product statements;
- Codex Evidence Quality Gate when Codex is used or required by risk;
- final evidence report.

B档 may use manually collected evidence reports and local verification. B档 does
not require plugin-generated run-state. B档 must not be called
machine-verifiable.

## C档 Gates

C档 is machine-verifiable.

Required C档 gates:

- active runtime and routing evidence;
- run directory;
- raw evidence;
- command log;
- worker-result where delegated;
- generated run-state;
- provenance;
- policy-check;
- final-report;
- approval inbox;
- Codex gate when required;
- plugin enablement or harness artifact evidence.
- hook payload evidence when hook capture is cited as runtime evidence.
- for v0.8 controlled-worker dry-run claims, worker evidence must be explicitly
  marked controlled/simulated and must not be described as official worker
  capture.

C档 remains incomplete until plugin enablement smoke passes or the Bash harness
generates the required artifacts for the run.

## Failure Behavior

Failure behavior must be explicit:

- block: stop and report the failing gate;
- partial: continue only when the user asked for partial output and no approval
  gate is crossed;
- retry: allowed only with a smaller work order and preserved failure evidence;
- downgrade: B/C claims may be downgraded when evidence is missing;
- defer: Codex unavailable or quota-limited remains deferred, never PASS;
- approval wait: external or destructive actions wait for the user.

No gate may be converted into acceptance by narrative alone.
