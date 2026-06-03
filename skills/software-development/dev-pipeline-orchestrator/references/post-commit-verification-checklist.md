# Post-Commit Verification Checklist

Date: 2026-06-02
Project: <USER_HOME>/projects/<PROJECT_NAME>
Commit: <COMMIT_HASH> (example: add comprehensive tests for feature)

## Context

User treated post-commit verification as a distinct pipeline phase separate from Gate 9 commit approval. The verification serves as an independent audit of commit cleanliness before risk items are tracked separately.

## Checklist (Phase 1)

Run all commands without wrapping/grep. Record raw exit codes.

```bash
git status --short --branch
git log --oneline -5
git show --stat --oneline HEAD
git show --name-status --oneline HEAD
npx vitest run
npx tsc --noEmit
git diff --check HEAD~1..HEAD
```

## Verification Criteria

| check | pass condition |
|-------|---------------|
| git status | clean working tree (or only expected untracked) |
| commit scope | only expected files in HEAD commit |
| vitest | exit 0, all tests pass, 0 regressions |
| tsc | exit code matches baseline; 0 new errors in committed files |
| git diff --check | no whitespace errors |
| tsc review-related | `grep -E "(review\.ts\|useReviewStore\.ts\|ReviewPanel\.tsx\|review\.test)"` on tsc output = 0 matches |

## Output Format

```
## Phase 1: Post-Commit Verification Report

### 1. Branch State
### 2. Commit History
### 3. HEAD Commit Content (files + line counts)
### 4. vitest (exit, files, tests, regressions)
### 5. tsc (exit, total errors, review-related errors)
### 6. tsc baseline error categorization (table: category, files, count, root cause)
### 7. git diff --check
### 8. Conclusion
### 9. Remaining risks (table: ID, risk, severity, recommended handling)
```

## tsc Baseline Error Categorization Pattern

When tsc has baseline errors, categorize them by root cause so the user can decide which to fix:

| category | example files | example root cause |
|----------|--------------|-------------------|
| next module missing | app/**/*.tsx | TanStack project, no next dependency, tsconfig residual include |
| jest-dom type missing | *.test.tsx | @testing-library/jest-dom not in tsconfig types |
| test file missing vitest imports | suggestionBubble.test.tsx | no `import { describe, it, expect, vi } from "vitest"` |
| upstream type strictness | CoverLetter.tsx, PoliticalInfo | type definition too narrow |
| browser API types | fileSystem.ts | IndexedDB/File System Access API incomplete types |
| other | various | per-file analysis |

## Risk Separation Rule

Remaining risks must be listed independently with recommended handling. Do NOT mix risk cleanup into the current commit. Each risk becomes a potential future work order.

## Key Lesson

When verifying tsc errors are "review-related", grep for exact file paths (`review\.ts`, `useReviewStore\.ts`, `ReviewPanel\.tsx`, `review\.test`) not just the substring "review" — which matches unrelated files like `MobileWorkbench.tsx` (previewPanelCollapsed) and `preview/index.tsx`.
