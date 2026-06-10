# 工作流全览：9-Gate Pipeline

本文档详细说明 hermes-dev-pipeline-kit 的完整 9-Gate 开发流程。

---

## 流程总览

```
Gate 0 ──► Gate 1 ──► Gate 2 ──► Gate 3 ──► Gate 3.5 ──► Gate 4-6 ──► Gate 7 ──► Gate 8 ──► Gate 9 ──► Gate 9.5
 Intake     Context    Plan      WO Split   Codex       Execute +     Codex      Report    Commit     GitHub
 +Classify  Discovery            Codex      Plan Rev     Verify        Diff Rev             Approval   Publish
```

不同 S/M/L 级别走不同路径：

| 级别 | 走过的 Gate | Codex Plan Review | Codex Diff Review |
|------|------------|-------------------|-------------------|
| S | 0 → 1 → 4 → 6 → 8 | 可选 | 不需要 |
| M | 0 → 1 → 2 → 3 → 4-6 → 8 → 9 | 高风险时自动 | 高风险时自动 |
| L | 0 → 1 → 2 → 3 → 3.5 → 4-6 → 7 → 8 → 9 | **必需** | **必需** |
| Recovery | 0 → 1 → 1.5 → 2 → 3 → 3.5 → 4-6 → 7 → 8 → 9 | **必需** | **必需** |
| Publish | 0 → A → B → C → D → E → F → 9.5 | 视级别 | 视级别 |

---

## v0.3 Executable Evidence Harness

v0.3 changes the state ownership model:

```text
Hermes / ClaudeCode submit raw evidence
scripts/record-command.sh records command facts
scripts/generate-run-state.sh derives generated/run-state.json
scripts/policy-check.sh validates generated run-state
scripts/final-report.sh generates the owner report
```

### Evidence Ownership Rule

- Agent may submit evidence.
- Harness owns state generation.
- Agent must not hand-write final M/L run-state.
- Generated run-state must include provenance.

### Run Directory

```text
.hermes-runs/<run-id>/
  task.md
  run-manifest.json
  classification.json
  work-orders/
    WO-1.json
  raw/
    claudecode-result.json
    command-log.jsonl
    files-touched.txt
    stdout/
    stderr/
  generated/
    run-state.json
    final-report.md
```

### Policy Fixture vs Runtime Evidence

Hand-written JSON under `examples/policy/` is policy fixture validation. It is not runtime behavior evidence.

True runtime behavior validation requires:

- `raw/command-log.jsonl` emitted by `scripts/record-command.sh`;
- `raw/claudecode-result.json` following `schema/claudecode-result.schema.json`;
- `generated/run-state.json` emitted by `scripts/generate-run-state.sh`;
- provenance source files linking generated state back to raw evidence.

---

## Gate 0: Intake + Classification

**Hermes 的入口门禁。**

### 中文阶段播报

Hermes 与用户交互时必须优先使用中文阶段名。内部英文 phase 只能作为括号内 trace。

示例：

```text
当前阶段：需求收集与头脑风暴（Simple Prompt Intake）
正在使用：dev-pipeline-orchestrator / Simple Prompt Intake / writing-plans
目的：把你的简短想法转成可执行的需求、范围、非目标和验收标准。
```

不得只显示：

```text
Phase: Simple Prompt Intake
Phase: planning
Phase: work_order_execution
```

### Active Skill Disclosure

At task start, Hermes must show an active workflow banner for `dev-pipeline-orchestrator`.

The banner identifies:
- mode: `dry_run`, `plan_only`, or `auto_run`;
- current phase;
- planned Hermes/gstack skills;
- required ClaudeCode Matt skill;
- Codex usage: disabled, optional, or required;
- planned `policy-check.sh`, `doctor.sh`, and `ci-local.sh` usage;
- whether user clarification is needed.

If the user prompt is short, vague, or product-like, Hermes visibly enters Simple Prompt Intake and reports the normalized brief, assumptions, non-blocking assumptions, blocking questions if any, and the default decision if the user says "you decide".

Hermes must not later claim a skill was used unless the final report includes evidence. Planned-but-skipped skills require a skipped reason and acceptance impact.

If Hermes asks questions, it must say in Chinese why the questions are blocking, what default it would choose if the user does not answer, and which phase follows after the answer. Non-blocking assumptions should be recorded, not turned into questions.

