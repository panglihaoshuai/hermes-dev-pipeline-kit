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
- [Architecture / Operating Model](#architecture--operating-model)
- [这是什么](#这是什么)
- [v0.1 vs v0.10.1](#v01-vs-v0101)
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

## Architecture / Operating Model

- [Operating Model](docs/operating-model.md)
- [Skill Routing Map](docs/skill-routing-map.md)
- [Dev Pipeline Gates](docs/gates.md)
- [Harness Evolution Lessons](docs/harness-evolution-lessons.md)
- [Plugin Runtime Roadmap](docs/plugin-runtime-roadmap.md)
- [Integration Contracts](docs/integration-contracts.md)

---

## 这是什么

hermes-dev-pipeline-kit 是一套 Hermes skills，安装后让 Hermes 具备完整的软件开发调度能力：

- **产品经理**：解读用户意图、定义 scope、拆分任务
- **架构师**：设计实现方案、选择技术路径
- **QA 调度器**：验证 ClaudeCode 输出、收集证据、决定通过/驳回
- **ClaudeCode**：执行具体编码
- **Codex**：独立审查门禁（plan review + diff review）

整个流程有 9+ 个 Gate，每个 Gate 有明确的输入/输出/通过标准。

## v0.1 vs v0.10.1

| 版本 | 状态 | 说明 |
|------|------|------|
| v0.1 | ✅ | 自然语言 harness spec + installer + templates |
| v0.2 | ✅ | + run-state schema + policy-check + smoke fixtures + JSON report contract |
| v0.3 | ✅ | + executable evidence harness: run directory, command log, generated run-state, generated final report |
| v0.4 | ✅ | + hash-linked event/state replay harness |
| v0.5.1 | experimental | + source-only Hermes plugin wrapper around existing Bash scripts |
| v0.5.2 | prototype | + non-blocking source-only hook probes behind `HERMES_EVIDENCE_HOOK_LOG_DIR` |
| v0.5.3 | prototype | + worker result contract adapter around simulated worker output |
| v0.5.4 | prototype | + worker output normalizer for caller-supplied/simulated ClaudeCode, Codex, OpenCode, and raw adapter output |
| v0.5.5 | prototype | + explicit worker dry-run wrapper; real invocation is optional and disabled by default |
| v0.6 | experimental | + plugin enabled in Hermes config and evidence tools callable through the active Hermes tool registry |
| v0.7 | experimental | + selected Hermes hook payloads captured in log-only mode; pre/post tool hooks verified through a real Hermes runtime smoke |
| v0.8 | experimental | + controlled-worker C-class dry-run using real Hermes evidence tool dispatch, real local command evidence, real pre/post hook evidence, generated run-state, policy result, final report, and pending approval inbox |
| v0.9 | spike | + optional integration backend adapters for Hermes Dynamic Workflows and AgentGuard; records raw orchestration/security evidence only |
| v0.10 | prototype | + run authorization, secondary live approval, and terminal verdict gates for selected Dev Pipeline mutation paths |
| v0.10.1 | prototype | + durable authorization, secondary approval, terminal verdict, control state, hashes, and events under each canonical run directory |

本项目是 **harness kit**，不是完整 runtime。它提供：
- 可安装的 Hermes skill 文件和模板
- 可执行的 policy 检查脚本
- 可运行的 harness behavior smoke tests
- JSON schema 和 sample

它**不提供**：
- 完整的 Hermes runtime 实现
- 自动化的 pipeline 执行引擎
- 保证所有 runtime 行为符合 policy

v0.3 的目标是减少自证：agent 提交 raw evidence，harness 生成 state，policy-check 检查 generated state。

最小执行式 harness：

```bash
bash scripts/run-init.sh --root /tmp/my-run --task-file task.md --scale M
bash scripts/record-command.sh --run-dir <run-dir> --phase RED -- <command>
bash scripts/generate-run-state.sh <run-dir>
bash scripts/policy-check.sh --run-state <run-dir>/generated/run-state.json
bash scripts/final-report.sh <run-dir>/generated/run-state.json
```

仍然不提供完整 Hermes runtime，不自动接管真实 Hermes / ClaudeCode 进程。

---

## v0.5.1 / v0.5.2 / v0.5.3 / v0.5.4 / v0.5.5 / v0.6 / v0.7 / v0.8 / v0.9 / v0.10 Experimental Plugin Wrapper

v0.5.1 adds a source-only experimental Hermes plugin wrapper at
`plugins/hermes-evidence-runtime`.

It registers four machine-readable tools around the existing Bash harness:

- `evidence_doctor`
- `evidence_active_run_status`
- `evidence_run_init`
- `evidence_drive_s_run`

v0.5.3 adds two machine-readable worker result adapter tools:

- `evidence_validate_worker_result`
- `evidence_record_worker_result`

v0.5.4 adds one machine-readable worker normalizer tool:

- `evidence_normalize_worker_result`

v0.5.5 adds one machine-readable explicit worker dry-run tool:

- `evidence_invoke_worker_dry_run`

v0.8 adds five machine-readable runtime artifact tools:

- `evidence_record_command`
- `evidence_generate_run_state`
- `evidence_policy_check`
- `evidence_final_report`
- `evidence_approval_inbox`

v0.9 adds three machine-readable integration backend tools:

- `evidence_integration_capabilities`
- `evidence_record_orchestration_result`
- `evidence_record_security_decision`

v0.10 adds machine-readable authorization lifecycle tools:

- `evidence_authorization_status`
- `evidence_persist_authorization`
- `evidence_prepare_live_approval`
- `evidence_terminalize_run`

v0.6 target: plugin enabled + evidence tools callable.
v0.6 status: plugin enabled and evidence tools callable when Hermes config
enables `hermes-evidence-runtime` and the wrapper can locate the kit scripts
through source layout, current working directory, or
`HERMES_DEV_PIPELINE_KIT_ROOT`.

v0.7 captures selected Hermes hook payloads in log-only mode.
`pre_tool_call` and `post_tool_call` were verified through a real Hermes
runtime smoke using the local `model_tools.handle_function_call` tool path.
Other registered hooks remain simulated-only or untriggered unless separately
proven.

v0.5.1-v0.10.1 plugin wrapper is experimental.
It does not replace built-in ClaudeCode/Codex/OpenCode skills.
It does not replace the existing dev-pipeline-orchestrator skill.
It does not capture official ClaudeCode/Codex/OpenCode output yet.

v0.8 status: controlled-worker C-class dry-run passes with real Hermes evidence
tool dispatch, real local RED/GREEN command evidence, real `pre_tool_call` and
`post_tool_call` hook evidence, generated run-state, generated policy result,
generated final report, and a pending approval inbox. v0.8 does not prove real
ClaudeCode/Codex/OpenCode worker capture, does not implement enforcement, does
not block Hermes tool calls, and is not C档 production readiness.

v0.9 status: optional integration backend spike. It defines raw evidence
contracts for Hermes Dynamic Workflows orchestration output and AgentGuard
security decisions. The default source-only smoke is contract-only and does not
claim real backend completion. Separate explicit real-runtime smokes prove
AgentGuard native Hermes `pre_tool_call` allow/block behavior and Dynamic
Workflows one-child completion when the optional backend sources and a
configured Hermes provider are available. The combined explicit real-runtime
smoke records both backend proofs into one generated run-state and requires
policy-check/final-report to pass. AgentGuard `allow` is audit evidence only
and must not be treated as engineering PASS; AgentGuard `block` does not
replace policy-check or Codex review.

v0.9.1 separates deterministic deployment readiness from external live E2E
freshness. Deterministic CI may pass without calling an inference provider.
External provider unavailability is classified as
`SKIP_EXTERNAL_PROVIDER_UNAVAILABLE` with a specific reason such as
`QUOTA_UNAVAILABLE`; it is never counted as `PASS_REAL_RUNTIME`.

v0.10 status: authorization lifecycle prototype for selected Dev Pipeline and
Hermes mutation paths. It binds run authorization to a goal hash, source
message/session metadata, allowed paths/actions, forbidden actions, secondary
live approval requirements, and terminal-verdict expiration. It does not
directly control Codex UI internal continuation, processes that bypass Hermes,
or universal OS-level mutation.

v0.10.1 status: durable authorization persistence. The `/tmp` bootstrap
authorization used to start a local Codex run is not the durable runtime store.
Durable run authorization lives under the canonical Dev Pipeline run directory:
`.hermes-runs/<run-id>/control/`. The store contains authorization,
authorization hash sidecar, secondary approvals, terminal verdict,
control-state, and append-only control events. Authorization state survives
process restart, terminal verdict remains authoritative after restart, and
missing or invalid control artifacts fail closed.

The durable store protects consistency inside Dev Pipeline-managed execution. It
is not a cryptographic trust boundary against the same OS user, does not control
external tools that bypass Hermes, and does not directly control Codex UI
internal continuation.

v0.5.2 adds prototype hook handlers for `pre_tool_call`, `post_tool_call`,
`on_session_start`, `on_session_end`, `on_session_finalize`, and
`subagent_stop`.

v0.5.2 hooks are prototype only.
They are non-blocking and do not enforce commit, push, policy, or command guards.
They log only when `HERMES_EVIDENCE_HOOK_LOG_DIR` is set.
They redact secret-like keys and values before writing local JSONL evidence.
They do not implement a memory provider.
They do not capture official ClaudeCode/Codex/OpenCode output yet.
They do not replace built-in ClaudeCode/Codex/OpenCode skills.
They do not replace the existing dev-pipeline-orchestrator skill.
v0.7 hook logs are written to `hook-events.jsonl` using a structured event
envelope with hashed session/tool call identifiers and redacted payload values.

The plugin wrapper is validated through source-only smoke tests and explicit
temp-HOME/live enablement checks. The installer copies the plugin source into
`~/.hermes/plugins/hermes-evidence-runtime`, but enablement remains a separate
explicit runtime step via `hermes plugins enable hermes-evidence-runtime`.
The temp-HOME discovery smoke uses `HERMES_HOME` to verify Hermes CLI discovery
without touching real HOME.
v0.6 adds live enablement and tool-call smoke evidence, but it proves only
plugin enablement and tool callability. v0.7 adds selected log-only hook
payload capture evidence; it still does not add policy blocking.
The v0.5.2 hook discovery smoke uses `/tmp/hermes-plugin-hooks-discovery-home`;
payload shape remains UNKNOWN for hooks and trigger paths not covered by the
v0.7 real runtime smoke.

v0.5.3 adds a Worker Result Contract Adapter prototype. It validates and records
simulated worker result JSON into `raw/worker/` and links that evidence into the
hash-linked event chain, generated run-state, policy-check output, and final
report. Worker results are evidence only:

- worker result JSON must not set `acceptance.complete=true`;
- deferred Codex worker results must not claim `PASS`;
- raw worker output must be tracked through provenance;
- final acceptance remains owned by Hermes/Codex gates and policy-check.

v0.5.3 still does not call real ClaudeCode, Codex, or OpenCode. It does not
claim official ClaudeCode/Codex/OpenCode output capture.

v0.5.4 adds `scripts/normalize-worker-result.sh` and
`scripts/simulate-worker-output.sh`. The normalizer accepts caller-supplied or
simulated `claude-code`, `codex`, `opencode`, and `raw` adapter output and writes
a v0.5.3-compatible worker result JSON. The `raw` adapter maps to
`worker=unknown` to preserve the existing schema. This is still a prototype:

- it does not invoke real ClaudeCode, Codex, or OpenCode;
- it does not claim official worker output capture;
- it does not implement a memory provider;
- it does not add a production hook dependency;
- it does not replace built-in ClaudeCode/Codex/OpenCode skills;
- it does not replace the existing `dev-pipeline-orchestrator` skill.

v0.5.5 adds `scripts/invoke-worker-dry-run.sh` and
`evidence_invoke_worker_dry_run`. The wrapper writes `raw.txt`,
`structured.json`, and `invocation.json` for `claude-code`, `codex`,
`opencode`, and `raw`.

Real worker invocation is optional and disabled by default. Default CI runs only
the disabled/skipped invocation lane. Optional real dry-run requires:

```bash
HERMES_EVIDENCE_ALLOW_REAL_WORKER_DRY_RUN=1 bash scripts/smoke/smoke-worker-dry-run-real-optional.sh
```

v0.5.5 still does not claim official ClaudeCode/Codex/OpenCode capture. The
harness owns final acceptance; workers own result evidence only.

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

### 中文汇报尺度策略

Hermes 必须按任务规模选择 `report_scale`：

| 任务规模 | report_scale | 汇报要求 |
|---|---|---|
| S 级小修 | compact | 第一屏给简洁 Owner Summary；仍必须包含阶段更新、技能使用证据、责任归因、待审批事项这些结构化栏目 |
| M 级功能 | standard | 输出 Owner Summary、主要阶段更新、Skill Trace 表格、验证摘要；有风险/修复/失败/审批时输出责任归因和待审批事项 |
| L / recovery / publish | full | 输出完整 Owner Summary、每个主要 Gate 的阶段更新、完整 Skill Trace、责任归因、待审批、Codex 审查、policy/doctor/ci-local 证据和 backlog |

失败或阻塞时，责任归因必须输出。需要 commit / push / PR / publish / 安装依赖 / 破坏性动作 / 修改全局配置时，`待你审批` 必须集中输出，不能藏在段落里。

小任务小汇报不是取消报告，而是结构压缩。S-level compact report 不能只输出 checklist，也不能只写“负责人摘要：中文”“技能使用证据：完整”。它仍必须显示：

- `## 负责人摘要`
- `## 阶段更新`
- `## 技能使用证据`
- `## 责任归因`
- `## 待你审批`

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

`ci-local.sh` 会聚合 Bash 语法检查、manifest 检查、policy-check fixtures、smoke tests、JSON parse、v0.3 generated run-state E2E smoke 和安全扫描。

当前版本不要求 GitHub Actions CI。不要新增 `.github/workflows/ci.yml`，除非用户明确要求。

这些检查是 **harness checks**。其中 `scripts/smoke/smoke-generated-run-state.sh` 是最小真实 runtime behavior validation；其他 `examples/policy/*.json` 是 policy fixture validation。

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

### Runtime Enforcement (v2)

v2 adds 7 automated policy checks enforced by `policy-check.sh`:

- **Scale Classification Guard** — M/L tasks cannot be downgraded to S
- **M/L Delegation Requirement** — M/L tasks must delegate to ClaudeCode (or record waiver)
- **Matt Skill Evidence Gate** — required Matt skill evidence must be present
- **Full Report Sections Gate** — L/recovery/publish tasks require all 9 report sections
- **Verification Exit Code Gate** — M/L tests_pass=true requires exit code evidence
- **Vague M/L Intake Gate** — vague M/L tasks must complete intake before execution
- **Codex Unavailable Handling** — Codex can be deferred with reason, cannot fabricate PASS

See [docs/workflow-overview.md](docs/workflow-overview.md) for full details and [docs/report-contract.md](docs/report-contract.md) for the enforcement contract table.

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

## v0.4 Hash-linked State Machine Harness

v0.4 adds a local, hash-linked runtime layer on top of the v0.3 executable evidence harness.

- Each run has `events.jsonl` and `state.json`.
- Every transition is appended through `scripts/append-event.sh`.
- Every event stores `prev_event_hash`, `event_hash`, and artifact hashes.
- `scripts/replay-run.sh` recomputes event hashes, previous-hash links, artifact hashes, and state transitions.
- `scripts/generate-run-state.sh` depends on replay evidence and writes `event_chain` / `replay_result`.
- `scripts/policy-check.sh` validates replay and state-machine evidence before acceptance.
- `scripts/final-report.sh` reports generated evidence, not agent self-evaluation.

This is tamper-evident, not tamper-proof. A local user with write access can delete or rewrite run files. The hash chain detects whether the submitted event/artifact chain is internally consistent; it does not defend against root-level filesystem control.

Policy fixtures are examples for policy validation only. Runtime validation requires a real run directory with `events.jsonl`, `state.json`, raw command logs, replay output, generated run-state, policy output, and final report.

---

## v0.5.1 / v0.5.2 / v0.5.3 / v0.5.4 / v0.5.5 / v0.6 / v0.7 / v0.8 Plugin Wrapper Boundary

`plugins/hermes-evidence-runtime` is an experimental wrapper around the existing
v0.4 Bash harness scripts. It is not a new runtime and does not rewrite the
state machine.

- It does not replace built-in ClaudeCode/Codex/OpenCode skills.
- v0.5.2 hooks are prototype-only, non-blocking probes.
- It does not implement a memory provider.
- It does not replace the existing dev-pipeline-orchestrator skill.
- v0.5.3 worker result adapter validates simulated worker result contracts only.
- v0.5.4 normalizer converts caller-supplied or simulated worker output into the v0.5.3 worker-result contract.
- v0.5.5 explicit worker dry-run records invocation truth (`real_invocation`, `skipped_reason`, and artifact paths).
- v0.6 proves plugin enablement and `evidence_*` tool callability only.
- v0.7 proves log-only observation for the hooks actually captured. Real smoke captured `pre_tool_call` and `post_tool_call`.
- v0.8 proves a controlled-worker C-class dry-run using real Hermes evidence tool dispatch, real command logs, real pre/post hook evidence, generated run-state, generated policy result, generated final report, and pending approval inbox.
- It does not capture official ClaudeCode/Codex/OpenCode output yet.
- It does not call real ClaudeCode/Codex/OpenCode unless the explicit optional dry-run lane is enabled.
- v0.8 does not implement enforcement and is not C档 production readiness.
- `scripts/install.sh` copies it to `~/.hermes/plugins/hermes-evidence-runtime`;
  live plugin enablement is a separate explicit runtime step.
- Its smoke tests use source-only import and temp-HOME plugin discovery under `/tmp`.
- Hook logs are written only when `HERMES_EVIDENCE_HOOK_LOG_DIR` is set.
- Hook runtime payload shape is certified only for the hooks and trigger path covered by the v0.7 smoke.

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
