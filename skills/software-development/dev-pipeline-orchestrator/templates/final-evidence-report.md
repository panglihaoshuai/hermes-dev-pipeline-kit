# Final Evidence Report

# Dev Pipeline Evidence Report

<!--
Chinese Report Scale Policy:
- report_scale: compact for S-level small fixes.
- report_scale: standard for M-level feature work.
- report_scale: full for L-level / recovery / publish / generated-file / security / API-store-UI / release tasks.
- Failure/blocker always requires Responsibility Trace.
- Commit / push / PR / publish / dependency install / destructive action / global config change always requires Approval Inbox.
-->

## Report Scale

- report_scale: compact / standard / full
- owner_summary_required: true / false
- stage_update_required: true / false
- responsibility_trace_required: true / false
- approval_inbox_required: true / false

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

## Compact / Standard / Full Examples

### Compact S-level

```markdown
## 负责人摘要

- 任务：在 /tmp/hermes-real-smoke 中实现 add(a,b) 并验证
- 当前状态：绿
- 当前阶段：证据报告输出
- 最大风险：无阻塞风险，临时目录已清理
- 需要你决定：否
- 下一步：结束本次 smoke

## 阶段更新

- 上一阶段：Hermes 验证
- 当前阶段：证据报告输出
- 使用的 skill / 工具：dev-pipeline-orchestrator、node --test
- 是否需要你现在决策：否

## 技能使用证据

| 层级 | skill / 工具 | 证据 | 结论 |
|---|---|---|---|
| Hermes | dev-pipeline-orchestrator | S 级 compact report，创建并验证 add.js/test.js | PASS |
| ClaudeCode | not used | smoke 小任务由 Hermes 直接执行 | SKIPPED |
| Codex | diff review | S 级小修，未触发 Codex review | SKIPPED |

## 责任归因

| 事项 | 责任方 | 状态 | 证据 |
|---|---|---|---|
| 实现 | Hermes | 完成 | add.js 创建 |
| 验证 | Hermes | 完成 | node --test exit 0 |
| 清理 | Hermes | 完成 | /tmp/hermes-real-smoke 已删除 |

## 待你审批

无。
```

### Standard M-level

```markdown
## 负责人摘要
列出任务、状态、当前阶段、最大风险、是否需要用户决定、下一步。

## 阶段更新
只列主要 Gate 切换。

## 中文 Skill Trace / 技能使用证据
输出表格。

## 责任归因
仅当有风险、修复、失败或阻塞时输出。

## 待你审批
仅当需要 commit / push / PR / install / global config 等审批时输出。
```

### Full L-level / recovery / publish

```markdown
## 负责人摘要
输出完整进度、证据、风险和下一步。

## 阶段更新
列出每个主要 Gate。

## 中文 Skill Trace / 技能使用证据
输出完整表格。

## 责任归因
必须输出。

## 待你审批
必须输出；无事项也写“无”。

## Codex Review
输出 plan/diff review。

## Verification Evidence
输出 policy-check / doctor / ci-local。

## Follow-up Backlog
输出 backlog / baseline debt 分类。
```

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
