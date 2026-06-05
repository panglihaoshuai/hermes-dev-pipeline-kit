# Example Runs

This directory is reserved for committed, scrubbed examples of v0.3 run
directories.

Runtime behavior validation should prefer temporary runs created by:

```bash
scripts/smoke/smoke-generated-run-state.sh
```

Policy fixtures under `examples/policy/` are hand-authored unit fixtures. They
do not prove a real command executed. True runtime evidence needs:

- `run-manifest.json`
- `raw/command-log.jsonl`
- `raw/claudecode-result.json`
- `generated/run-state.json`
- `generated/final-report.md`

