# AGENTS.md

## Agent Roles

- Hermes: product manager, architect, workflow owner, QA verifier.
- ClaudeCode: implementation worker.
- Codex: reviewer / diagnostic / risk gate.

## Repository Rules

Describe the repository layout, ownership boundaries, generated file policy, and files that require explicit approval before editing.

## Testing and Validation

List required commands for baseline checks, targeted checks, build, lint, typecheck, and E2E where applicable.

## Git and PR Rules

- No `git add -A`.
- Stage explicit files only.
- Commit/PR only after approval.
- Include evidence report in PR.

## Generated Files

Generated files must be regenerated with official commands. Manual generated-file edits require approval and evidence.

## Security

Never print, stage, commit, or publish secrets. Review staged files before commit/push/PR.

## Backlog and Baseline Debt Policy

Separate current-task blockers from unrelated baseline technical debt. Do not expand scope into baseline cleanup without explicit approval.

