# AGENTS.md — Agent Instructions for hermes-dev-pipeline-kit

## Role Definitions

### Hermes Agent
- Primary orchestrator for development tasks
- Can read/write files, run commands, manage git operations
- Always ask for approval before committing

### Claude Code
- Code-focused assistant for script editing and review
- Follows same git and security rules as Hermes

### Codex
- Batch code generation agent
- Must validate all output with `bash -n` before completion

---

## Git Workflow

1. **Never use `git add -A`** — always stage files explicitly:
   ```bash
   git add path/to/specific/file
   ```

2. **Commit requires approval** — show the diff and ask before committing

3. **Commit messages** follow conventional format:
   ```
   <type>: <description>
   
   Types: feat, fix, docs, chore, test, refactor
   ```

---

## Security Rules

**NEVER commit:**
- Secrets, API keys, tokens, passwords
- Absolute paths containing usernames (e.g., `<USER_HOME>/...`)
- `.env` files or environment variable dumps

---

## Test & Validation Commands

### Full health check
```bash
bash scripts/doctor.sh
```

### Script syntax validation
```bash
bash -n scripts/*.sh
```

---

## Pre-Publish Checklist

Before any release or merge to main:

- [ ] No absolute paths (grep for `/Users/`, `/home/`, etc.)
- [ ] No secrets or API keys in any file
- [ ] No backup files (`*.bak`, `*~`, `*.orig`)
- [ ] No `.env` files committed
- [ ] `bash scripts/doctor.sh` passes
- [ ] `README.md` is complete and accurate
- [ ] `LICENSE` file is present

---

## Pull Request Requirements

Every PR must include:

1. **What changed** — brief summary of modifications
2. **Why** — motivation or issue reference
3. **`bash scripts/doctor.sh` output** — paste the full output
4. **`bash scripts/install.sh --dry-run` output** — verify install path

---

## Forbidden Actions

- Modifying files under `skills/` without explicit instruction
- Adding external dependencies (this is a pure markdown + bash project)
- Running `git push` without explicit approval
- Committing without showing diff first
