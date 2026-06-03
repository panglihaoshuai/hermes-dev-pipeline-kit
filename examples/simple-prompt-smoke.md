# 示例：简短提示词全流程 Trace

场景：用户说 `修一下 toast 不消失的问题`

本文档展示 pipeline 在处理一个简短、不完整提示词时的完整 Gate 输出。

---

## Gate 0: Intake + Classification

### 用户原始输入
```
修一下 toast 不消失的问题
```

### Hermes 展开后的标准化任务描述
```
- original prompt: "修一下 toast 不消失的问题"
- user goal: 修复 toast 通知组件不自动消失的问题
- inferred intent: small_fix
- inferred behavior: toast 应该在 N 秒后自动消失，但当前一直显示
- project path: ~/projects/my-app (从当前上下文推断)
- target artifact: toast 组件或 toast 的 timer/close 逻辑
- expected behavior: toast 显示后自动在 3-5 秒后消失
- non-goals: 不重构整个 toast 系统、不添加新 toast 类型
- likely files/modules: src/components/Toast.tsx 或 src/hooks/useToast.ts
- risk classification: S（如果只涉及单文件 timer 逻辑）
                            M（如果涉及 store + 组件 + 样式）
- verification commands: npm test -- --testPathPattern=toast
- Codex: S 级可选，M 级视风险
- GitHub publish: 未请求
- approval gates: commit 需审批
```

### 分类决策
```
scale: S 或 M（取决于实际涉及的文件数量）
reason: "修一下" → small_fix 意图默认 S/M
assumptions:
  - 假设项目有 toast 组件
  - 假设问题是 timer 逻辑而非 CSS 问题
  - 假设不需要修改 toast 的 CSS 动画
proceeded with defaults: YES
questions asked: 0
questions skipped: 3
  - "toast 是用什么库实现的？" → NON_BLOCKING_ASSUMPTION（可以从代码推断）
  - "消失时间应该多久？" → CLARIFY_IF_CONVENIENT（默认 3 秒）
  - "是指所有 toast 还是某种类型？" → NON_BLOCKING_ASSUMPTION（默认所有）
```

---

## Gate 1: Context Discovery

### 实际输出
```bash
$ git status --short --branch
## main
 M src/components/Toast.tsx

$ cat package.json | grep -A 5 '"scripts"'
"scripts": {
  "test": "vitest run",
  "build": "vite build",
  "lint": "eslint src/",
  "typecheck": "tsc --noEmit"
}

$ find src -name "*toast*" -o -name "*Toast*"
src/components/Toast.tsx
src/components/Toast.test.tsx
src/hooks/useToast.ts
src/hooks/useToast.test.ts

$ cat src/components/Toast.tsx | head -30
# (读取 Toast 组件源码，发现 setTimeout 逻辑)
```

### Hermes 发现
```
- toast 组件: src/components/Toast.tsx (有 setTimeout)
- toast hook: src/hooks/useToast.ts (管理 toast 状态)
- 测试: Toast.test.tsx, useToast.test.ts
- 可能的问题: setTimeout 清理逻辑或 duration 参数
- 归类为 S 级（单文件 bug，无 API/store/routing/auth）
```

---

## Gate 2: Plan (S 级可跳过)

S 级快速路径，直接进入 Gate 4。

---

## Gate 3: Work Order (S 级内联)

```
WO-1: 修复 toast 不消失的问题

objective: 修复 toast 通知不自动消失的 bug
scope: src/components/Toast.tsx（如果问题在组件层）
       或 src/hooks/useToast.ts（如果问题在 hook 层）
non-goals: 不重构 toast 系统、不添加新功能
allowed files: src/components/Toast.tsx, src/hooks/useToast.ts
forbidden files: package.json, tsconfig.json, vite.config.ts
  → "If you technically must modify a forbidden file, STOP and report."
Required Matt skill: diagnose
validation commands:
  - npm test -- --testPathPattern=toast
  - npm run typecheck
timeout checkpoint: yes
```

---

## Gate 4: ClaudeCode Execution

### ClaudeCode 输出
```
=== Diagnosis ===
Root cause: useEffect cleanup in Toast.tsx does not clear the timeout.
When component re-renders, old timeout continues and new timeout is set,
but the old one is never cleared. However, the REAL bug is: the
setTimeout callback references a stale `isVisible` state.

=== Fix ===
Changed src/components/Toast.tsx:
- Added cleanup in useEffect return
- Used ref to track timeout ID
- Ensured cleanup on unmount

=== TDD Evidence ===
(ClaudeCode 用 diagnose skill，不是 tdd)

=== Planned File Touches ===
| File | Allowed | Reason |
|------|---------|--------|
| src/components/Toast.tsx | yes | bug fix target |

=== Modified Files ===
- src/components/Toast.tsx (+8, -3)

=== Commands Run ===
- npm test -- --testPathPattern=toast: exit 0 (4/4 pass)
- npm run typecheck: exit 0

=== Risks ===
None identified.

=== Required skill used ===
diagnose: YES
skill evidence: Root cause analysis provided above.
```

