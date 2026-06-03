# 使用示例

本文档提供 5 个典型的使用场景，展示 pipeline 在不同意图下的完整行为。

---

## 示例 1：Small Bug Fix — S 级

### 用户输入
```
修一下登录 bug
```

### Pipeline 行为

#### Gate 0: Intake + Classification
```
- user goal: 修复登录相关的 bug
- inferred intent: small_fix
- scale: S
- reason: 单文件修复，无 API/store/routing
- risks: 低
- required gates: 0 → 1 → 4 → 6 → 8
```

#### Gate 1: Context Discovery
```
- 读取登录相关文件 (src/auth/login.ts)
- 检查现有测试 (src/auth/login.test.ts)
- 确认 package scripts (test, build, lint)
```

#### Gate 4: ClaudeCode Execution
```
- WO-1: 诊断并修复登录 bug
  - Allowed files: src/auth/login.ts
  - Forbidden files: package.json, tsconfig.json
  - Required skill: diagnose
  - Validation: npm test -- --testPathPattern=login
```

#### Gate 6: Hermes Verification
```bash
git diff --name-status    # 只有 src/auth/login.ts
git diff --check           # exit 0
npm test -- --testPathPattern=login   # PASS
```

#### Gate 8: Report
```
- execution complete: true
- verification complete: true
- acceptance complete: true (S 级 Codex 可选)
- Codex verdict: not required (S 级, minimal risk)
- Final Decision: ACCEPTED
```

---

## 示例 2：Feature — M 级

### 用户输入
```
加个导出功能
```

### Pipeline 行为

#### Gate 0: Intake + Classification
```
- user goal: 添加数据导出功能
- inferred intent: feature_development
- scale: M
- reason: 需要新组件 + API 接口 + store 变更，2-5 文件
- risks: 中等（涉及 API + store）
- required gates: 0 → 1 → 2 → 3 → 4-6 → 7 → 8 → 9
- Codex: 高风险 M 级，自动介入
```

#### Gate 1: Context Discovery
```
- 读取现有数据结构和 API
- 检查现有导出相关代码
- 确认 package scripts
```

#### Gate 2: Plan
```
- scope: 添加 CSV/JSON 导出，UI 按钮 + API 端点 + store action
- non-goals: 不做 PDF 导出、不做大数据量异步导出
- files: src/components/ExportButton.tsx, src/api/export.ts, src/stores/useExportStore.ts
- acceptance: 用户点击导出 → 下载文件 → 格式正确
```

#### Gate 3: WO Split
```
WO-1: API 端点 + 类型定义 (src/api/export.ts)
  - Required skill: tdd
  - Allowed: src/api/export.ts, src/api/export.test.ts
  - Forbidden: package.json

WO-2: Store action (src/stores/useExportStore.ts)
  - Required skill: tdd
  - Allowed: src/stores/useExportStore.ts, src/stores/useExportStore.test.ts
  - Forbidden: package.json

WO-3: UI 组件 (src/components/ExportButton.tsx)
  - Required skill: tdd
  - Allowed: src/components/ExportButton.tsx, src/components/ExportButton.test.tsx
  - Forbidden: package.json
```

#### Gate 4-6: Execute + Verify (per WO)
```
每个 WO:
  ClaudeCode 执行 → Hermes 验证 (git diff + tests)
  WO-1 PASS → WO-2 PASS → WO-3 PASS
```

#### Gate 7: Codex Diff Review (高风险 M 级自动触发)
```
- 审查 API 安全性
- 审查 store 状态流
- 审查测试覆盖
- verdict: PASS
```

#### Gate 8: Report
```
- execution complete: true
- verification complete: true
- acceptance complete: true (Codex PASS)
- Final Decision: ACCEPTED
```

#### Gate 9: Commit Approval
```
Pipeline 暂停，询问用户：
"3 个文件已修改，Codex PASS，是否批准 commit?"
等待用户确认。
```

---

## 示例 3：Vague Idea — idea_to_product

### 用户输入
```
把这个想法落地
```

### Pipeline 行为

#### Gate 0: Intake + Classification
```
- user goal: 将一个模糊想法转化为产品功能
- inferred intent: idea_to_product
- scale: 需要进一步判断（先产品化再分类）
- ambiguity: HIGH
```

#### Hermes 产品化阶段（Gate 0 特殊处理）
Hermes 不会直接交给 ClaudeCode。先进入产品经理模式：

```
1. product interpretation: 解读用户想做什么
2. user goal: 明确用户目标
3. likely users: 目标用户是谁
4. core workflow: 核心工作流
5. scope: 范围
6. non-goals: 不做
7. acceptance criteria: 验收标准
8. risk classification: 风险分类
9. proposed implementation slices: 建议实现切片
```

#### 判断：是否需要问用户？
```
如果产品方向清晰 → 记录假设，继续
如果产品方向有歧义（会产出完全不同的产品）→ 问用户（最多 3 个问题）
如果涉及 data/security/payment/deployment → 问用户
```

#### 后续 Gate
根据产品化结果的分类，走对应的 S/M/L 流程。

---

## 示例 4：Recovery — L 级

### 用户输入
```
恢复之前那个没做好的功能
```

### Pipeline 行为

