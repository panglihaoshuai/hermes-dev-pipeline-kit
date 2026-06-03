# Codex Diff Review

## Review Target

- project:
- base:
- head:
- task scale:
- work orders:

## Evidence To Inspect

- `git status --short --branch`
- `git diff --name-status`
- `git diff --stat`
- `git diff --check`
- full relevant test output
- typecheck/build output
- generated file command evidence
- Hermes verification report
- ClaudeCode work order reports

## Required Checks

- Security and trust boundaries
- Architecture and state/data flow
- Tests and regression coverage
- Test evidence review
- API behavior and error handling
- UI/browser interaction evidence
- Generated file review
- Generated files were regenerated, not hand-edited
- Forbidden file review
- No unrelated staged files
- No `git add -A` feature staging
- Commit/PR readiness

## Verdict

Choose exactly one:
- PASS
- PASS_WITH_REQUIRED_CHANGES
- FAIL
- UNKNOWN

## Semantics

- PASS: diff may proceed to final report and optional commit/PR approval gate.
- PASS_WITH_REQUIRED_CHANGES: create repair work orders and return to Gate 4.
- FAIL: blocking issue; do not accept.
- UNKNOWN: evidence insufficient; do not accept.

Codex may still return PASS if only BASELINE_TECH_DEBT / OPTIONAL_POLISH / BACKLOG remain. Codex must not fail a task because of unrelated baseline project debt unless it blocks verification or was introduced by the current diff.

## Acceptance Authorization

- allow acceptance complete: yes/no
- reason:

`acceptance complete: true` is allowed only when verdict is PASS.

## Findings

| severity | category | finding | evidence | required fix |
| -------- | -------- | ------- | -------- | ------------ |

Categories: BLOCKER | TASK_RELATED | BASELINE_TECH_DEBT | OPTIONAL_POLISH | BACKLOG