---

## Gate 5: ClaudeCode Self-Check

ClaudeCode 已在 Gate 4 输出中包含 self-check 信息。

---

## Gate 6: Hermes Verification

### 实际输出
```bash
$ git diff --name-status
M	src/components/Toast.tsx

$ git diff --check
(exit 0, no whitespace errors)

$ git diff --stat
 src/components/Toast.tsx | 11 ++++++------
 1 file changed, 8 insertions(+), 3 deletions(-)

$ npm test -- --testPathPattern=toast
 ✓ Toast (4 tests) 48ms
 ✓ useToast (3 tests) 12ms
 Test Files  2 passed (2)
      Tests  7 passed (7)

$ npm run typecheck
(exit 0)
```

### 验证结果
```
allowed files check: PASS (only src/components/Toast.tsx modified)
forbidden files check: PASS (no forbidden files modified)
tests: PASS (7/7)
typecheck: PASS
diff format: PASS

→ proceed to Gate 8
```

---

## Gate 7: Codex Diff Review

S 级，Codex 可选。
```
S 级, minimal risk, 单文件 bug fix, Codex review not required per Gate 7 rules.
```

---

## Gate 8: dev-pipeline-report

```
## Executive Status
- pipeline mode: auto_run
- execution complete: true
- verification complete: true
- acceptance complete: true
- Codex verdict: not required (S 级)
- commit/PR status: pending approval
- current gate: 9
- stopped reason: commit approval required
- next automatic action: ask user for commit approval
- user action required: yes
- if user action required, why: commit 需要用户批准

## Role Performance
- Hermes role performed:
  - product manager: yes (意图识别 + 分类)
  - architect: no (S 级无需架构设计)
  - QA verifier: yes (Gate 6 验证)
- ClaudeCode role performed:
  - implementation worker: yes (WO-1 执行)
- Codex role: not used (S 级可选)

## Task Classification
- scale: S
- reasons: 单文件 bug fix，无 API/store/routing/auth
- risk level: low

## Intake Quality
- original user prompt: "修一下 toast 不消失的问题"
- normalized task brief: (见 Gate 0 展开)
- assumptions made: 3 (见 Gate 0)
- questions asked: 0
- questions skipped: 3
- proceeded with defaults: yes
- ambiguity level: medium
- product direction confidence: high

## Work Orders
| id | owner | required skill | files | retry | status | evidence |
|----|-------|---------------|-------|-------|--------|----------|
| WO-1 | ClaudeCode | diagnose | Toast.tsx | 0 | PASS | root cause + fix + tests |

## Verification Evidence
| command | exit code | key output | pass/fail |
|---------|-----------|------------|-----------|
| git diff --name-status | 0 | M Toast.tsx | PASS |
| git diff --check | 0 | (clean) | PASS |
| npm test toast | 0 | 7/7 pass | PASS |
| npm run typecheck | 0 | (clean) | PASS |

## Diff Summary
- files changed: 1 (src/components/Toast.tsx)
- generated files: 0
- explicit staged files only: YES

## Final Decision
ACCEPTED

## Follow-up Backlog
| id | category | description | related? | blocker? | handling |
|----|----------|-------------|----------|----------|----------|
| (none) | | | | | |

- safe to stop: yes
- safe to commit: yes
- safe to push/PR: NO (需要用户批准)
- follow-up work required now: no
```

---

## Gate 9: Commit Approval

### Pipeline 暂停
```
1 个文件已修改: src/components/Toast.tsx
Codex: S 级不需要
验证: 全部 PASS
是否批准 commit?
```

### 用户批准后
```bash
git add src/components/Toast.tsx
git commit -m "fix: toast notification not auto-dismissing

Clear timeout on useEffect cleanup to prevent stale timer.
Added ref-based timeout tracking for proper cleanup on unmount."
```

---

## 全流程总结

```
用户: "修一下 toast 不消失的问题"
  │
  ▼
Gate 0: 意图识别 → small_fix → S 级
  │
  ▼
Gate 1: 发现 Toast.tsx + useToast.ts + tests
  │
  ▼
(S 级跳过 Gate 2, 3)
  │
  ▼
Gate 4: ClaudeCode (diagnose) → 找到 root cause → 修复 → tests PASS
  │
  ▼
Gate 6: Hermes 验证 → git diff + tests + typecheck → 全部 PASS
  │
  ▼
(S 级跳过 Gate 7)
  │
  ▼
Gate 8: 报告 → ACCEPTED
  │
  ▼
Gate 9: 暂停 → 等待用户批准 commit
```

总耗时估计：< 5 分钟
