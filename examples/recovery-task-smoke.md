# Recovery Task Smoke Test

## 场景

用户说："恢复之前那个没做好的功能"

## 预期 Pipeline 行为

### Gate 0: Intake + Classification

```
intent: recovery
scale: L
reason: previous failed attempt / recovery task
Codex: required (plan review + diff review)
mode: auto_run
```

### Gate 1: Context Discovery

```bash
git status --short --branch
git log --oneline -10
```

识别：
- 当前分支
- 最近的失败功能分支或 commit
- 涉及的文件和模块

### Gate 1.5: Baseline Verification

```bash
npx tsc --noEmit
npm run build
npm test
npm run lint
```

关键：区分 baseline 已有错误 vs 当前功能引入的错误。
不能只 grep 功能名。统计总错误数，识别哪些文件在功能范围内。

### Gate 2: Code-State Audit（5 层审查）

1. **API layer**: provider reuse, SSE/chunk handling, error handling, API key safety, response schema stability, test seam existence
2. **Store layer**: state flow correctness, mutation safety, stale reference handling, malformed data resilience, coupling
3. **UI layer**: all states rendered (loading/streaming/error/empty/completed), adopt/undo consistency, panel close cleanup, i18n, testable selectors
4. **Integration**: entry point correctness, i18n key completeness, generated file status
5. **Tests**: API smoke, store unit, UI smoke, E2E, mock mechanism

### Gate 3: Work Order Split（Recovery Pattern）

```
WO-1 (always first): Generated file / routeTree / config recovery
  → diagnose, read-only, find official re-gen command

WO-2 through WO-N: Hardening + tests per layer
  → tdd or prototype

WO-last: E2E with mocked external dependencies
  → diagnose
```

每个 recovery WO 必须包含：
- Planned File Touches table（allowed? + reason）
- TDD Evidence format（RED exit ≠ 0, GREEN exit = 0）
- Forbidden file clause with "STOP and report" requirement

### Gate 3.5: Codex Plan Review（必须）

L-level recovery 必须 Codex plan review。
PASS → Gate 4
PASS_WITH_REQUIRED_CHANGES → 更新 work orders → Gate 4
FAIL → 停

### Gate 4-6: Execution + Verification

逐个 work order 执行，每个后 Hermes 验证：
- git diff --name-status
- git diff --check
- targeted tests
- allowed files check

### Gate 7: Codex Diff Review（必须）

L-level recovery 完成后必须 Codex diff review。
PASS → Gate 8
FAIL → 停

### Gate 8: dev-pipeline-report

包含完整 evidence：baseline before/after, 修复内容, 测试结果, Codex verdict。

### Gate 9: Commit Approval

停止等用户批准。

## 预期报告格式

```markdown
# Recovery Pipeline Report

- verdict: PASS / PARTIAL / BLOCKED
- scale: L
- recovery type: previous failed attempt
- baseline errors before: N
- baseline errors after: N
- feature-introduced errors: 0
- files recovered:
- layers audited: 5/5
- work orders: N
- Codex plan review: PASS
- Codex diff review: PASS
- tests: X/Y pass
- safe to commit: yes/no
- stopped reason: (if blocked)
```

## PASS 条件

1. 进入 L-level recovery 流程
2. Gate 1.5 baseline verification 完成
3. Gate 2 五层 code-state audit 完成
4. Recovery work order patterns 正确使用
5. Codex plan review PASS
6. Codex diff review PASS
7. 区分 baseline vs feature-introduced errors
8. 停在 commit approval
