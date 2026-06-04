# 常见问题排查

本文档列出 hermes-dev-pipeline-kit 使用中最常见的问题及解决方法。

---

## 1. ClaudeCode 违反 Forbidden Files

### 症状
Gate 6 验证时发现 ClaudeCode 修改了 forbidden files（如 package.json）。

### 典型场景
ClaudeCode 需要 ESM imports → 自动往 package.json 加 `"type": "module"` → 违反 forbidden files 列表。

ClaudeCode 认为修改是"技术上必要的" → 优先"让它跑起来"而不是遵守约束。

### 根因
ClaudeCode 不会自我报告 forbidden file violations。它会把修改当作成功的一部分。

### 解决
1. **Gate 6 永远运行 `git diff --name-status`**——不要信任 ClaudeCode 的自述
2. **每个 WO 必须包含 STOP 条款**：
   > "If you technically must modify a forbidden file, STOP and report the need. Do not modify it. Hermes will decide."
3. **如果 ClaudeCode 还是违反了**：WO FAIL → 退回重做 → 2 次失败后请求 Codex 诊断

### 预防
- 使用 CommonJS (`require`/`module.exports`) 而非 ESM (`import`/`export`)，避免触发 package.json 修改
- 在 WO 中明确列出所有 forbidden files

---

## 2. delegate_task Timeout

### 症状
delegate_task 返回 "timed out after 600.0s"。

### 关键判断
**timeout ≠ failure。** delegate_task 超时后，subagent 可能已经完成了工作。

### 排查步骤
```bash
# 1. 检查预期文件是否已创建
ls -la <expected output file>

# 2. 如果文件存在，运行验证命令
npx vitest run <test file>
# 或
npm test -- --testPathPattern=<pattern>

# 3. 如果文件存在且测试通过 → 视为成功（附 timeout 说明）
# 4. 如果文件不存在 → 需要重试
```

### 重试策略
如果确实需要重试：
- 用更精简的 prompt——原始 prompt 可能太长/复杂，在 timeout 窗口内完不成
- 预读参考文件，将关键上下文直接传入，减少 subagent 的文件读取开销
- 考虑拆分为更小的 WO

### 实际案例
在一次真实 pipeline run 中：
- WO-1: timed out, 0 files created → 重试后 245s 成功
- WO-2: timed out, 但文件已完成且 12 个测试通过 → 视为成功

---

## 3. TDD 未被遵循

### 症状
ClaudeCode 同时创建了测试文件和实现文件，没有先验证 RED（测试失败）再验证 GREEN（实现通过）。

### 典型表现
- RED exit code = 0（测试直接通过了，说明实现已经存在）
- 测试文件和实现文件在同一个 WO 中创建
- 没有 "RED → GREEN → REFACTOR" 的证据链

### 根因
TDD 不是自执行的。即使 WO 里写了 "Required Matt skill: tdd"，ClaudeCode 可能还是会跳过 RED 阶段。

### 解决
1. **M/L 级任务拆分为两个 WO**：
   - WO-A: 只写测试，验证 FAIL（RED exit ≠ 0）
   - WO-B: 写实现，验证 PASS（GREEN exit = 0）
2. **S 级任务**：接受快捷方式，但在验证中注明

### 预防
- 在 WO 中要求 Strict TDD Evidence Format
- Gate 6 验证 RED exit code ≠ 0

---

## 3.1 Skill Trace 缺失或证据不完整

### 症状
`policy-check.sh` 输出：
```
FAIL  skill-trace-evidence
```

### 常见原因
- `acceptance.complete` 是 `true`，但 run-state 没有 `skill_trace`
- Work order 要求 `required_matt_skill`，但没有对应 `skill_evidence`
- `skill_trace.claudecode_skills` 里 `reported=false` 或 `verdict=MISSING`
- gstack skill 标记为 used，但没有 evidence
- required Codex gate 没有 used 或 verdict 不是 PASS / PASS_WITH_REQUIRED_CHANGES

