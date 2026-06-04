# Final Evidence Report

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
