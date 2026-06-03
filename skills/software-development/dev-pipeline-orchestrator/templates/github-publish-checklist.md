# GitHub Publish Checklist

Use this checklist only when the user explicitly requested GitHub publishing, repository creation, push, PR, deployment, or package upload.

## Request

- publish requested: yes/no
- requested operation: create repo / push / PR / release / deploy / package upload / other
- user pre-authorization: none / commit / repo creation / push / PR / release / deploy

## Repository Discovery

```bash
git status --short --branch
git remote -v
git branch --show-current
git log --oneline -5
```

- working tree clean:
- current branch:
- remote present:
- latest commits reviewed:

## GitHub Toolchain Discovery

```bash
which gh || true
gh auth status || true
```

- gh CLI available:
- gh authenticated:
- Hermes GitHub skill available:
- ClaudeCode GitHub plugin available:
- gstack ship/review available:
- missing tooling:

## Package / Build Discovery

```bash
ls
cat package.json 2>/dev/null || true
ls pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null || true
ls pyproject.toml requirements.txt Cargo.toml go.mod 2>/dev/null || true
```

- package manager:
- framework:
- test command:
- build command:
- lint command:
- typecheck command:
- package/release command:
- missing scripts:

## Project Protocol Files

- README.md: present/missing/intentionally skipped
- CLAUDE.md: present/missing/intentionally skipped
- AGENTS.md: present/missing/intentionally skipped
- .github/workflows: present/missing/intentionally skipped

## Safety Checks

- no secrets staged:
- no forbidden files staged:
- explicit staged files only:
- no `git add -A`:
- no force push:
- no dirty working tree push:
- rollback instructions prepared:

## Approval Gates

- commit approval required:
- remote/repo creation approval required:
- push approval required:
- PR approval required:
- public repo approval required:

## Decision

Choose exactly one:
- READY_FOR_USER_APPROVAL
- MISSING_TOOLING
- NEEDS_PROJECT_PROTOCOL_FILES
- NEEDS_BUILD_OR_TEST_SETUP
- BLOCKED

