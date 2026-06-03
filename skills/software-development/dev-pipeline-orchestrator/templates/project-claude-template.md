# CLAUDE.md

## Project Overview

Describe the project, core product goal, primary users, and important architectural boundaries.

## Common Commands

List verified commands only. Do not invent build, test, lint, typecheck, package, release, or deploy commands.

## Development Workflow

Use Hermes dev-pipeline-orchestrator as primary workflow owner.

ClaudeCode should only act through Hermes work orders unless explicitly instructed.

## Testing Requirements

Record the required baseline and task-specific validation commands. Include expected test framework and any mocking rules.

## Generated Files Policy

Generated files must be regenerated with official commands. Do not hand-edit generated files unless approved.

## Forbidden Actions

- Do not commit unless explicitly instructed.
- Do not modify secrets.
- Do not run destructive commands.
- Do not hand-edit generated files unless approved.

## Work Order Protocol

ClaudeCode must follow allowed files, forbidden files, required Matt skill, validation commands, and structured report.

## Secrets and Environment

Never print or commit secrets.

