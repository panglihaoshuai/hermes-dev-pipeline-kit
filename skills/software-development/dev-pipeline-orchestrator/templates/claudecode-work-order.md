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

## 责任边界 / Responsibility Boundary

- 用户 / Owner：目标提供、关键产品方向决策、commit / push / PR / publish 审批。
- Hermes：需求标准化、方案设计、S/M/L 分级、工单拆分、allowed / forbidden files、验证、报告。
- ClaudeCode：代码实现、测试编写、命令执行、Matt skill evidence、文件修改回执。
- Codex：plan review、diff review、高风险审查、release readiness review。

ClaudeCode must not redefine the product goal or approval policy. Return BLOCKED if the work order lacks enough scope to execute safely.

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

## 中文工单说明 / Chinese Work Order Disclosure

Hermes must show this summary to the user before delegation:

```text
当前阶段：ClaudeCode 工单执行
我要把任务交给 ClaudeCode，但 ClaudeCode 只负责执行，不负责重新定义需求。

本次工单要求：
- ClaudeCode 必须使用 Matt skill：<tdd | diagnose | prototype | to-issues | grill-me>
- 为什么使用这个 skill：<原因>
- 允许修改文件：
  - <path>
- 禁止修改文件：
  - <path>
- 必须运行验证命令：
  - <command>
- 如果缺少对应 skill evidence，Hermes 不允许标记验收完成。
```

Skill reason examples:

- `tdd`：这是功能开发，需要先写测试再实现。
- `diagnose`：这是 bug / 失败恢复任务，需要先提出假设、收集证据、定位原因，再修复。
- `prototype`：当前 UI/交互方案不确定，需要比较方案后再实现。

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

## TDD Evidence Requirements (when required_matt_skill=tdd)

1. RED phase: Create test, run test, record failure (exit code != 0)
2. GREEN phase: Implement, run test, record success (exit code = 0)
3. If RED is not applicable, provide `red_not_applicable_reason`
4. Output: commands, exit codes, expected failures

ClaudeCode must not merely say "used tdd". It must provide evidence matching the skill.

If the required Matt skill evidence is missing, Hermes must return the work order as PARTIAL/FAIL unless explicitly waived with reason.

## ClaudeCode Result Contract (v0.3)

ClaudeCode must submit raw execution receipt data as `raw/claudecode-result.json` or return exactly equivalent JSON for Hermes to place there.

Minimum shape:

```json
{
  "work_order_id": "WO-1",
  "status": "completed|blocked|partial",
  "required_matt_skill": "tdd|diagnose|prototype|to-issues|grill-me|none",
  "matt_evidence": {
    "red": "",
    "red_exit_code": null,
    "red_not_applicable_reason": "",
    "green": "",
    "green_exit_code": null,
    "commands": []
  },
  "files_touched": [],
  "commands_run": [],
  "blocked": false,
  "notes": ""
}
```

Forbidden in ClaudeCode result:

```json
{
  "acceptance": {
    "complete": true
  }
}
```

ClaudeCode submits raw evidence only. Harness generates `generated/run-state.json`.

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
