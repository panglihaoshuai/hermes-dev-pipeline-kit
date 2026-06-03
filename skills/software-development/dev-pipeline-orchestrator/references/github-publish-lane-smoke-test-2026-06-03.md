# GitHub Publish Lane — Runtime Smoke Test Evidence

Date: 2026-06-03
Project: /tmp/hermes-github-publish-smoke (Node/CommonJS, zero dependencies)
Verdict: PASS

## Gate Mapping (Smoke Test → Skill Gates)

| Smoke Test Gate | Skill Gate(s) | Purpose |
|---|---|---|
| Gate A: Publish Lane Detection | User Entrypoint + Gate 0 | Detect publish intent, enter lane |
| Gate B: Repository Discovery | Gate 1 (Context Discovery) | git status, remote, branch, log |
| Gate C: GitHub Toolchain Discovery | GitHub Toolchain Discovery section | gh CLI, auth, skills, plugins |
| Gate D: Package/Build Discovery | Package/Build Discovery section | package manager, scripts |
| Gate E: Project Protocol File Check | Project Protocol Files section | README, CLAUDE.md, AGENTS.md, CI |
| Gate F: Verification | Gate 6 (Hermes Verification) | git diff, tests, CI content |
| Gate G: Publish Approval Stop | Gate 9.5 (GitHub Publish Approval) | Halt before push/repo/PR |

## Runtime Results

### Gate B — Repository Discovery
- branch: main
- remote: MISSING (no origin)
- working tree: clean (tracked), 4 untracked (generated)
- committed: yes (1 commit)

### Gate C — GitHub Toolchain Discovery
- gh CLI: available (/opt/homebrew/bin/gh)
- gh auth: available (<GITHUB_USER>, scopes: <SCOPES_REDACTED>)
- GitHub skill: available (6 skills: repo-management, pr-workflow, issues, code-review, auth, codebase-inspection)
- gstack ship/review: available

### Gate D — Package/Build Discovery
- package manager: npm (no lockfile, zero deps)
- test: `node --test src/index.test.js`
- build: NONE
- lint: placeholder
- typecheck: NONE (CommonJS)

### Gate E — Protocol Files Generated
All 4 missing, all 4 generated:
- README.md: quick start, project structure, license
- CLAUDE.md: project context, conventions, forbidden, validation commands
- AGENTS.md: Hermes/ClaudeCode/Codex roles, git workflow
- .github/workflows/ci.yml: checkout + setup-node + node --test (matrix: 18/20/22)

### Gate F — Verification
- git status: 4 untracked files
- git diff --name-status: empty (no modified tracked files)
- git diff --check: exit 0
- npm test: 3/3 pass, 56ms
- CI yml: checkout ✓ setup-node ✓ test ✓

### Gate G — Approval Stop
Pipeline halted. No push, no repo create, no PR executed.

## Key Observations

1. **Detection works**: "打包上传 GitHub" correctly triggers the Publish Lane.
2. **Missing remote is non-fatal**: Pipeline discovers missing origin and reports it without failing.
3. **Protocol file generation works**: All 4 files generated in Gate E with appropriate content.
4. **CommonJS zero-deps verification**: `node --test` runs without npm install — ideal for smoke tests.
5. **Approval gate holds**: Pipeline stops cleanly at Gate G with explicit "user approval required".
6. **gh auth available but unused**: Auth was discovered but never called — correct behavior for read-only smoke.