### Owner-Facing Stage Update

每次进入新的主要 Gate 时，Hermes 必须给用户一个简短中文阶段更新：

```text
阶段更新：已完成 <上一阶段>，现在进入 <当前阶段>。
负责人：Hermes / ClaudeCode / Codex / 用户 / 外部工具。
为什么进入：<触发条件或证据>。
下一步：<要执行或等待的动作>。
```

阶段更新是沟通协议，不改变 9-Gate 流程本身。

### Chinese Report Scale Policy

Hermes 在 Gate 0 分类后同时确定最终报告尺度：

| 分类 | report_scale | 第一屏策略 |
|---|---|---|
| S | compact | 保留五个结构化栏目，但每栏只写必要信息，避免小修官僚化 |
| M | standard | 给 Owner Summary、主要阶段更新、Skill Trace 和验证摘要 |
| L / recovery / publish | full | 给完整报告，包括责任归因、审批、Codex、policy/doctor/ci-local、backlog |

失败 / 阻塞会强制要求责任归因。commit / push / PR / publish / 安装依赖 / 破坏性动作 / 修改全局配置会强制要求 `待你审批`。

S-level compact report 仍必须包含 `负责人摘要`、`阶段更新`、`技能使用证据`、`责任归因`、`待你审批`。它可以短，但不能退化成打勾列表。

### 输入
用户的自然语言请求，可能是完整描述，也可能是简短的一句话。

### 处理
1. 识别用户意图（small_fix / feature_development / idea_to_product / recovery / github_publish / workflow_polish / audit_only）
2. 将简短提示词展开为标准化任务描述
3. 分类为 S / M / L
4. 识别项目路径
5. 确定需要哪些后续 Gate
6. 判断是否需要用户补充信息

### 输出
```
- user goal: 用户目标
- inferred intent: 识别的意图类型
- project path: 项目路径
- scale: S / M / L
- classification reason: 分类理由
- expected files/modules: 预期涉及的文件/模块
- risks: 风险项
- required gates: 需要经过的 Gate
- user clarification needed: yes/no
```

### 关键规则
- **分类不确定时，升级**（S → M 或 M → L）
- Gate 0 未完成前，不得调用 ClaudeCode
- 简短提示词必须展开，不能直接转发

---

## Gate 1: Context Discovery

**只读探索项目现状。**

### 必须收集的信息
```bash
git status --short --branch    # 当前分支、工作树状态
git branch --show-current      # 当前分支名
git log --oneline -5           # 最近 5 个 commit
```

以及：
- package.json / scripts（test、build、lint、typecheck）
- README.md / CLAUDE.md / AGENTS.md（协议文件）
- 现有测试
- 相关源码文件
- 现有 skill 指令（如需要）

### 关键规则
- **不得将之前的记忆或 agent 自述当作证据**——必须读取实际文件
- 只读操作，不修改任何文件

---

## Gate 1.5: Baseline Verification（仅 Recovery）

**Recovery 任务独有。区分 baseline 错误 vs 本次引入的错误。**

### 必须运行的命令
```bash
npx tsc --noEmit          # TypeScript 类型检查
npm run build             # 构建
npm test                  # 测试
npm run lint              # Lint
```

如果某个命令不存在，记录 `MISSING SCRIPT`。

### 关键规则
- 必须区分 **baseline existing errors**（origin/main 已有的错误）和 **feature-introduced errors**（本次引入的错误）
- 不能只 grep 特定功能名——必须全量检查并计数

---

## Gate 2: Plan

**M/L 级任务必须产出计划。**

### S 级
可跳过，直接进 Gate 4。

### M 级
产出简单计划：scope、non-goals、预期改动、风险、测试策略。

### L 级
必须使用：
- `writing-plans` skill 制定计划
- `gstack plan-eng-review` 审查计划

### Recovery 任务（Gate 2: Code-State Audit）
对每个受影响的文件进行多层审计：

| 层 | 检查项 |
|---|--------|
| API 层 | provider 复用、SSE/chunk 处理、错误处理、API key 安全、测试 seam |
| Store 层 | state 流正确性、mutation 安全、stale reference、malformed data、耦合 |
| UI 层 | 全状态渲染（loading/streaming/error/empty/completed）、adopt/undo 一致性、关闭清理、i18n、可测试 selector |
| 集成 | 入口正确性、i18n key 完整性、generated file 状态 |
| 测试 | API smoke、store unit、UI smoke、E2E、mock 机制 |

