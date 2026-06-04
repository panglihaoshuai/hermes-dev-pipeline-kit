# 安全规则

本文档说明 hermes-dev-pipeline-kit 的所有安全约束和防护机制。

---

## 核心安全原则

```
Hermes 是调度器和验证器，不是执行者。
ClaudeCode 是执行工人，不是决策者。
Codex 是独立审查门禁，不是橡皮图章。
用户是最终审批人，不是旁观者。
```

---

## 1. 不自动 Push / PR / 创建仓库

| 操作 | 是否需要用户审批 |
|------|---------------|
| git commit | ✅ 需要（Gate 9） |
| git push | ✅ 需要（Gate 9 / 9.5） |
| 创建 GitHub 仓库 | ✅ 需要（Gate 9.5） |
| 创建 PR | ✅ 需要（Gate 9.5） |
| 创建公开仓库 | ✅✅ 双重需要 |
| 部署 / package upload | ✅ 需要 |

**唯一例外**：用户在同一任务中明确说"自动 commit"或"直接推"。即便如此，公开仓库仍需明确批准。

---

## 2. 不用 `git add -A`

**永远不允许。**

```bash
# ❌ 禁止
git add -A
git add .

# ✅ 必须
git add src/auth/login.ts src/auth/login.test.ts
```

每次 commit 前，必须：
1. 显式列出所有 staged files
2. 用户确认 staged 文件列表
3. 确认无 secrets、无 forbidden files

---

## 3. 不提交 Secrets

以下内容永远不得出现在 commit 中：
- API keys
- passwords
- tokens
- .env 文件内容
- private keys
- credentials

Gate 6 验证时会检查 staged files 中是否有 secrets 模式。

---

## 4. Generated Files 不能手改

### 规则
- generated files 必须用官方生成命令重新生成
- 不得直接编辑 generated files

### 处理流程
```
发现 generated file 被手改
  → 检查是否有官方生成命令
    → 有: 创建 WO 用官方命令重新生成
    → 没有: 请求 Codex 批准手动修复 + 证据说明
```

### 常见 generated files
- routeTree.gen.ts（TanStack Router）
- schema.generated.ts（GraphQL codegen）
- API 客户端（openapi-generator）
- lockfiles（package-lock.json / pnpm-lock.yaml）

### 阻塞条件
Generated files 被手改且没有 Codex 批准 → **blocking issue**。

在 v0.2 policy-check 中，只要 `modified_files` 包含 generated file 且没有官方 generation command evidence，检查必须 **FAIL**。这个规则适用于所有任务级别，包括 S 级。

---

## 5. Forbidden Files 越权即 FAIL

### 机制
每个 WO 包含：
- **allowed files**: 允许修改的文件
- **forbidden files**: 禁止修改的文件

ClaudeCode 必须遵守。如果技术上必须修改 forbidden file，必须：
1. **STOP**
2. **报告**为什么必须修改
3. **等待** Hermes 决定

### ClaudeCode 的已知行为
> ClaudeCode 会在认为"技术上必要"时修改 forbidden files。
> 例如：需要 ESM imports 时，ClaudeCode 会往 package.json 加 `"type": "module"`。

### Gate 6 防护
```bash
git diff --name-status    # 与 forbidden files 列表交叉比对
```

**不得信任 ClaudeCode 的自述。** ClaudeCode 不会主动报告 forbidden file violation。

### Forbidden file violation 的后果
- WO FAIL
- 退回 ClaudeCode 重做（最多 2 次）
- 2 次失败 → 停止，请求 Codex 诊断或用户决定

---

## 6. Completion Boundary Policy（完成边界策略）

### 核心区分
```
"请求的任务已完成" ≠ "整个项目完美"
```

### 规则
- Pipeline 在用户请求的目标完成并验证后停止
- 不自动扩展范围到无关的技术债清理
- 无关的 baseline issues 记录为 backlog，不自动修复

### 风险分类

| 类别 | 定义 | 处理 |
|------|------|------|
| BLOCKER | 阻塞当前任务 | 创建修复 WO 或停止 |
| TASK_RELATED | 影响当前任务质量但不完全阻塞 | 在 scope 内修复；否则 Codex 决定 |
| BASELINE_TECH_DEBT | 之前就存在、非本次引入、不影响验收标准 | 记录为 backlog，**不自动修复** |
| OPTIONAL_POLISH | UX/text/i18n/style 改进，不影响正确性 | 记录；仅用户要求时才做 |
| BACKLOG | 有用但不紧急的未来工作 | 列为 follow-up，不自动执行 |

### 不得自动触发修复的条件
```
post-commit 验证发现的无关 baseline issues
→ 记录
→ 不得变成新的 development task（除非用户明确要求）
```

---

## 7. Backlog vs Current Task

### 规则
- 当前任务的 tests fail → BLOCKER，必须修复
- 当前 diff 引入 TypeScript/test/build errors → BLOCKER，必须修复
- 之前的 baseline errors → BASELINE_TECH_DEBT，记录即可

### 报告格式
```
Follow-up Backlog:
| id | category            | description             | related? | blocker? | handling           |
|----|---------------------|-------------------------|----------|----------|--------------------|
| 1  | BASELINE_TECH_DEBT  | 122 unrelated tsc errors| no       | no       | record as backlog  |
| 2  | OPTIONAL_POLISH     | button label wording    | no       | no       | ask if user wants  |
```

