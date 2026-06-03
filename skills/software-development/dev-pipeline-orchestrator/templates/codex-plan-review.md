# Codex Plan Review

## Review Target

- project:
- plan path:
- task scale:
- risk factors:

## Required Checks

- Is S/M/L classification correct?
- Is the scope narrow and testable?
- Are work orders vertical slices?
- Are allowed files and forbidden files clear?
- Are Required Matt skill choices correct?
- Are generated files handled by official commands?
- Are baseline before/after commands defined?
- Are acceptance criteria observable?
- Is Codex review required before implementation continues?

## Verdict

Choose exactly one:
- PASS
- PASS_WITH_REQUIRED_CHANGES
- FAIL
- UNKNOWN

## Semantics

- PASS: plan is safe to execute.
- PASS_WITH_REQUIRED_CHANGES: plan may execute only after Hermes applies the required work order changes below.
- FAIL: blocking plan flaw; do not execute Gate 4.
- UNKNOWN: evidence insufficient; do not execute Gate 4.

## Gate 4 Authorization

- allow Gate 4 execution: yes/no
- reason:

## Required Work Order Changes

| work order | required change | reason |
| ---------- | --------------- | ------ |

## Blocking Issues

| issue | evidence | required fix |
| ----- | -------- | ------------ |

## Notes

Codex review must be completed before L-level implementation begins.
