# Hermes Verification Report

## 负责人摘要

- 任务：
- 当前状态：绿 / 黄 / 红
- 当前阶段：Hermes 验证
- 当前最大风险：
- 需要你决定：是 / 否
- 下一步：

## 阶段更新

- 上一阶段：ClaudeCode 工单执行
- 当前阶段：Hermes 验证
- 正在使用的 skill / 工具：dev-pipeline-orchestrator / policy-check / test commands
- 本阶段目标：验证当前 diff 是否满足验收标准
- 进入下一阶段的条件：验证通过，或记录阻塞问题
- 是否需要你现在决策：是 / 否

## Scope

- project:
- work order:
- scale:
- mode:
- retry count:
- allowed files:
- forbidden files:

## Baseline Before

| command | exit code | key output |
| ------- | --------- | ---------- |

## Verification Commands

| command | exit code | key output | pass/fail |
| ------- | --------- | ---------- | --------- |
| `git diff --name-status` | | | |
| `git diff --check` | | | |
| `git diff --stat` | | | |

## Checks

- allowed files check:
- forbidden files check:
- untracked files check:
- tracked files check:
- generated files check:
- official generation command:
- entrypoint integration check:
- targeted tests:
- relevant typecheck:
- baseline before/after comparison:
- next automatic action:

## Baseline Debt Separation

Hermes verification must separate findings into three categories:

1. **current diff verification** — checks against files changed by the current task
2. **whole project baseline** — full-project checks (tsc, lint, build) that may surface pre-existing issues
3. **unrelated historical debt** — pre-existing failures not caused by current diff

If whole-project checks fail because of known baseline issues but current-diff checks pass, verification may be PASS_WITH_BASELINE_DEBT.

| category | check | result | caused by current diff? |
| -------- | ----- | ------ | ----------------------- |
| current diff | | | |
| whole project baseline | | | |
| unrelated historical debt | | | |

Hermes must record baseline debt but must not automatically create repair work orders unless it blocks the current task.

## GitHub / Publish Verification

Complete this section only when GitHub publishing, package upload, repo creation, push, PR, deployment, or project bootstrap was explicitly requested.

### Repository Discovery

| command | exit code | key output |
| ------- | --------- | ---------- |
| `git status --short --branch` | | |
| `git remote -v` | | |
| `git branch --show-current` | | |
| `git log --oneline -5` | | |

### Toolchain Discovery

| command | exit code | key output |
| ------- | --------- | ---------- |
| `which gh || true` | | |
| `gh auth status || true` | | |

### Package / Build Discovery

- package manager:
- framework:
- build command:
- test command:
- lint command:
- typecheck command:
- package/release command:

### Project Protocol Files

- README.md:
- CLAUDE.md:
- AGENTS.md:
- .github/workflows:

### Publish Safety

- no secrets staged:
- no forbidden files staged:
- explicit staged files only:
- remote/repo creation approval:
- push/PR approval:

## Decision

Choose one:
- proceed to next work order
- return to ClaudeCode
- request Codex review
- stop for user action
- stop for blocking issue
- proceed with baseline debt (current diff verified, unrelated issues recorded as backlog)

Hermes must not mark `acceptance complete` here.
