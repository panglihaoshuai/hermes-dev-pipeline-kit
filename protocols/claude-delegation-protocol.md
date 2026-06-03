## Hermes Delegation Protocol

When a task is delegated by Hermes `dev-pipeline-orchestrator`:

1. Read the work order fully before making changes.
2. Use the required Matt Pocock skill:
   - feature: `tdd`
   - bug: `diagnose`
   - uncertain UI/state: `prototype`
   - issue split: `to-issues`
   - design tradeoff: `grill-me`
3. Stay within allowed files.
4. Do not modify forbidden files.
5. Do not hand-edit generated files unless explicitly allowed.
6. Do not commit.
7. Run required validation commands.
8. Report exit codes.
9. If timeout or blocked, output checkpoint.
10. Do not claim complete without tests or a clear documented reason.

When delegated by Hermes `dev-pipeline-orchestrator` in `auto_run`:

1. ClaudeCode must not ask the user for next steps.
   - Exact rule: do not ask the user for next steps.
2. ClaudeCode must return structured result to Hermes.
3. If blocked, return BLOCKED with exact reason and requested scope expansion.
4. Do not modify forbidden files.
5. Do not commit.
6. Do not call Codex directly unless the Hermes work order explicitly asks.
7. Do not silently change package/config/test runner files unless they are allowed.
8. If a required file is forbidden, stop and request scope expansion.
9. Required Matt skill evidence is mandatory.
10. For `tdd`, output RED / GREEN / REFACTOR evidence.
11. For `diagnose`, output hypothesis / test / finding / fix recommendation.
12. For `prototype`, output variants considered / chosen variant / why.
13. Always include command exit codes.

Required output format:

```markdown
# ClaudeCode Work Order Result

## Status

DONE / PARTIAL / BLOCKED / FAILED

## Required Skill

- required:
- used:
- evidence:

## Files Modified

## Diff Summary

## Tests / Commands Run

| command | exit code | key output |
| ------- | --------- | ---------- |

## Risks / Unresolved

## Timeout / Checkpoint

## Recommended Next Step
```
