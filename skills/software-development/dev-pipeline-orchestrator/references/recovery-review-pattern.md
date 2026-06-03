# Recovery Review Pattern — 2026-06-02

When a feature was implemented through a failed workflow (no TDD, no Codex review, hand-edited generated files, self-accepted by Hermes), use this recovery pattern.

## Recovery Review Gates

1. **Gate 0**: Classify as L (previous failed attempt is automatic L)
2. **Gate 1**: Full context discovery (git log, git show prior commits, git diff vs origin)
3. **Gate 1.5**: Baseline verification (tsc, vitest, eslint, build) — distinguish baseline errors from feature-introduced errors
4. **Gate 2**: Code-state audit of ALL feature files (not just grep)
5. **Gate 3**: Generate repair work orders (NOT fix code)
6. **Codex Plan Review**: REQUIRED for recovery tasks
7. **Gate 8**: Report with `execution complete: false`

## Code-State Audit Checklist

For each feature file, check:
- API: provider reuse, SSE handling, error handling, API key safety, test seam
- Store: state flow, adopt/undo safety, stale reference, malformed data, coupling
- UI: all states (loading/streaming/error/empty/completed), adopt/undo consistency, close cleanup, i18n, testable selectors
- Integration: entry point correctness, i18n key completeness, generated file status
- Tests: API smoke, store unit, UI smoke, E2E, mock mechanism

## Baseline Error Classification

When running tsc/vitest/eslint, categorize errors as:
- **baseline existing**: errors that exist in origin/main (not our problem)
- **review feature introduced**: errors only in our new files
- **unknown**: need investigation

Do NOT just grep for the feature name — run full check and count totals.

## Generated File Recovery

If a generated file was hand-edited:
1. Identify the official generation command (check build tool config)
2. Determine if revert + official re-gen would produce correct output
3. If yes: WO to revert + re-gen via official command
4. If no: WO with Codex approval for manual repair + evidence explanation
