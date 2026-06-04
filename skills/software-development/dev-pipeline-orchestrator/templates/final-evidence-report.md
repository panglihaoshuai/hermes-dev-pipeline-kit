# Final Evidence Report

# Dev Pipeline Evidence Report

## 负责人摘要

- 任务：
- 当前状态：绿 / 黄 / 红
- 当前阶段：
- 完成度：
  - 需求收集：
  - 方案计划：
  - 工单拆分：
  - ClaudeCode 执行：
  - Hermes 验证：
  - Codex 审查：
  - Commit / Push / PR 审批：
- 使用情况：
  - Hermes：
  - ClaudeCode：
  - Codex：
- 关键证据：
  - 测试：
  - policy-check：
  - doctor / ci-local：
  - Codex：
- 最大风险：
- 需要你决定：
- 下一步：

## 阶段更新

- 上一阶段：
- 当前阶段：
- 正在使用的 skill / 工具：
- 本阶段目标：
- 进入下一阶段的条件：
- 是否需要你现在决策：是 / 否

## 责任归因

| 事项 | 责任方 | 状态 | 证据 | 是否阻塞 |
|---|---|---|---|---|
| 需求边界 | Hermes / 用户 | | normalized task brief | 否 |
| 代码实现 | ClaudeCode | | files changed + commands | 否 |
| 测试验证 | Hermes / ClaudeCode | | exit code | 否 |
| Codex 审查 | Codex | 完成 / 跳过 | verdict / reason | 否 |
| commit 审批 | 用户 | 等待 / 不需要 | approval gate | 是/否 |

## 待你审批

| 编号 | 审批事项 | 为什么需要你批 | 默认建议 | 不批准的后果 |
|---|---|---|---|---|
| A1 | 是否 commit | 代码已验证，需要落库 | 批准 | 当前改动停留在 working tree |

If no approval is needed, state: `待你审批：无。下一步会自动继续。`

## Executive Status

- pipeline mode:
- execution complete:
- verification complete:
- acceptance complete:
- Codex verdict:
- commit/PR status:
- current gate:
- stopped reason:
- user action required:
- next automatic action:

## Task Summary

- goal:
- project:
- scale:
- risk factors:

## Intake Quality

- original user prompt:
- normalized task brief:
- assumptions made:
- questions asked:
- questions skipped and why:
- proceeded with defaults: yes/no
- ambiguity level: low / medium / high
- product direction confidence: high / medium / low

## Files Changed

| file | status | owner | notes |
| ---- | ------ | ----- | ----- |

## Work Orders

| id | required skill | status | evidence |
| -- | -------------- | ------ | -------- |

## 中文 Skill Trace / 技能使用证据

| 层级 | 使用的 skill / 工具 | 计划使用 | 实际使用 | 证据 | 结论 |
|---|---|---:|---:|---|---|
| Hermes 入口 | dev-pipeline-orchestrator | 是 | 是 | 完成需求标准化、分级、工单拆分、验证、报告 | PASS |
| Hermes / gstack | writing-plans | 是/否 | 是/否 | 输出范围、非目标、验收标准 / 跳过原因 | PASS/SKIPPED |
| Hermes / gstack | plan-eng-review | 是/否 | 是/跳过 | 风险审查 / 跳过原因 | PASS/SKIPPED |
| ClaudeCode / Matt | tdd | 是/否 | 是/否 | RED / GREEN / exit code | PASS/PARTIAL/MISSING |
| ClaudeCode / Matt | diagnose | 是/否 | 是/否 | hypothesis / test / finding / fix | PASS/PARTIAL/MISSING |
| ClaudeCode / Matt | prototype | 是/否 | 是/否 | variants / chosen / reason | PASS/PARTIAL/MISSING |
| Codex | plan review | 是/否 | 是/否 | PASS / 跳过原因 | PASS/SKIPPED/FAIL |
| Codex | diff review | 是/否 | 是/否 | PASS / 跳过原因 | PASS/SKIPPED/FAIL |
| 本地校验 | policy-check / doctor / ci-local | 是 | 是/否 | command + exit code | PASS/SKIPPED/FAIL |

### 缺失证据

- 缺失的 Matt skill evidence：
- 缺失的 gstack evidence：
- 跳过的 skill：
- 跳过原因：
- 对验收的影响：无 / 部分 / 阻塞

If required evidence is missing, report must not say `acceptance complete: yes`.

## Skill Trace

| layer | skill/tool | planned | used | evidence | verdict |
|---|---|---:|---:|---|---|
| Hermes entry | dev-pipeline-orchestrator | yes | yes | intake/classification/work orders/report | PASS |
| Hermes/gstack | plan-eng-review | yes/no | yes/no | plan/risk/acceptance evidence | PASS/PARTIAL/SKIPPED |
| Hermes/gstack | investigate | yes/no | yes/no | hypothesis/evidence/conclusion | PASS/PARTIAL/SKIPPED |
| Hermes/gstack | review | yes/no | yes/no | diff/issues/verdict | PASS/PARTIAL/SKIPPED |
| Hermes/gstack | ship | yes/no | yes/no | release readiness/approval state | PASS/PARTIAL/SKIPPED |
| ClaudeCode/Matt | tdd | yes/no | yes/no | RED/GREEN/exit code | PASS/PARTIAL/MISSING |
| ClaudeCode/Matt | diagnose | yes/no | yes/no | hypothesis/test/finding/fix | PASS/PARTIAL/MISSING |
| ClaudeCode/Matt | prototype | yes/no | yes/no | variants/chosen/reason | PASS/PARTIAL/MISSING |
| Codex | plan review | yes/no | yes/no | verdict | PASS/SKIPPED/FAIL |
| Codex | diff review | yes/no | yes/no | verdict | PASS/SKIPPED/FAIL |
| policy-check | policy-check.sh | yes/no | yes/no | command + exit code | PASS/SKIPPED/FAIL |
| doctor/ci-local | doctor.sh / ci-local.sh | yes/no | yes/no | command + exit code | PASS/SKIPPED/FAIL |

- missing skill evidence:
- skipped skills:
- skipped reason:
- acceptance impact: none / partial / blocking

## Commands Run

| command | exit code | key output | pass/fail |
| ------- | --------- | ---------- | --------- |

## Generated Files

- generated files touched:
- official generation command:
- Codex approval if manual:

## Codex Review

- plan review:
- Codex plan review verdict:
- diff review:
- Codex diff review verdict:
- blocking issues:
- verdict:

## Commit / PR

- branch:
- explicit staged files only:
- commit:
- PR:
- rollback command:

## GitHub / Publish Readiness

- publish requested: yes/no
- GitHub remote present: present/missing/unknown
- gh auth available: available/unavailable/unknown
- GitHub skill/plugin available: available/unavailable/unknown
- package manager:
- build command:
- test command:
- project protocol files:
  - README.md: present/missing/intentionally skipped
  - CLAUDE.md: present/missing/intentionally skipped
  - AGENTS.md: present/missing/intentionally skipped
  - .github/workflows: present/missing/intentionally skipped
- safe to commit: yes/no
- safe to push/create PR: yes/no
- user approval required: yes/no
- recommended next action:

## Final Decision

Choose exactly one:
- ACCEPTED
- NOT ACCEPTED
- PARTIAL
- BLOCKED

## Follow-up Backlog

| id | category | description | related to current task? | blocker? | recommended handling |
| -- | -------- | ----------- | ------------------------ | -------- | -------------------- |

## Safety Assessment

- safe to stop: yes/no
- safe to commit: yes/no
- safe to push/PR: yes/no
- follow-up work required now: yes/no