---

## Gate 3: Work Order Split

**将计划拆分为 ClaudeCode Work Orders。**

每个 WO 必须包含：
- objective（目标）
- scope（范围）
- non-goals（不做）
- allowed files（允许修改的文件）
- forbidden files（禁止修改的文件 + "STOP and report" 条款）
- Required Matt skill（tdd / diagnose / prototype / to-issues / grill-me）
- validation commands（验证命令）
- timeout checkpoint format（超时检查点格式）

Hermes must also disclose the work order in Chinese before delegation:

```text
当前阶段：ClaudeCode 工单执行
ClaudeCode 只负责执行，不负责重新定义需求。
ClaudeCode 必须使用 Matt skill：tdd / diagnose / prototype
为什么使用：...
缺少对应 skill evidence 时，Hermes 不允许完整验收。
```

### 约束
- 每个 WO 触摸的核心文件少于 3 个（除非明确论证）
- 必须是垂直切片（vertical slice）
- 必须可独立验证

### Recovery WO 模式
Recovery 任务产生特定的 WO 模式：
- **WO-1（总是第一个）**：Generated file / routeTree / config recovery — 使用 `diagnose`，只读，找到官方重新生成命令
- **WO-2 到 WO-N**：按层加固 + 测试，每层用 `tdd` 或 `prototype`
- **WO-last**：E2E with mocked external dependencies — 使用 `diagnose`

---

## Gate 3.5: Codex Plan Review

**L 级任务的计划审查门禁。**

### 触发条件
- L 级：**自动触发，必需通过**
- 高风险 M 级（API + state mutation、generated files、auth/security、external service、prior failed attempt）：**自动触发**
- Recovery：**必需**

### 审查内容
Hermes 将计划、WO 列表、风险项发送给 Codex，Codex 返回：

| 结果 | 含义 | 后续动作 |
|------|------|----------|
| PASS | 计划通过 | 继续 Gate 4 |
| PASS_WITH_REQUIRED_CHANGES | 有条件通过 | 按 Codex 要求修改 WO 后继续 |
| FAIL | 计划不通过 | 停止，报告阻塞问题 |
| UNKNOWN | 无法判断 | 停止，报告 |

### 关键规则
- Codex PASS 之前，`acceptance complete` 必须为 false
- Hermes 不得要求用户手动触发 Codex review（除非工具不可用）

---

## Gate 4: ClaudeCode Execution

**执行工人开始干活。**

### 调用方式（优先级）
1. **`delegate_task`**（首选）：上下文清晰、独立终端会话、无 heredoc 解析开销
2. **`claude -p --bare`**（仅限 S 级单文件）：heredoc prompt 消耗额外 turns

### 工作单内容
```
objective: 要做什么
scope: 范围
non-goals: 不做
reference files: 参考文件
allowed files: 允许修改
forbidden files: 禁止修改（含 STOP and report 条款）
Required Matt skill: tdd / diagnose / prototype / ...
validation commands: 验证命令
result report format: 输出格式
timeout checkpoint requirement: 超时检查点
```

### 关键规则
- ClaudeCode **不得 commit**——commit 由 Hermes 在 Gate 9 处理
- ClaudeCode **不得修改 forbidden files**——如果技术上必须修改，必须 STOP 并报告
- ClaudeCode **不得手改 generated files**——除非 Codex 明确允许

---

## Gate 5: ClaudeCode Self-Check

**ClaudeCode 自检输出。**

ClaudeCode 必须输出：
- modified files（修改了哪些文件）
- diff summary（变更摘要）
- tests added/changed（测试增改）
- commands run with exit code（运行了哪些命令 + 退出码）
- risks（风险）
- Required Matt skill used: yes/no
- if not used, why（为什么没用）
- Matt skill evidence matching the required skill:
  - `tdd`: RED/GREEN evidence and validation exit code
  - `diagnose`: hypothesis, test, finding, fix recommendation or applied fix
  - `prototype`: variants considered, chosen variant, reason
  - `to-issues`: issue breakdown, acceptance criteria, priority
  - `grill-me`: challenge questions and decisions changed or confirmed