#### Gate 0: Intake + Classification
```
- user goal: 恢复之前未完成/质量不达标的功能
- inferred intent: recovery
- scale: L (previous failed attempt → 自动 L)
- reason: recovery 任务自动升级为 L 级
- required gates: 0 → 1 → 1.5 → 2 → 3 → 3.5 → 4-6 → 7 → 8 → 9
- Codex: 必需
```

#### Gate 1: Context Discovery
```
- git log：查看相关 commit 历史
- git show：查看之前的实现
- git diff vs origin：对比差异
```

#### Gate 1.5: Baseline Verification（Recovery 专有）
```bash
npx tsc --noEmit         # exit: 0 (或记录 baseline errors)
npm run build            # exit: 0
npm test                 # exit: 0 (或记录 baseline failures)
npm run lint             # exit: 0 (或记录 baseline warnings)
```

**关键**：区分 baseline existing errors vs feature-introduced errors。

#### Gate 2: Code-State Audit（Recovery 专有）

对每个功能文件进行多层审计：
```
API layer:  provider 复用? SSE 处理? 错误处理? API key 安全? 测试 seam?
Store layer: state 流? mutation 安全? stale reference? malformed data?
UI layer:   全状态? adopt/undo? 关闭清理? i18n? 可测试 selector?
Integration: 入口正确? i18n key? generated file?
Tests:      API smoke? store unit? UI smoke? E2E? mock?
```

#### Gate 3: WO Split（Recovery 特有模式）
```
WO-1 (always first): Generated file / config recovery
  - Required skill: diagnose (只读)
  - 目标: 找到官方重新生成命令，恢复 generated files

WO-2: Store 层加固 + 测试
  - Required skill: tdd
  - TDD Evidence format (RED ≠ 0, GREEN = 0)

WO-3: UI 层加固 + 测试
  - Required skill: tdd
  - TDD Evidence format

WO-last: E2E with mocked dependencies
  - Required skill: diagnose
```

#### Gate 3.5: Codex Plan Review（Recovery 必需）
```
- 将 recovery 计划 + WO 列表 + 审计发现发送给 Codex
- verdict: PASS / PASS_WITH_REQUIRED_CHANGES / FAIL
```

#### Gate 7: Codex Diff Review（Recovery 必需）
```
- 审查所有 recovery WO 的 diff
- 审查 generated file 恢复是否正确
- 审查测试覆盖
- verdict: PASS / PASS_WITH_REQUIRED_CHANGES / FAIL
```

#### Gate 8: Report
```
- execution complete: true
- verification complete: true
- acceptance complete: true (Codex PASS)
- Final Decision: ACCEPTED
- Follow-up Backlog: 记录 baseline tech debt（不自动修复）
```

---

## 示例 5：GitHub Publish — Publish Lane

### 用户输入
```
把项目整理好上传 GitHub
```

### Pipeline 行为

#### Gate 0: Intake + Classification
```
- user goal: 整理项目并上传到 GitHub
- inferred intent: github_publish
- lane: GitHub Publish / Project Bootstrap Lane
- required gates: 0 → A → B → C → D → E → F → 9.5
```

#### Gate A: Publish Lane Detection
```
检测到发布意图，进入 Publish Lane。
```

#### Gate B: Repository Discovery
```bash
git status --short --branch    # 分支、工作树状态
git remote -v                  # 是否有 origin
git branch --show-current      # 当前分支
git log --oneline -5           # 最近 commit
```

#### Gate C: GitHub Toolchain Discovery
```bash
which gh || true               # gh CLI 是否可用
gh auth status || true         # gh 是否已认证
```
以及检查：
- Hermes GitHub skill 是否可用
- ClaudeCode GitHub plugin 是否可用
- gstack ship/review 是否可用

#### Gate D: Package/Build Discovery
```bash
ls
cat package.json 2>/dev/null || true
ls pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null || true
```
识别：package manager、scripts（test/build/lint/typecheck）、framework。

#### Gate E: Project Protocol File Check
检查是否缺少：
- README.md
- CLAUDE.md
- AGENTS.md
- .github/workflows/

如果缺少，提议从 templates 创建。**创建需要用户批准**。

#### Gate F: Verification
```bash
git diff --name-status    # 检查改动
git diff --check           # 检查格式
npm test                   # 运行测试
```

#### Gate 9.5: Publish Approval Stop ⛔
```
Pipeline 硬停止。

输出：
- 仓库发现状态
- 工具链状态
- 协议文件状态
- 验证结果
- "等待用户批准 push / create repo / PR"
```

**任何 push、repo 创建、PR 操作都不会自动执行。**

#### 用户批准后
```
1. 如果没有 remote → 提议 repo name/visibility → 等批准 → gh repo create
2. 如果有 remote → 等批准 → git push
3. 如果要 PR → 生成 PR title/body → 等批准 → gh pr create
```

---

## 对比总结

| 场景 | 级别 | Codex | 典型耗时 | 停止点 |
|------|------|-------|---------|--------|
| 修一下 bug | S | 可选 | < 5 min | Gate 8 |
| 加个功能 | M | 高风险自动 | 10-30 min | Gate 9 |
| 落地想法 | M/L | 视分类 | 15-60 min | Gate 9 |
| 恢复功能 | L | **必需** | 30-90 min | Gate 9 |
| 上传 GitHub | - | 视级别 | 10-20 min | Gate 9.5 |
