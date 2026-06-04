# Hermes Dev Pipeline Kit

一个可安装的 Hermes 开发流程 skill 包，将 Hermes 变成 **产品经理 + 架构师 + QA 调度器**，指挥 ClaudeCode 执行、通过 Codex 审查。

A portable Hermes workflow kit: Hermes acts as product manager, architect, workflow owner, and QA verifier — delegating implementation to ClaudeCode and gating through Codex.

This is NOT an official Hermes, Claude Code, Codex, OpenAI, Anthropic, or gstack project.

---

## 用 Hermes 安装 / Install with Hermes

把本仓库链接发给 Hermes：

```text
安装这个 Hermes 工作流：<repo-url>
```

Hermes 会自动：clone → 读取 BOOTSTRAP.md → 检查依赖 → 运行 install --dry-run → 运行 doctor → 询问你是否安装。

## 手动安装 / Manual Install

```bash
git clone <repo-url>
cd hermes-dev-pipeline-kit
bash scripts/install.sh --dry-run    # 预览
bash scripts/install.sh --yes        # 安装
bash scripts/doctor.sh               # 验证
```

---

## 免责声明 / Disclaimer

本项目不是 Hermes Agent、Claude Code、Codex 或 gstack 的官方项目。

This is NOT an official project of Hermes Agent, Claude Code, Codex, or gstack.

- Hermes, Claude Code, Codex, gstack, Matt Pocock skills, gh CLI 均为外部依赖，本项目不包含也不安装这些工具。
- 本项目仅提供 Hermes skill 文件、协议模板和安装脚本。
- 使用前请确保已安装 Hermes Agent 和 Claude Code CLI。
- 本项目不收集任何数据，不发送任何网络请求。

---

## 目录