### 关键规则
- 如果 Required skill 没用且没有证据证明不可用，WO 直接 FAIL
- 如果缺少必需 Matt skill evidence，verification 必须是 PARTIAL 或 FAIL，不能是 PASS
- **不得信任 ClaudeCode 的自述**——Gate 6 会用 git diff 验证

---

## Gate 6: Hermes Verification

**Hermes 独立验证，只做验证和证据收集。**

### 必须运行的验证
```bash
git diff --name-status      # 检查改动了哪些文件
git diff --check             # 检查 diff 格式
git diff --stat              # 改动统计
```

以及：
- allowed files check（检查是否只改了允许的文件）
- targeted tests（目标测试）
- relevant typecheck（类型检查）
- generated file official generation check（generated file 是否用官方命令生成）
- entrypoint integration check（入口集成检查）
- baseline before/after（M/L 级的基线对比）

### Gate 6 只能输出
- `proceed to next work order` — 验证通过
- `return to ClaudeCode` — 验证不通过，退回重做
- `request Codex review` — 需要 Codex 介入

### 关键规则
- **不得在此标记 acceptance complete**
- **Forbidden file violation 是 ClaudeCode 最常见的失败模式**——永远运行 `git diff --name-status` 交叉检查
- 每个 WO 最多重试 2 次。2 次失败后停止，请求 Codex 诊断或用户决定

---

## Gate 7: Codex Diff Review

**L 级任务的 diff 审查门禁。**

### 触发条件
- L 级：**所有 WO 完成后自动触发，必需通过**
- 高风险 M 级：如果 Gate 3.5 运行了，或 WO 触及 API/generated files/auth/security/persistence/user data mutation

### 审查内容
- plan review（计划审查）
- diff review（差异审查）
- generated file review（生成文件审查）
- security/data review（安全/数据审查）
- test evidence review（测试证据审查）
- commit/PR readiness（提交/PR 就绪）

### 结果处理
| 结果 | 含义 | 后续动作 |
|------|------|----------|
| PASS | diff 通过 | 继续 Gate 8 |
| PASS_WITH_REQUIRED_CHANGES | 有条件通过 | 创建修复 WO，返回 Gate 4 |
| FAIL | diff 不通过 | 停止，报告阻塞问题 |
| UNKNOWN | 无法判断 | 停止，报告 |

### 关键规则
- Codex Diff Review 不是 PASS 时，`acceptance complete: true` 是 **被禁止的**

---

## Gate 8: dev-pipeline-report

**生成最终证据报告。**

调用 `software-development/dev-pipeline-report` skill，产出完整报告，包括：

- report_scale（compact / standard / full）
- 负责人摘要（绿 / 黄 / 红、当前阶段、下一步、阻塞项）
- 阶段更新（关键 Gate 切换和证据）
- 责任归因（full 或失败 / 阻塞时必需）
- 待你审批（commit / push / PR / deploy / 安装依赖 / 全局配置等需要审批时必需）
- Executive Status（执行状态总览）
- Role Performance（各角色执行情况）
- Task Classification（任务分类）
- Intake Quality（意图识别质量）
- Plan Evidence（计划证据）
- Work Orders（工作单状态）
- Verification Evidence（验证证据）
- Diff Summary（差异摘要）
- Codex Review（Codex 审查结果）
- Commit / PR（提交/PR 状态）
- GitHub / Publish Readiness（发布就绪，仅 publish 请求时）
- Final Decision: ACCEPTED / NOT ACCEPTED / PARTIAL / BLOCKED
- Follow-up Backlog（后续 backlog）

### 关键规则
- **没有报告 = pipeline 没有完成**
- 只有 Codex PASS 才能设置 `acceptance complete: true`
- 报告是唯一能证明 pipeline 跑过的 artifact
- 如果 `acceptance complete: true`，报告必须有负责人摘要
- 如果 `report_scale=compact` 且验收完成，报告仍必须有阶段更新、技能使用证据、责任归因和待审批结构
- 如果失败 / 阻塞 / full report，报告必须有责任归因
- 如果等待用户审批，报告必须集中列出待审批事项

---

## Gate 9: Commit / PR Approval

**提交审批门禁。**

