# Role Performance Fields — Added 2026-06-02

The dev-pipeline-report now includes a "Role Performance" section that tracks which parties performed their expected roles.

## Fields

```markdown
## Role Performance

- Hermes role performed:
  - product manager: yes/no
  - architect: yes/no
  - QA verifier: yes/no
- ClaudeCode role performed:
  - implementation worker: yes/no
- Codex role:
  - not used / optional review / required gate / diagnosis / diff review
- Codex disabled by user: yes/no
```

## When to Fill Each Field

**Hermes product manager:** yes if Hermes clarified user goal, defined scope/non-goals, made product decisions.
**Hermes architect:** yes if Hermes designed architecture, chose patterns, defined interfaces.
**Hermes QA verifier:** yes if Hermes ran verification commands and collected evidence.

**ClaudeCode implementation worker:** yes if ClaudeCode executed work orders and produced code.

**Codex role:**
- `not used` — S-level fast path, no Codex needed
- `optional review` — M-level, Codex was invited but not required
- `required gate` — L-level, Codex plan review or diff review was mandatory
- `diagnosis` — Codex was invoked to diagnose a failure
- `diff review` — Codex reviewed the final diff before acceptance

**Codex disabled by user:** yes if user said "不用 Codex" / "no Codex" etc.
