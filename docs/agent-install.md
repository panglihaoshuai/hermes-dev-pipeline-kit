# Agent Install Guide

## 用户触发提示词 / User Prompt

```text
安装这个 Hermes 工作流：<repo-url>
```

## Agent 执行流程 / Agent Procedure

### Step 1: Clone

```bash
git clone <repo-url> /tmp/hermes-dev-pipeline-kit-install
cd /tmp/hermes-dev-pipeline-kit-install
```

### Step 2: Read in order

1. `BOOTSTRAP.md` — agent bootstrap contract
2. `manifest.yaml` — machine-readable dependency map
3. `README.md` — human-facing docs
4. `AGENTS.md` — agent protocol
5. `CLAUDE.md` — ClaudeCode protocol

### Step 3: Pre-flight

```bash
bash scripts/install.sh --dry-run
bash scripts/doctor.sh
```

### Step 4: Dependency assessment

```bash
bash scripts/install-deps.sh --dry-run
```

- `git`, `bash`, `grep` — must exist (system tools)
- `gh` — optional, do NOT auto-install, report as missing
- `gstack` — recommended, output install suggestion, ask user
- `mattpocock-skills` — recommended, output install suggestion, ask user
- Unknown dependencies — only report, never install

### Step 5: Ask user for approval

Before modifying any global file (`~/.hermes/skills/`, `~/.claude/CLAUDE.md`):

- Show what will be installed
- Show what will NOT be modified
- Ask: "确认安装？[y/N]"

### Step 6: Install (only after approval)

```bash
bash scripts/install.sh --yes
```

### Step 7: Verify

```bash
bash scripts/doctor.sh
```

### Step 8: Report

Output:

```markdown
## 安装报告 / Install Report

- repo cloned: yes/no
- skills installed:
  - dev-pipeline-orchestrator: installed/failed
  - dev-pipeline-report: installed/failed
- ClaudeCode delegation protocol: present/missing/needs manual append
- missing dependencies:
  - gh: optional, not installed
  - gstack: recommended, not installed
  - Matt skills: recommended, not installed
- doctor verdict: PASS / PARTIAL / FAIL
- user action required:
  - append protocol to ~/.claude/CLAUDE.md (if missing)
  - install optional dependencies (if needed)
```

### Step 9: Cleanup

```bash
rm -rf /tmp/hermes-dev-pipeline-kit-install
```

## 绝对不做的事 / Never Do

- Do NOT modify user business projects
- Do NOT push to any remote
- Do NOT create GitHub repos
- Do NOT print or store secrets
- Do NOT overwrite `~/.claude/CLAUDE.md` (only warn)
- Do NOT install unknown-source dependencies
- Do NOT silently modify global config
- Do NOT run `git add -A`

## Expected Doctor Results

| Condition | Verdict |
|-----------|---------|
| Core skills + protocol + all deps | PASS |
| Core skills + protocol, some optional deps missing | PARTIAL |
| Core skills missing or protocol missing | FAIL |
