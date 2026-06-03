# CLAUDE.md — Claude Code Project Instructions

## Project Overview

hermes-dev-pipeline-kit 是一个可分发的 Hermes skill 包，用于标准化 AI Agent 开发流程。

- 纯 markdown + bash 脚本，无外部依赖
- 语言风格：中文正文 + 英文技术术语

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bash scripts/doctor.sh` | Full health check (syntax + keyword verification) |
| `bash -n scripts/*.sh` | Syntax validation for all scripts |

---

## Conventions

- **Language**: Chinese prose, English code/terms
- **File style**: Match existing patterns in the repo
- **No external dependencies**: Do not introduce any

---

## Forbidden Actions

1. **Do not modify files under `skills/`** unless explicitly asked
2. **Do not add dependencies** — this is a self-contained kit
3. **Do not commit without approval** — always ask first
4. **Do not use `git add -A`** — stage files explicitly

---

## Validation Workflow

Before completing any task:
```bash
bash -n scripts/*.sh          # syntax check
bash scripts/doctor.sh         # full health check
```
