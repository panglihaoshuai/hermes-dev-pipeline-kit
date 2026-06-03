# CommonJS Zero-Dependencies Verification Pattern

When creating smoke tests, throwaway projects, or minimal repros for the dev pipeline,
prefer CommonJS + Node.js built-in test runner. This avoids npm install entirely.

## Pattern

### package.json
```json
{
  "name": "project-name",
  "version": "1.0.0",
  "main": "src/index.js",
  "scripts": {
    "test": "node --test src/index.test.js"
  }
}
```

### src/index.js
```javascript
function add(a, b) { return a + b; }
module.exports = { add };
```

### src/index.test.js
```javascript
const { describe, it } = require('node:test');
const assert = require('node:assert');
const { add } = require('./index');

describe('add', () => {
  it('returns sum', () => { assert.strictEqual(add(2, 3), 5); });
});
```

## Why This Works

- `node --test` is built into Node.js 18+, no jest/vitest/mocha needed
- `require()` / `module.exports` works without `"type": "module"` in package.json
- No lockfile needed, no node_modules, no npm install
- Tests run instantly with zero setup

## When to Use

- Smoke tests validating pipeline behavior
- Minimal repros for bug reports
- Throwaway prototypes
- CI template validation (the test command works in GitHub Actions too)

## When NOT to Use

- Production projects (use the project's established test framework)
- Projects that need DOM/browser APIs (use vitest/jsdom)
- TypeScript projects (use vitest or jest with ts-jest)

## Pitfall: ESM Requires package.json Change

If you use `import`/`export` (ESM), Node.js requires `"type": "module"` in package.json.
This modifies a potentially forbidden file. CommonJS avoids this entirely.
See Pitfall 6 in the orchestrator skill for the full explanation.