- [免责声明 / Disclaimer](#免责声明--disclaimer)
- [这是什么](#这是什么)
- [v0.1 vs v0.2](#v01-vs-v02)
- [角色分工](#角色分工)
- [前置条件](#前置条件)
- [安装前须知](#安装前须知)
- [安装](#安装)
- [验证](#验证)
- [如何触发](#如何触发)
- [S/M/L 工作流概览](#sml-工作流概览)
- [Skill Trace and Evidence](#skill-trace-and-evidence)
- [中文阶段播报与技能使用证据](#中文阶段播报与技能使用证据)
- [负责人摘要、责任归因与审批事项](#负责人摘要责任归因与审批事项)
- [安全规则](#安全规则)
- [GitHub 发布通道](#github-发布通道)
- [简短提示词协议](#简短提示词协议)
- [卸载](#卸载)
- [License](#license)

---

## 这是什么

hermes-dev-pipeline-kit 是一套 Hermes skills，安装后让 Hermes 具备完整的软件开发调度能力：

- **产品经理**：解读用户意图、定义 scope、拆分任务
- **架构师**：设计实现方案、选择技术路径
- **QA 调度器**：验证 ClaudeCode 输出、收集证据、决定通过/驳回
- **ClaudeCode**：执行具体编码
- **Codex**：独立审查门禁（plan review + diff review）

整个流程有 9+ 个 Gate，每个 Gate 有明确的输入/输出/通过标准。

## v0.1 vs v0.2

| 版本 | 状态 | 说明 |
|------|------|------|
| v0.1 | ✅ | 自然语言 harness spec + installer + templates |
| v0.2 | ✅ | + run-state schema + policy-check + smoke fixtures + JSON report contract |

本项目是 **harness kit**，不是完整 runtime。它提供：
- 可安装的 Hermes skill 文件和模板
- 可执行的 policy 检查脚本
- 可运行的 harness behavior smoke tests
- JSON schema 和 sample

它**不提供**：
- 完整的 Hermes runtime 实现
- 自动化的 pipeline 执行引擎
- 保证所有 runtime 行为符合 policy

仍依赖 Hermes / ClaudeCode / Codex 遵守协议。

---

## Skill Trace and Evidence

Hermes must announce the active workflow at task start when using `dev-pipeline-orchestrator`, including mode, current phase, planned Hermes/gstack skills, required ClaudeCode Matt skill, Codex gate usage, and planned policy/doctor checks.

Final reports include a `Skill Trace` section that discloses:

- Hermes entry skill and phase;
- planned, used, and skipped Hermes/gstack skills;
- ClaudeCode Matt skills required and reported;
- Codex plan/diff review gates used or skipped;
- `policy-check.sh`, `doctor.sh`, and `ci-local.sh` command evidence;
- missing evidence and acceptance impact.

ClaudeCode must provide Matt skill evidence, not just claim a skill was used. For example, `tdd` needs RED/GREEN evidence and validation exit codes; `diagnose` needs hypothesis, test, finding, and fix recommendation or applied fix.

`policy-check.sh` can validate missing Skill Trace or missing Matt skill evidence in run-state fixtures. If acceptance is complete while required Matt skill evidence is missing, policy-check fails.

This kit enforces disclosure and evidence reporting. It does not guarantee hidden runtime invocation unless Hermes or ClaudeCode expose machine-readable runtime traces.

---

## 中文阶段播报与技能使用证据

Hermes 使用 `dev-pipeline-orchestrator` 时，必须优先用中文说明当前阶段和正在使用的能力。内部英文 phase 可以放在括号里作为机器 trace，但不能只显示 `Phase: planning` 或 `Phase: work_order_execution`。

用户可见阶段包括：

- 需求收集与头脑风暴
- 简短需求标准化
- 需求澄清与关键问题确认
- 方案设计与计划编写
- 工单拆分
- ClaudeCode 工单执行
- Hermes 验证
- Codex 计划审查 / Codex 代码变更审查
- 证据报告输出
- Commit / GitHub 发布审批

需求澄清时，Hermes 必须说明正在使用哪个 skill / 子流程、为什么必须问、如果用户不回答默认怎么判断，以及问完后会进入哪个阶段。

计划阶段要说明是否使用 `writing-plans` 和 `gstack plan-eng-review`。工单阶段要说明 ClaudeCode 必须使用哪个 Matt skill，例如 `tdd`、`diagnose` 或 `prototype`，以及缺少对应 evidence 会如何影响验收。

最终报告必须输出中文 `技能使用证据` 表格。缺少 required Matt skill evidence、gstack evidence 或 Codex gate evidence 时，不能标记完整验收。

本 kit 不能证明隐藏 runtime 真实调用，但能要求 agent 披露 skill usage 并提供 evidence。

---

## 负责人摘要、责任归因与审批事项

Hermes 使用 `dev-pipeline-orchestrator` 时，最终报告顶部必须给用户一个中文负责人摘要，而不是只输出底层日志。摘要需要说明：

- 当前状态：绿 / 黄 / 红；
- 当前阶段和下一步；
- 已完成的关键产出；
- 阻塞项和需要用户审批的事项；
- 本次是否可以 commit / push / publish。

阶段切换时，Hermes 必须输出中文阶段更新，说明“刚完成什么、现在进入什么、为什么进入这个阶段、下一步由谁负责”。这用于让用户在 auto_run 过程中看到流程进度，而不是等最终报告才知道发生了什么。

最终报告还必须包含 `责任归因` 和 `待你审批`：

- `责任归因` 区分用户、Hermes、ClaudeCode、Codex、外部工具或环境的责任边界；
- 失败或阻塞时必须说明 owner、证据、影响和下一步；
- `待你审批` 集中列出 commit、push、PR、部署、覆盖文件、修改敏感配置等需要用户确认的事项；
- 没有审批事项时也要明确写 `无`。

`policy-check.sh` 会检查 acceptance complete 状态下是否存在 owner summary、responsibility trace，以及需要审批时是否存在 approval inbox。本 kit 只能要求 Hermes 输出这些证据；实际执行质量仍依赖 Hermes / ClaudeCode / Codex runtime 遵守协议。

---

## 角色分工

```
┌─────────────────────────────────────────────────┐
│                  用户 (User)                      │
│   "修一下 toast 不消失的问题" / "加个功能"           │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│              Hermes (调度器)                       │
│  产品经理 ── 架构师 ── QA 验证器                     │
│  · 意图识别    · 任务分类    · 制定计划               │
│  · 拆分 WO     · 验证证据    · 决定通过/驳回          │
└────────┬────────────────────────────┬────────────┘
         │                            │
         ▼                            ▼
┌────────────────────┐    ┌──────────────────────┐
│   ClaudeCode       │    │   Codex (审查门禁)     │
│   执行工人          │    │   · Plan Review       │
│   · 实现 WO        │    │   · Diff Review       │
│   · 运行测试        │◄───│   · PASS / FAIL       │
│   · 返回证据        │    │   · 风险诊断           │
└────────────────────┘    └──────────────────────┘
```

**核心原则：**
- Hermes 不做实质编码，不自我验收
- ClaudeCode 只执行，不规划
- Codex 独立审查，PASS 后才能标记 acceptance complete

---

## 前置条件

| 条件 | 必需 | 说明 |
|------|------|------|
| Hermes Agent | ✅ | 已安装且可用 |
| Claude Code CLI | ✅ | `claude` 命令可用 |
| Codex CLI | 可选 | L 级任务、recovery、高风险 M 级需要 |
| Python 3 | ✅ | 用于 JSON 解析和 policy checks |
| Node.js | 可选 | 仅具体项目验证或示例需要时使用 |

---

## 安装前须知

- 运行 `bash scripts/install.sh --dry-run` 预览安装过程，确认无误后再安装。
- 安装脚本会修改 `~/.hermes/skills/software-development/` 目录。
- 安装脚本会检查 `~/.claude/CLAUDE.md` 是否包含 Hermes Delegation Protocol，如缺失会提示追加，但不会自动修改该文件。
- doctor.sh 检查本工具包的安装状态，不检查 Hermes / Claude Code / Codex 的整体运行健康。
- 本工具包不安装全局依赖，不写入 secret，不修改环境变量。

---

## 安装

```bash
# 预览（不修改任何文件）
bash scripts/install.sh --dry-run

# 正式安装
bash scripts/install.sh --yes
```

安装脚本会：
1. 将 skills 复制到 `~/.hermes/skills/software-development/`
2. 如已有同名 skill，先备份到 `.backup-dev-pipeline-<timestamp>/`
3. 检查 `~/.claude/CLAUDE.md` 是否包含 Hermes Delegation Protocol（缺失则提示，不自动修改）

---

## 验证

```bash
bash scripts/doctor.sh
```

doctor.sh 检查：
- skill 文件是否完整（orchestrator + report + templates）
- kit 引导文件是否就位（BOOTSTRAP.md / manifest.yaml / scripts）
- `~/.claude/CLAUDE.md` 是否包含 Hermes Delegation Protocol
- SKILL.md 内容关键词是否齐全（auto_run / Simple Prompt Intake 等）
- 可选依赖是否安装（gh CLI / gstack / Matt skills）
- 结果：PASS（全部通过）/ PARTIAL（核心通过，可选缺失）/ FAIL（核心缺失）

本地完整 hardening 检查：

```bash
bash scripts/ci-local.sh
```

`ci-local.sh` 会聚合 Bash 语法检查、manifest 检查、policy-check fixtures、smoke tests、JSON parse 和安全扫描。

当前版本不要求 GitHub Actions CI。不要新增 `.github/workflows/ci.yml`，除非用户明确要求。

这些检查是 **harness checks**，不是 Hermes 真实 E2E，也不是完整 runtime。

---

## 如何触发

安装后，对 Hermes 说以下任意一种即可触发：

| 你说 | 行为 |
|------|------|
| `用 dev skill 做 XXX` / `使用 dev-pipeline-orchestrator auto_run` | 显式触发开发流程 |
| `加个功能` | feature_development 意图 |
| `修一下` | small_fix 意图 |
| `重构 XXX` | 自动分类为 M/L |
| `把这个想法落地` | idea_to_product 意图 |
| `恢复之前那个没做好的功能` | recovery 意图（L 级） |
| `把项目整理好上传 GitHub` | GitHub publish 通道 |

Hermes 会自动识别意图、分类 S/M/L、选择对应流程。

---

## S/M/L 工作流概览

### S 级（Small Fix）

```
Gate 0: 意图识别 + 分类
  → Gate 1: 上下文发现
    → Gate 4: ClaudeCode 执行
      → Gate 6: Hermes 验证
        → Gate 8: 报告
```

- 单文件、无 API、无 store、~100 行以内
- Codex 可选
- 快速路径，一个 WO

### M 级（Feature / Medium）

```
Gate 0: 意图识别 + 分类
  → Gate 1: 上下文发现
    → Gate 2: 计划
      → Gate 3: WO 拆分
        → Gate 4-6: ClaudeCode 执行 + 验证循环
          → Gate 7: Codex Diff Review（高风险时必需）
            → Gate 8: 报告
              → Gate 9: Commit 审批
```

- 2-5 文件、一个 feature slice
- 高风险 M 级（API + state、generated files、auth）Codex 自动介入

### L 级（Large / Complex）

```
Gate 0: 意图识别 + 分类
  → Gate 1: 上下文发现
    → Gate 2: 计划（writing-plans + gstack plan-eng-review）
      → Gate 3: WO 拆分
        → Gate 3.5: Codex Plan Review（必需）
          → Gate 4-6: ClaudeCode 执行 + 验证循环
            → Gate 7: Codex Diff Review（必需）
              → Gate 8: 报告
                → Gate 9: Commit 审批
```

- 6+ 文件、AI API、auth/security、generated files、CI/CD、recovery 等
- Codex Plan Review 和 Diff Review 均为必需

---

## 安全规则

| 规则 | 说明 |
|------|------|
| 🚫 不自动 push | 任何 push 操作需要用户审批 |
| 🚫 不自动创建 PR | PR 创建需要用户审批 |
| 🚫 不自动创建公开仓库 | 公开仓库创建需要明确审批 |
| 🚫 不用 `git add -A` | 必须显式列出 staged 文件 |
| 🚫 不提交 secrets | secrets 永远不进 commit |
| ✅ Commit 需审批 | Gate 9 必须暂停等用户确认 |
| ✅ Generated files 不能手改 | 必须用官方生成命令 |
| ✅ Forbidden files 越权即 FAIL | ClaudeCode 改了禁止文件 → Gate 6 捕获 |
| ✅ Codex PASS 才能标记 acceptance | 没有 Codex PASS 就不能说"完成" |

详见 [docs/safety-rules.md](docs/safety-rules.md)。

---

## GitHub 发布通道

当用户说"上传 GitHub"、"创建仓库"、"推送到 GitHub"等，Hermes 进入 **Publish Lane**：

```
Gate A: 发布意图检测
  → Gate B: 仓库发现 (git status/remote/branch)
    → Gate C: GitHub 工具链发现 (gh CLI/auth/skills)
      → Gate D: 包/构建发现 (package manager/scripts)
        → Gate E: 协议文件检查 (README/CLAUDE/AGENTS/CI)
          → Gate F: 验证
            → Gate G: 发布审批暂停 ⛔
```

**Gate G 是硬停止门禁**——所有发现就绪后，pipeline 暂停，等待用户明确批准 push/create repo/PR。

正常开发流程在 Gate 9 停止，不会进入 Publish Lane，除非用户明确要求。

---

## 简短提示词协议

Hermes 不要求用户提供完整的任务描述。简短提示词会被自动展开：

**输入：** `修一下 toast 不消失的问题`

**Hermes 内部展开为：**
- user goal: 修复 toast 通知不自动消失
- inferred intent: small_fix
- project path: 当前项目
- risk classification: S 或 M
- verification commands: 需要确认的命令
- Codex: S 级可选
- approval gates: commit 需审批

Hermes 会在报告的 "Intake Quality" 部分记录所有推断假设。

详见 [docs/workflow-overview.md](docs/workflow-overview.md)。

---

## 卸载

```bash
# 先预览会删除什么
bash scripts/uninstall.sh --dry-run

# 确认后执行（会提示确认，--yes 跳过提示）
bash scripts/uninstall.sh --yes
```

---

## License

MIT

---

## 相关文档

| 文档 | 内容 |
|------|------|
| [docs/workflow-overview.md](docs/workflow-overview.md) | 完整 9-Gate 流程详解 |
| [docs/usage-examples.md](docs/usage-examples.md) | 5 个使用示例 |
| [docs/safety-rules.md](docs/safety-rules.md) | 安全规则完整说明 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 常见问题排查 |
| [examples/simple-prompt-smoke.md](examples/simple-prompt-smoke.md) | 简短提示词全流程 trace |
| [examples/github-publish-smoke.md](examples/github-publish-smoke.md) | GitHub 发布通道 smoke test |
| [examples/recovery-task-smoke.md](examples/recovery-task-smoke.md) | Recovery 任务全流程 trace |
