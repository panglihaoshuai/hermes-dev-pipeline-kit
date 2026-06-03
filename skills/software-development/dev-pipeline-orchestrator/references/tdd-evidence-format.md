# Strict TDD Evidence Format (proven 2026-06-02)

For S/M tasks requiring TDD, ClaudeCode must output this exact structure:

```
### TDD Evidence

RED:
- test file written: <path>
- command: <test command>
- exit code: <must be non-zero>
- expected failure: YES — <error type, e.g. MODULE_NOT_FOUND>
- key output: <exact error line>

GREEN:
- implementation file written: <path>
- command: <test command>
- exit code: <must be 0>
- expected pass: YES
- key output: <pass line, e.g. "pass 1, fail 0">

REFACTOR:
- refactor performed: <yes/no>
- command: <if yes>
- exit code: <if yes>
- key output: <if yes>
```

If RED exit code is 0, TDD was not followed — work order is FAIL.
If GREEN exit code is non-zero, implementation is broken — work order is FAIL.

## Smoke Test Results

### 2026-06-02 S-level smoke test (JavaScript, CommonJS)

- Project: /tmp/hermes-dev-pipeline-smoke-2
- Files: src/add.js, src/add.test.js
- ClaudeCode invocation: delegate_task (33s, no timeout)
- TDD: RED exit 1 (MODULE_NOT_FOUND) → GREEN exit 0 (pass 1, fail 0)
- Forbidden files: no violations
- Result: PASS

### 2026-06-02 S-level smoke test (TypeScript, first attempt)

- Project: /tmp/hermes-dev-pipeline-smoke
- Issue: ClaudeCode modified package.json (added "type": "module")
- Lesson: Use plain JavaScript with CommonJS for smoke tests to avoid ESM issues
- ClaudeCode invocation: delegate_task (127s)
- Result: PARTIAL (forbidden file violation)
