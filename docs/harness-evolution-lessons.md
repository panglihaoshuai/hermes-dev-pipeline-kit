# Harness Evolution Lessons

This document records why the dev-pipeline moved from prompt-only skills toward
an evidence harness and plugin runtime. It is intentionally conservative: a
documented protocol is not the same thing as enforcement.

## Why v0.1 was insufficient

v0.1 was mostly a Markdown skill and prompt protocol. It could describe a good
workflow, but it could not prove that the workflow happened.

Failure modes:

- Hermes could appear to call a skill while leaving no runtime evidence.
- An agent could say it followed the process without machine evidence.
- Gates existed only as natural-language instructions.
- There was no run directory.
- There was no raw evidence.
- There was no generated run-state.
- There was no replay.
- There was no policy-check.

Permanent lesson:

```text
Skill defines policy, but skill alone must not be treated as enforcement.
```

## Why v0.2 was insufficient

v0.2 added more explicit workflow rules, including stage updates, owner-facing
summaries, skill trace, TDD requirements, Codex review requirements, full report
requirements, and verification gates.

That improved disclosure, but the process could still be skipped:

- Agents often omitted required report columns.
- Agents could claim tests passed without command evidence.
- Hermes could skip spawning ClaudeCode.
- A task could claim TDD without RED/GREEN command evidence.
- Codex unavailable or deferred states could be written like a pass.
- Scaffold and stub work could be reported as completed implementation.

Permanent lesson:

```text
Natural-language gates are not enough. Every required gate needs evidence
ownership and failure behavior.
```

## Why v0.3 was insufficient

v0.3 introduced run-state, policy-check, final report, and evidence report
concepts. This moved the project closer to auditable execution, but it exposed a
deeper ownership problem.

Failure modes:

- `run-state.json` could be hand-written by the agent.
- A synthetic run-state could be prefilled to look compliant.
- `policy-check.sh` could only validate the JSON it was given.
- Policy checks could not prove that JSON came from real commands.
- The agent could still use synthetic state as if it were runtime behavior.

Permanent lesson:

```text
Agent may submit evidence.
Harness owns state generation.
Agent must not hand-write final run-state.
Generated run-state must include provenance.
```

## What v0.4 fixed

v0.4 introduced a Bash harness as executable substrate:

- `run-init.sh`
- `record-command.sh`
- `append-event.sh`
- `transition-check.sh`
- `replay-run.sh`
- `generate-run-state.sh`
- `policy-check.sh`
- `final-report.sh`

This fixed important evidence gaps:

- Command facts can include command, cwd, stdout, stderr, timestamps, and exit
  code.
- RED/GREEN ordering can be checked.
- Generated run-state can cite raw evidence through provenance.
- Replay can detect event-chain tampering.
- Final reports can be generated from state instead of agent narrative.

Remaining problem:

- Hermes may still bypass the harness unless the active runtime enforces it.
- An agent can still report in natural language instead of using scripts.
- Bash scripts are external tools, not automatically Hermes runtime constraints.

Permanent lesson:

```text
Bash harness is the executable substrate, but Hermes plugin/hooks are needed for
runtime capture and enforcement.
```

## What v0.5 started

v0.5 introduced the `hermes-evidence-runtime` plugin source and worker evidence
prototypes:

- source plugin wrapper;
- source `evidence_*` tools;
- worker-result contract;
- worker normalizer;
- explicit worker dry-run wrapper.

The v0.5.5 boundary is still strict:

- plugin source exists;
- an installed copy may exist;
- plugin discoverable is not plugin enabled;
- evidence tools are not proven callable unless the runtime exposes them;
- hook payloads are not proven until captured in a real or temp-HOME runtime;
- worker dry-run is not official ClaudeCode/Codex/OpenCode capture.

The v0.7 boundary is narrower and evidence-based:

- `pre_tool_call` and `post_tool_call` were captured through a real Hermes
  runtime smoke using the local `model_tools.handle_function_call` path;
- selected hook payloads are logged only when
  `HERMES_EVIDENCE_HOOK_LOG_DIR` is set;
- captured payloads must be redacted, non-mutating, and fail-open;
- untriggered hooks remain unproven and must not be counted as runtime
  coverage.

Permanent lesson:

```text
plugin source exists != plugin installed
plugin discoverable != plugin enabled
plugin enabled != tools callable
tools callable != hook enforcement
```

## What simple-code exposed

The `simple-code` history is a counterexample that the dev-pipeline must design
against. It showed that a project can have a plausible process and still drift
away from real completion.

Observed failures:

- M1-M3 skeleton work could pass while later milestones were mostly scaffold.
- M4-M7 had scaffold, stubs, missing vendoring, and missing wiring.
- README and public claims exceeded implementation evidence.
- Tests sometimes checked interface shape rather than real integration.
- There was no evidence that ClaudeCode had been spawned for required work.
- Complete harness artifacts were missing.
- Codex review sometimes meant real repo review, but sometimes meant text-only
  pass-like statements.
- B档 without a minimum evidence standard can degrade into "write a plan and
  summarize it".

Design response:

- Stub / Scaffold Gate must block or downgrade incomplete milestones.
- Public Claim Gate must map claims to implementation evidence.
- Codex Evidence Quality Gate must distinguish real command/repo evidence from
  text-only review.
- Worker Result Gate must prove delegation or record a waiver.
- B档 must remain human-auditable, not machine-verifiable.
- C档 must require generated artifacts and policy output.

## Permanent Design Rules

1. Skill defines policy; plugin/harness enforces evidence.
2. Agent may submit evidence; harness owns state generation.
3. Worker must not write `acceptance.complete`.
4. Generated run-state must include provenance.
5. Text-only PASS is not acceptance evidence.
6. Codex deferred is not Codex PASS.
7. Stub/scaffold cannot satisfy milestone Done.
8. README/public claims must map to implementation evidence.
9. Plugin discoverable is not plugin enabled.
10. C档 requires callable plugin tools and/or generated harness artifacts.
11. B档 is human-auditable and may use manually collected evidence.
12. C档 is machine-verifiable and requires generated state, policy output, and
    final report artifacts.
13. Worker CLI exists does not mean worker integrated.
14. Hook source exists does not mean hook payloads are proven; only captured
    hooks with trigger-path evidence count.
15. Harness policy owns acceptance; worker outputs are evidence only.