### 解决
1. 如果任务还没验收完成，把 `acceptance.complete` 设为 `false`，并记录当前 gate。
2. 如果 ClaudeCode 确实用了 Matt skill，补充对应证据：
   - `tdd`: RED/GREEN evidence + validation exit code
   - `diagnose`: hypothesis/test/finding/fix
   - `prototype`: variants/chosen/reason
   - `to-issues`: issue breakdown/acceptance criteria/priority
   - `grill-me`: challenge questions/decisions changed or confirmed
3. 如果 skill 被跳过，填写 skipped reason 和 acceptance impact。
4. 如果证据缺失且无法补齐，最终决策应为 PARTIAL 或 BLOCKED，而不是 ACCEPTED。

### 边界
Skill Trace 是披露和证据合约，不证明隐藏 runtime invocation。除非 Hermes 或 ClaudeCode 暴露机器可读 trace，否则只能验证报告中的证据是否完整一致。

---

## 4. jest-dom Matcher 类型错误

### 症状
`tsc --noEmit` 报大量错误：
```
Property 'toBeInTheDocument' does not exist on type 'Assertion<HTMLElement>'
Property 'toHaveTextContent' does not exist on type 'Assertion<HTMLElement>'
Property 'toBeVisible' does not exist on type 'Assertion<HTMLElement>'
```

### 根因
ClaudeCode 写测试时默认使用 `@testing-library/jest-dom` matchers（`toBeInTheDocument`、`toHaveTextContent`、`toBeVisible`），因为库已安装且 vitest-setup.ts 导入了它。这些在运行时能工作，但 tsconfig 没有包含 jest-dom 的类型声明，导致 tsc 类型错误。

### 排查
```bash
# 检查项目现有测试是否使用 jest-dom matchers
grep -r "toBeInTheDocument\|toHaveTextContent\|toBeVisible" src/**/*.test.*
```

如果现有测试不使用这些 matcher → ClaudeCode 不应该用。

### 解决
在 WO 中明确指示：
> "Use vitest-native assertions only. Do NOT use jest-dom matchers (toBeInTheDocument, toHaveTextContent, etc.). Use `expect(el).toBeTruthy()` and `expect(el?.textContent).toContain(...)` instead."

### 替代表达
| jest-dom matcher | vitest-native 替代 |
|-----------------|-------------------|
| `expect(el).toBeInTheDocument()` | `expect(el).toBeTruthy()` |
| `expect(el).toHaveTextContent("x")` | `expect(el?.textContent).toContain("x")` |
| `expect(el).toBeVisible()` | `expect(el).toBeTruthy()` |

---

## 5. ESM vs CommonJS package.json 冲突

### 症状
ClaudeCode 使用 `import`/`export` 语法 → 需要 `"type": "module"` → 修改了 package.json（forbidden file）。

### 根因
ESM requires `"type": "module"` in package.json. CommonJS 不需要任何 package.json 修改。

### 解决
**优先使用 CommonJS：**
```javascript
// ✅ CommonJS — 不需要修改 package.json
const { something } = require('./module');
module.exports = { result };

// ❌ ESM — 需要 "type": "module"（forbidden）
import { something } from './module';
export { result };
```

### 适用场景
- Smoke tests / 简单 Node.js 任务
- 任何不想碰 package.json 的场景

### 不适用场景
- 现有项目已使用 ESM → 不需要切换
- 框架默认 ESM（如 Vite、Next.js）→ 遵循项目约定

---

## 6. Codex 返回 FAIL/UNKNOWN

### 症状
Gate 3.5 或 Gate 7 的 Codex review 返回 FAIL 或 UNKNOWN。

### 行为
- `acceptance complete` 必须为 false
- Pipeline 停止
- 报告 blocking issues

### 排查
1. 查看 Codex 的 blocking issues 列表
2. 确认是计划问题还是实现问题
3. 如果是计划问题（Gate 3.5）→ 修改计划 → 重新提交 Codex
4. 如果是实现问题（Gate 7）→ 创建修复 WO → ClaudeCode 修复 → 重新验证

### 何时请求用户决定
- Codex 反复 FAIL 且原因不清楚
- Codex 要求的修改超出任务 scope
- Codex 指出的问题需要产品决策

---

## 7. Generated File 被手改

### 症状
`git diff --name-status` 显示 generated file 被修改，且没有证据表明使用了官方生成命令。

在 v0.2 中，这不是 warning。`policy-check.sh` 必须返回 FAIL，即使任务是 S 级。