### 前置条件
- Codex Diff Review 必须 PASS（L 级）
- dev-pipeline-report 必须已生成
- staged files 必须是显式列出的
- 不得使用 `git add -A`

### 行为
- **auto_run 模式下**：在此暂停，询问用户是否批准 commit
- 用户明确授权自动 commit 时：继续执行
- **push / PR 不在默认 auto_run 内**——除非用户明确要求

---

## Gate 9.5: GitHub Publish Approval

**发布审批门禁，仅在明确请求 publish 时进入。**

### 触发条件
用户说了以下任何一种：
- 上传 GitHub / 创建仓库 / 推送 / 开 PR / 发布 / 部署 / package upload

### 前置检查
- clean working tree 或显式 reviewed staged set
- branch 已知
- remote 存在或仓库创建已批准
- `gh` auth / GitHub skill / approved plugin 路径可用
- tests/build 通过，或 baseline debt 已分类且不阻塞
- README.md / CLAUDE.md / AGENTS.md / .github/workflows/ 存在或有证据表明有意跳过
- 无 secrets staged
- 无 forbidden files staged
- 只有显式 allowlisted files staged

### 硬性禁止
- 🚫 push secrets
- 🚫 force push
- 🚫 未明确批准就创建公开仓库
- 🚫 `git add -A`
- 🚫 push dirty working tree
- 🚫 无 rollback instructions 就 publish

---

## S/M/L 分类标准

### S 级（Small Fix）

以下所有条件必须满足：
- 单文件
- 无 API
- 无 store/state
- 无 routing
- 无 auth/security
- 无 generated file
- 无 user data mutation
- 约 100 行以内改动

**快速路径**：1 个 WO → ClaudeCode → Hermes 验证 → 报告。

### M 级（Medium / Feature）

- 2-5 文件
- 一个 feature slice
- API 或 store 有 limited blast radius
- 无 auth/deploy/generated file
- targeted tests 可验证行为

**标准流程**：plan → WO split → ClaudeCode → Hermes 验证 → 可选 Codex review。

### L 级（Large / Complex）

以下任一条件即为 L：
- 6+ 文件
- AI API
- API + store + UI
- routing
- i18n
- auth/security
- generated files
- CI/CD
- deployment
- data persistence
- project config
- multi-agent workflow
- unclear product behavior

---

## Runtime Evidence Consistency (v3)

### TDD RED/GREEN Evidence
- M/L tasks with required Matt skill=tdd must have RED phase evidence
- If RED is missing, must provide red_not_applicable_reason
- evidence_present=true forbidden without RED evidence

### Acceptance-Evidence Consistency
- blocking=true + evidence_present=false → acceptance.complete must be false
- status_color must be yellow or red when evidence is blocking

### Codex Deferred Consistency
- codex_deferred.deferred=true + required=true:
  - Do NOT require codex.diff_review_verdict
  - Do NOT write Codex PASS
  - status_color must NOT be green

### Self-Improvement Side Effect Guard
- Runtime tasks must not create skills, modify memory, or write global config
- Unless user explicitly approves

---

## Runtime Enforcement (v2)

The pipeline enforces 7 new policy checks:

### 1. Scale Classification Guard
- M/L tasks cannot be downgraded to S
- Multi-module, persistence, or system-level tasks must be M or L

### 2. M/L Delegation Requirement
- M/L tasks MUST delegate to ClaudeCode
- Self-execution requires explicit waiver
- Without delegation+waiver, acceptance FAILS

### 3. Matt Skill Evidence Gate
- Required Matt skill (tdd/diagnose/prototype) must have evidence
- Missing evidence blocks acceptance.complete=true

### 4. Full Report Sections Gate
- L/recovery/publish tasks require ALL 9 critical report sections
- Missing any section blocks green status

### 5. Verification Exit Code Gate
- M/L tests_pass=true requires command + exit code evidence
- Missing exit code blocks acceptance

### 6. Vague M/L Intake Gate
- Vague M/L tasks must complete intake (normalized brief, assumptions, non-goals, acceptance criteria)
- Missing intake blocks execution

### 7. Codex Unavailable Handling
- Codex can be deferred if quota unavailable
- Must record deferred reason
- Cannot fabricate Codex PASS
- previous failed attempt / recovery task

**完整流程**：plan → Codex plan review → ClaudeCode → Hermes 验证 → Codex diff review → report → commit approval。

