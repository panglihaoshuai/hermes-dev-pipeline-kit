# HERMES DEV PIPELINE WORK ORDER

## Source Intake

- source user prompt:
- Hermes normalized task brief:
- assumptions relevant to this work order:

## Objective

<One concrete vertical-slice objective.>

## Scope

- Mode: `auto_run`
- Project path:
- Work order id:
- Scale:
- Slice:
- Retry count:

## Planned File Touches

| file | action | allowed? | reason |
| ---- | ------ | -------- | ------ |

## Non-Goals

- Do not expand scope.
- Do not refactor unrelated code.
- Do not commit.
- Do not modify secrets, env files, lockfiles, CI/CD, deployment config, or generated files unless explicitly allowed.
- Do not ask the user to fill missing product requirements. If the work order is insufficient, return BLOCKED to Hermes with the exact gap.

## Reference Files

- <path>

## Allowed Files

- <path>

## Forbidden Files

- <path>

## Forbidden File Escalation

If a required file is forbidden, stop and return BLOCKED to Hermes with the exact reason and requested scope expansion. Do not ask the user for next steps.

## Required Matt skill

Required Matt skill: `<tdd | diagnose | prototype | to-issues | grill-me>`

You must use this skill during execution. If unavailable, report concrete evidence. If you do not use it, this work order is FAIL unless Hermes accepts the unavailable evidence.

## Required Skill Trace

- Required Matt skill:
- Why this skill:
- Expected evidence:
- What counts as missing evidence:
- Whether missing evidence blocks acceptance:

## Required Skill Evidence

- For `tdd`, output RED / GREEN / REFACTOR evidence.
- For `diagnose`, output hypothesis / test / finding / fix recommendation.
- For `prototype`, output variants considered / chosen variant / why.
- For `to-issues`, output the issue slices and dependencies.
- For `grill-me`, output the decision branches resolved.

ClaudeCode must not merely say "used tdd". It must provide evidence matching the skill.

If the required Matt skill evidence is missing, Hermes must return the work order as PARTIAL/FAIL unless explicitly waived with reason.

## ClaudeCode Plugin Routing

- UI/browser validation: use Playwright plugin if available.
- Code review request: use code-review plugin if available.
- GitHub issue/PR operation: use github plugin if available.

## Implementation Requirements

- Keep changes small.
- Stay within allowed files.
- Do not hand-edit generated files.
- For new behavior, add or update tests first when a valid seam exists.

## Validation Commands

| command | required? | notes |
| ------- | --------- | ----- |
| <command> | yes | <expected result> |

## Timeout Policy

If timeout or blocked, output a `timeout checkpoint`:
- files touched
- completed work
- incomplete work
- commands run
- last known error
- recommended next work order

Return the result to Hermes. Do not ask the user for next steps. Do not commit.

## Required Output Format

# ClaudeCode Work Order Result

## Status

DONE / PARTIAL / BLOCKED / FAILED

## Required Skill

- required:
- used:
- evidence:

## Skill Evidence

- Skill used:
- Skill evidence:
- Commands run:
- Exit codes:
- Files touched:
- Blocked / complete:

## Planned File Touches

| file | action | allowed? | reason |
| ---- | ------ | -------- | ------ |

## Files Modified

## Diff Summary

## Tests / Commands Run

| command | exit code | key output |
| ------- | --------- | ---------- |

## Risks / Unresolved

## Timeout / Checkpoint

## Recommended Next Step

Return this recommendation to Hermes only.
