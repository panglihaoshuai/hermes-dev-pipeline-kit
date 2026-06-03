# Hermes Dev Pipeline Kit — Agent Bootstrap

## What this repository is

This repository packages Hermes workflow skills for development pipeline orchestration:

- `dev-pipeline-orchestrator` — main development task entrypoint
- `dev-pipeline-report` — final evidence/verification report format
- Templates for ClaudeCode work orders, Codex reviews, and verification reports
- ClaudeCode delegation protocol
- Agent-facing install scripts and docs

This is NOT an official Hermes, Claude Code, Codex, OpenAI, Anthropic, or gstack project.

## If a user gives you this repo URL

When the user says:

```
安装这个 Hermes 工作流：<repo-url>
```

You must:

### Step 1: Clone and read

```bash
git clone <repo-url> /tmp/hermes-dev-pipeline-kit-install
cd /tmp/hermes-dev-pipeline-kit-install
```

Read these files in order:

1. `BOOTSTRAP.md` (this file)
2. `manifest.yaml` (machine-readable dependency map)
3. `README.md` (human-facing docs)
4. `AGENTS.md` (agent protocol)
5. `CLAUDE.md` (Claude Code protocol)

### Step 2: Pre-flight checks

```bash
bash scripts/install.sh --dry-run
bash scripts/doctor.sh
```

### Step 3: Dependency assessment

If `doctor.sh` reports missing dependencies:

- Check `manifest.yaml` for known dependency sources.
- Run `bash scripts/install-deps.sh --dry-run` if available.
- For `git`, `bash` — these are system tools, must already exist.
- For `gh` (GitHub CLI) — do NOT auto-install. Report as optional.
- For `gstack` / Matt Pocock skills — output install suggestion, ask user before installing.
- Never install unknown-source dependencies.
- Never install dependencies without user approval.

### Step 4: Install (requires user approval)

Ask the user before proceeding. Then:

```bash
bash scripts/install.sh --yes
```

The installer will:

- Copy skills to `~/.hermes/skills/software-development/`
- Backup any existing same-name skills
- Check `~/.claude/CLAUDE.md` for delegation protocol (warn if missing, never overwrite)

### Step 5: Verify

```bash
bash scripts/doctor.sh
```

### Step 6: Report

Output a summary including:

- Skills installed (dev-pipeline-orchestrator, dev-pipeline-report)
- ClaudeCode delegation protocol status (present / missing / needs manual append)
- Missing dependencies (if any)
- Doctor verdict: PASS / PARTIAL / FAIL
- Next steps for the user

## Hard safety rules

- Do NOT modify user business projects.
- Do NOT print or store secrets.
- Do NOT push to any remote.
- Do NOT create GitHub repos.
- Do NOT run `git add -A`.
- Do NOT overwrite existing `~/.claude/CLAUDE.md`.
- Do NOT install unknown-source dependencies.
- Do NOT silently modify global config.
- Ask before installing dependencies or changing `~/.claude/CLAUDE.md`.

## Expected final result

| Component | Expected |
|-----------|----------|
| dev-pipeline-orchestrator | installed in `~/.hermes/skills/software-development/` |
| dev-pipeline-report | installed in `~/.hermes/skills/software-development/` |
| ClaudeCode delegation protocol | present in `~/.claude/CLAUDE.md` or user warned |
| doctor verdict | PASS (core) or PARTIAL (optional deps missing) |

## Cleanup after install

```bash
rm -rf /tmp/hermes-dev-pipeline-kit-install
```