---

## 何时 Codex 必须介入

| 场景 | Codex |
|------|-------|
| S 级 | 可选 |
| M 级高风险 | 自动 |
| L 级 | **必需** |
| Recovery | **必需** |
| 反复失败 | **必需** |

用户可通过以下方式禁用 Codex：
- 不用 Codex
- 不要引入 Codex
- 只用 Hermes 和 ClaudeCode
- no Codex

---

## 执行模式

| 模式 | 行为 |
|------|------|
| `dry_run` | 分类、计划、拆 WO、生成报告——不执行 ClaudeCode、不调用 Codex |
| `plan_only` | 分类、发现上下文、生成 WO、运行 Codex plan review——在 Codex 裁定后停止 |
| `auto_run`（默认） | 完整流程——分类、计划、拆 WO、Codex plan review（需时）、ClaudeCode 执行、Hermes 验证、Codex diff review（需时）、report、仅在阻塞条件时停止 |

默认 `auto_run`，除非用户明确说 dry-run / plan-only / audit-only / 只读 / 只审查。

---

## v0.2 Harness Hardening

v0.2 增加了以下可执行检查：

- `run-state schema`: pipeline 执行状态的 JSON schema 定义
- `policy-check.sh`: 基于 run-state 的安全策略检查
- `smoke scripts`: 4 个 harness behavior fixture checks
- `check-manifest.sh`: manifest.yaml 完整性检查
- `dev-pipeline-report schema`: 报告的 JSON 格式定义

这些是 **harness checks**，不是 runtime 引擎。它们能抓住一部分危险状态，但不能证明所有 runtime 行为都符合预期。

---

## v0.4 Hash-linked Runtime

v0.4 separates facts, events, state, and report:

- facts are raw files such as command logs, stdout/stderr, result contracts, and artifacts;
- events are append-only state transitions in `events.jsonl`;
- state is generated by the harness in `state.json` and `generated/run-state.json`;
- reports are generated from replayed state and policy results.

The state conclusion is generated by harness scripts, not by Hermes or ClaudeCode prose. Agents may submit raw evidence, but they must not hand-write final run-state. `append-event.sh` records transitions, `replay-run.sh` validates hash-linked history, `policy-check.sh` validates gates, and `final-report.sh` renders evidence.

Hash rule:

```text
event_hash = sha256(canonical_json(event_without_event_hash))
prev_event_hash = previous event_hash
```

Canonical JSON means UTF-8 JSON with sorted keys and compact separators. This is tamper-evident, not tamper-proof: a local writer can delete or rewrite a run, but replay detects mismatched hashes, broken links, invalid transitions, and changed artifacts within the submitted run.

---

## v0.5.1 / v0.5.2 Experimental Plugin Wrapper

v0.5.1 adds `plugins/hermes-evidence-runtime`, a conservative Hermes general
plugin wrapper around the existing v0.4 Bash harness scripts.

The wrapper exposes four machine-readable tools:

- `evidence_doctor`
- `evidence_active_run_status`
- `evidence_run_init`
- `evidence_drive_s_run`

v0.5.1 plugin wrapper is experimental.
It is source-validated and temp-HOME discovery validated.
It does not install into real `~/.hermes/plugins` by default.
It does not replace built-in ClaudeCode/Codex/OpenCode skills.
It does not replace the existing dev-pipeline-orchestrator skill.
It does not capture official ClaudeCode/Codex/OpenCode output yet.

v0.5.2 adds prototype hook handlers for:

- `pre_tool_call`
- `post_tool_call`
- `on_session_end`
- `on_session_finalize`
- `subagent_stop`

These hooks are source-only, experimental, and non-blocking. They log JSONL
records only when `HERMES_EVIDENCE_HOOK_LOG_DIR` is set, redact secret-like
keys and values, and must not enforce policy or stop user commands. They do not
implement a memory provider and do not capture official ClaudeCode/Codex/OpenCode
output. The old `dev-pipeline-orchestrator` skill remains the user-facing
development entrypoint.

The wrapper is validated with source-only smoke tests and temp-HOME discovery
under `/tmp`. It is not installed to real `~/.hermes/plugins` by the installer
path. v0.5.2 does not claim production runtime hook payload compatibility;
payload shape remains UNKNOWN until a future Hermes runtime probe.
