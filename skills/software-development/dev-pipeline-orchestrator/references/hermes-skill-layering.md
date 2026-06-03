# Hermes Skill Layering for Development

Date: 2026-06-02

## Architecture

```
Hermes (orchestrator)
├── dev-pipeline-orchestrator — entrypoint for all dev tasks
├── gstack — heavy workflow (review/ship/deploy/retro)
├── obra/superpowers — light methodology (TDD/plans/spike/subagent)
└── mattpocock/skills — Claude Code execution (tdd/diagnose/prototype)

Claude Code (execution worker)
├── mattpocock/skills — invoked via work order "Required Matt skill"
└── claude-plugins-official — code-review, github, playwright
```

## Routing Rules

| Scenario | Hermes uses | ClaudeCode uses | Codex gate |
|----------|-------------|-----------------|------------|
| new feature | writing-plans + gstack plan-eng-review | tdd | M opt / L req |
| bug fix | gstack investigate | diagnose | high-risk req |
| uncertain UI/state | writing-plans | prototype | L required |
| recovery task | gstack investigate + dev-pipeline-orchestrator | diagnose + tdd | L required |
| release | gstack ship | do not release | required |

## Overlap Resolution (2026-06-02)

Deleted overlapping skills:
- `systematic-debugging` → replaced by `gstack investigate`
- `requesting-code-review` → replaced by `gstack review`

## User Preferences

- User expects ALL dev tasks to flow through dev-pipeline-orchestrator
- User expects Hermes to NEVER self-accept
- User expects generated files to use official commands only
- User expects recovery tasks to have baseline verification (Gate 1.5)
- User expects Codex review to be REQUIRED for L-level, not optional