---

## 8. Codex Review Requirements

### 什么时候 Codex 必须介入

| 场景 | Codex Plan Review | Codex Diff Review |
|------|-------------------|-------------------|
| S 级 | 可选 | 不需要 |
| M 级（低风险） | 可选 | 可选 |
| M 级（高风险） | **自动** | **自动** |
| L 级 | **必需** | **必需** |
| Recovery | **必需** | **必需** |
| 反复失败 | **必需** | **必需** |

### 高风险 M 级定义
- API + state mutation
- generated files
- auth/security
- external service integration
- prior failed attempt
- multi-agent workflow changes

### Codex 裁定与 acceptance 的关系
```
Codex PASS → acceptance complete 可以设为 true
Codex PASS_WITH_REQUIRED_CHANGES → 修复后可设为 true
Codex FAIL → acceptance complete 必须为 false
Codex UNKNOWN → acceptance complete 必须为 false
```

**没有 Codex PASS 的 acceptance complete 是被禁止的。**

---

## 9. Skill Trace and Evidence

Hermes must disclose the active `dev-pipeline-orchestrator` workflow at task start and report the current phase, planned sub-skills, required ClaudeCode Matt skill, Codex gates, and planned policy/doctor checks.

The user-facing disclosure must be in Chinese. English internal phase names may appear in parentheses, but the primary visible label must be Chinese.

Final reports must include Skill Trace evidence:

- gstack skills used require concrete evidence such as plan/risk/acceptance, hypothesis/evidence/conclusion, diff/issues/verdict, release readiness, or retro notes.
- gstack skills skipped require a skipped reason.
- ClaudeCode Matt skills require matching evidence, not a bare "used skill" claim.
- Codex gates required by policy must be used and return PASS or allowed PASS_WITH_REQUIRED_CHANGES.
- missing evidence must include acceptance impact: none, partial, or blocking.

If required Matt skill evidence is missing, verification must be PARTIAL or FAIL. If acceptance complete is true while required Matt skill evidence is missing, `policy-check.sh` must FAIL.

If acceptance is complete, `skill_trace.display_language` must exist. If `display_language` is `zh-CN`, `skill_trace.current_phase_label` and `user_visible_skill_banner` are required. If clarification questions were asked, `clarification_trace.why_questions_are_needed` is required.

This rule enforces disclosure and evidence. It does not claim to introspect hidden runtime invocation unless the runtime exposes trace data.

---

## 10. Timeout 不等于完成

### delegate_task 超时（600s）
当 delegate_task 超时：
1. 不要认为是失败
2. 检查预期文件是否已创建
3. 运行验证命令
4. 如果文件存在且测试通过 → 视为成功（附带 timeout 说明）
5. 如果文件不存在 → 用更精简的 prompt 重试

### 超时检查点
每次 ClaudeCode 执行都必须输出 timeout checkpoint 格式：
```
timeout checkpoint: [已完成/未完成] [已完成部分] [剩余部分]
```

---

## 11. TDD Evidence 不可伪造

### 严格 TDD 证据格式
```
RED:
- test file written: <path>
- command: <test command>
- exit code: <必须非零>
- expected failure: YES — <error type>

GREEN:
- implementation file written: <path>
- command: <test command>
- exit code: <必须为 0>
- expected pass: YES

REFACTOR:
- refactor performed: <yes/no>
```

### 规则
- RED exit code = 0 → TDD 未被遵循 → WO FAIL
- 不得先写实现再补测试
- M/L 级任务建议拆分为两个 WO：WO-A（测试，验证 FAIL）→ WO-B（实现，验证 PASS）

---

## 12. 不发明命令

### 规则
- test command: 从 package.json scripts 推断，不发明
- build command: 从 package.json scripts 推断，不发明
- package manager: 从 lockfile 推断，不发明

如果所需 scripts 不存在 → 创建 setup WO + 询问用户是否允许添加。

---

## 13. 不自我验收

### 规则
- Hermes 不得做实质编码然后自我验收
- Hermes 只做验证和证据收集
- 如果 Hermes 需要修复 → 交给 ClaudeCode 通过 WO
- 如果 Hermes 做了修复 → 不得在同一轮标记 acceptance complete

### 典型反模式
```
❌ Hermes 发现问题 → Hermes 自己改代码 → Hermes 标记 PASS
✅ Hermes 发现问题 → 创建修复 WO → ClaudeCode 修复 → Hermes 验证 → Codex 审查
```

---

## 安全检查清单（每个 pipeline run）

- [ ] Gate 0: 分类不确定时升级
- [ ] Gate 6: 运行 `git diff --name-status` 交叉检查 forbidden files
- [ ] Gate 6: 不信任 ClaudeCode 自述
- [ ] Gate 9: 显式列出 staged files
- [ ] Gate 9: 不用 `git add -A`
- [ ] Gate 9: 检查无 secrets
- [ ] Gate 9.5: 检查无 forbidden files staged
- [ ] Gate 9.5: 不自动 push / create repo / PR
- [ ] Gate 9.5: 公开仓库需要明确批准
- [ ] Report: Codex PASS 才设 acceptance complete
- [ ] Report: 记录所有 BASELINE_TECH_DEBT 为 backlog
- [ ] Report: 不将 post-commit findings 变成新任务
