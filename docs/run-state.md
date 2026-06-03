# Run State — Pipeline Execution State Snapshot

## What is run-state?

The **run-state** is a JSON object that captures the complete execution state of a
hermes-dev-pipeline-kit pipeline run. It serves as the single source of truth for:

- Which gate the pipeline has reached
- What classification the task received
- What work orders exist and their status
- What verification results have been collected
- Whether user approvals have been granted
- What the final acceptance decision is

The run-state is the primary input for `policy-check.sh`, which reads it to enforce
pipeline policies at each gate.

## Lifecycle

### Creation (Gate 0)

The run-state is created at **Gate 0** (classification) when a pipeline run begins.
At creation it contains:

- `run_id` — unique identifier (ISO 8601 timestamp or UUID)
- `project` — the project being worked on
- `mode` — execution mode (`dry_run`, `plan_only`, or `auto_run`)
- `current_gate` — set to `"Gate 0"`
- `classification` — scale (S/M/L), reasons, and risk level
- Empty arrays for work_orders, allowed_files, etc.

### Updates (Every Gate)

The run-state is updated at each gate transition:

| Gate   | Updates                                                     |
|--------|-------------------------------------------------------------|
| Gate 0 | classification, mode, project                               |
| Gate 1 | work_orders, allowed_files, forbidden_files                 |
| Gate 3 | codex.plan_review_verdict                                   |
| Gate 5 | codex.diff_review_verdict                                   |
| Gate 7 | command_evidence, modified_files                            |
| Gate 8 | verification (git diff, tests, typecheck)                   |
| Gate 9 | acceptance, approval_gates, baseline_debt, follow_up_backlog|

## Schema Field Descriptions

### Top-level fields

| Field              | Type     | Description                                    |
|--------------------|----------|------------------------------------------------|
| `run_id`           | string   | Unique run identifier                          |
| `project`          | string   | Project path or name                           |
| `mode`             | enum     | `dry_run`, `plan_only`, or `auto_run`          |
| `current_gate`     | string   | Current gate (e.g. "Gate 0", "Gate 3.5")      |
| `classification`   | object   | Scale, reasons, risk level                     |
| `work_orders`      | array    | Subtasks with owner, skill, status, retries    |
| `allowed_files`    | string[] | Files the run may modify                       |
| `forbidden_files`  | string[] | Files the run must NOT modify                  |
| `modified_files`   | string[] | Files actually modified                        |
| `command_evidence` | array    | Commands run with exit codes and results       |
| `codex`            | object   | Codex review verdicts                          |
| `verification`     | object   | Git diff, test, and typecheck results          |
| `acceptance`       | object   | Final completion and decision                  |
| `approval_gates`   | object   | User approvals for commit/push/PR/repo create  |
| `baseline_debt`    | array    | Pre-existing tech debt acknowledged            |
| `follow_up_backlog`| array    | Items deferred to future runs                  |

### Classification

- `scale` — S (small/single-file), M (medium/multi-file), L (large/cross-cutting)
- `reasons` — human-readable reasons for the assigned scale
- `risk_level` — low, medium, or high

### Codex

- `plan_review_verdict` — result of Codex plan review (PASS, PASS_WITH_REQUIRED_CHANGES, FAIL, UNKNOWN, NOT_REQUIRED)
- `diff_review_verdict` — result of Codex diff review (same enum)
- `disabled_by_user` — true if user explicitly skipped Codex review

For **S-level** tasks, both verdicts default to `NOT_REQUIRED` (Codex review is skipped).

### Verification

- `git_diff_name_status` — output of `git diff --name-status`
- `git_diff_check_exit` — exit code from `git diff --check` (0 = clean)
- `tests_pass` — boolean, true if all tests passed
- `typecheck_exit` — exit code from typecheck, or null if not applicable

### Approval Gates

These flags track whether the user has approved destructive operations:

- `commit_approved` — git commit is allowed
- `push_approved` — git push is allowed
- `pr_approved` — pull request creation is allowed
- `repo_create_approved` — new repository creation is allowed

## How policy-check.sh Uses It

`policy-check.sh` reads the run-state JSON and validates pipeline policies:

1. **Forbidden file check** — ensures `modified_files` contains no entries from `forbidden_files`
2. **Codex review check** — for M/L tasks, ensures plan_review and diff_review verdicts are not FAIL
3. **Verification check** — ensures `tests_pass` is true and `git_diff_check_exit` is 0
4. **Acceptance check** — ensures `acceptance.complete` is true and `final_decision` is ACCEPTED
5. **Approval gate checks** — ensures required approvals are granted before proceeding

If any check fails, `policy-check.sh` exits non-zero with a description of the violation.

## Relationship to dev-pipeline-report

The **dev-pipeline-report** is the human-readable output generated from the run-state.
While run-state is the machine-readable source of truth, the report is formatted for
review in PR descriptions, terminal output, and documentation.

The report includes:
- A summary table of gate results
- The classification decision
- Verification results
- Any follow-up backlog items

## Version Status

### v0.2 (Current)

- Schema definition exists at `schema/run-state.schema.json`
- Sample exists at `examples/run-state.sample.json`
- Documentation exists (this file)
- `policy-check.sh` validates against run-state structure

### Future Work (v0.3+)

- Runtime integration: auto-populate run-state from gate execution
- Schema validation hook in pipeline entry point
- Run-state persistence between gate transitions
- Diff of run-state across pipeline stages
- Integration with dev-pipeline-report generator