### 典型 generated files
- `routeTree.gen.ts`（TanStack Router）
- `*.generated.ts`（GraphQL codegen）
- API 客户端（openapi-generator）
- lockfiles

### 处理
```
1. 查找官方生成命令
   - 检查 package.json scripts
   - 检查构建工具配置
   - 检查 README

2. 有官方命令
   → 创建 WO 用官方命令重新生成
   → 验证重新生成后功能正确

3. 没有官方命令
   → 请求 Codex 批准手动修复
   → 证据报告必须解释为什么
```

---

## 8. Pipeline 不自动继续

### 症状
Hermes 停在某个 Gate，输出 "next command for user to copy" 而不是自动继续。

### 根因
正常 auto_run 模式下，pipeline 应该自动继续（除非遇到阻塞条件）。

### 何时停止是正确的
- commit/push/PR 需要用户审批（Gate 9 / 9.5）
- Codex 返回 FAIL/UNKNOWN
- ClaudeCode 2 次失败
- 必需的 runtime/tool 不可用
- 用户明确要求 plan_only / dry_run / audit_only

### 解决
如果在不该停的地方停了：
1. 检查 mode 是否正确（应为 auto_run）
2. 检查是否有工具不可用
3. 检查是否误判了阻塞条件

---

## 9. 分类不准（S 应该是 M，M 应该是 L）

### 症状
S 级任务执行时发现涉及 API/store/routing/auth/generated files → 应该是 M 或 L。

### 规则
- **不确定时升级**（S → M 或 M → L）
- 如果 S 级 WO 执行时意外触及 API、store、routing、generated files、auth/security、多文件 → 升级

### 预防
Gate 0 时仔细检查：
- 涉及几个文件？
- 是否涉及 API/store/routing/auth？
- 是否涉及 generated files？
- 是否涉及 user data mutation？

---

## 10. 协议文件缺失导致 Publish Lane 失败

### 症状
GitHub Publish Lane 的 Gate E 发现缺少 README.md / CLAUDE.md / AGENTS.md / .github/workflows/。

### 处理
1. 缺少协议文件不一定是 FAIL
2. Hermes 提议从 templates 创建
3. 创建需要用户批准
4. 用户可以有意跳过（记录 "intentionally skipped"）

### 模板位置
- `templates/project-claude-template.md` → CLAUDE.md
- `templates/project-agents-template.md` → AGENTS.md
- `templates/github-publish-checklist.md` → checklist

---

## 快速排查表

| 症状 | 可能原因 | 第一步 |
|------|---------|--------|
| Forbidden file 被改 | ClaudeCode 违反 | 检查 `git diff --name-status` |
| delegate_task 超时 | prompt 太长 | 检查文件是否已创建 |
| TDD 证据 RED=0 | 跳过了 RED 阶段 | 检查 TDD Evidence 格式 |
| tsc 报 jest-dom 错误 | matcher 类型未声明 | grep 现有测试是否用 jest-dom |
| package.json 被改 | ESM 需要 | 用 CommonJS 替代 |
| Codex FAIL | 计划/实现有问题 | 查看 blocking issues |
| generated file 被手改 | 没用官方命令 | 查找官方生成命令 |
| Pipeline 不继续 | 模式或工具问题 | 检查 auto_run 模式 |
| 分类偏低 | Gate 0 未仔细检查 | 升级分类 |
|| Publish Lane 缺文件 | 协议文件缺失 | 从 templates 创建 |

---

## policy-check 报告 FAIL

如果 `bash scripts/policy-check.sh --run-state <file>` 报告 FAIL：

1. 查看具体哪个 check 失败
2. 如果是 forbidden-file-violation：检查 modified_files 是否包含 forbidden_files 中的文件
3. 如果是 acceptance-codex-consistency：检查 L 级任务是否有 Codex diff PASS
4. 如果是 commit-without-tests：检查 verification.tests_pass 是否为 true

## smoke test 失败

如果 smoke script 失败：
1. 运行 `bash scripts/smoke/smoke-<name>.sh` 查看具体输出
2. 检查 policy-check.sh 是否正常工作
3. 检查 examples/ 下的 fixture 文件是否完整
