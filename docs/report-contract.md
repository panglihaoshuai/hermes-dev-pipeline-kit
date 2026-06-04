# Dev Pipeline Report Contract

## Version History

### v0.1 — Markdown-only (current)

The initial report format is a Markdown document written to the working directory
after each pipeline run. It is human-readable and designed for review in terminals,
GitHub PRs, and editors. There is no machine-readable contract in v0.1.

### v0.2 — Markdown for humans + JSON contract for agents/policy-check

Starting in v0.2, the pipeline also produces a structured JSON report alongside the
Markdown report. This JSON document conforms to a formal schema and is intended for:

- **Automated policy checks** — verify pipeline invariants before merging (e.g.
  `verification_complete` must be `true`, `safety.safe_to_push_pr` must be `true`).
- **Agent-to-agent communication** — downstream agents can parse the report
  programmatically to decide next steps.
- **Auditing and dashboards** — tooling can aggregate pipeline results across runs.

The Markdown report remains the **primary** format for human review. The JSON
contract is supplementary and **not mandatory yet**.

## Schema

The JSON report schema is located at:

```
schema/dev-pipeline-report.schema.json
```

It uses JSON Schema draft-07. The schema defines all fields produced by the
pipeline including pipeline mode, gate status, role performance, task
classification, intake quality, work orders, verification evidence, diff summary,
Codex review results, final decision, and safety flags.

## Sample

A realistic sample JSON report (S-level task, accepted, no Codex review needed)
is located at:

```
examples/dev-pipeline-report.sample.json
```

This sample can be used to:

- Understand the expected structure and field values.
- Test policy-check tooling against a known-good report.
- Seed integration tests for consumers of the report.

## Skill Trace and Evidence

The report includes a `skill_trace` object and a human-readable `Skill Trace`
table in the Markdown report.

The trace discloses:

- Hermes entry skill and active phase;
- planned, used, and skipped Hermes/gstack skills;
- ClaudeCode Matt skills required and reported;
- Codex plan/diff review gates used or skipped;
- policy-check and doctor/ci-local usage;
- missing evidence and acceptance impact.

ClaudeCode Matt skill evidence must match the required skill. `tdd` requires
RED/GREEN evidence and validation exit codes. `diagnose` requires hypothesis,
test, finding, and a fix recommendation or applied fix. `prototype`,
`to-issues`, and `grill-me` have their own evidence fields in the schemas and
templates.

If required Matt skill evidence is missing, Hermes must not mark verification as
PASS. If acceptance is complete while required Matt skill evidence is missing,
`scripts/policy-check.sh` fails run-state validation.

This is a disclosure and evidence contract. It does not prove hidden runtime
invocation unless Hermes or ClaudeCode expose machine-readable runtime traces.

## 中文阶段播报与技能使用证据

`skill_trace` also carries Chinese display fields for user-facing narration:

- `display_language`: usually `zh-CN`;
- `current_phase_label`: Chinese phase label, such as `方案设计与计划编写` or `Hermes 验证`;
- `current_phase_internal`: internal phase key for machine trace;
- `user_visible_skill_banner`: whether Hermes showed the active workflow banner;
- `clarification_trace`: why blocking questions were asked and what stage follows.

If `display_language` is `zh-CN`, `current_phase_label` is required by policy-check. If clarification questions exist, `clarification_trace.why_questions_are_needed` is required.

The Markdown report must include a Chinese `技能使用证据` table explaining which Hermes/gstack skills, ClaudeCode Matt skills, Codex gates, and local validation tools were planned, used, skipped, and evidenced.

## How policy-check can validate reports

A policy-check script or CI step can validate any pipeline report by:

1. **Schema validation** — Parse the JSON and validate against
   `schema/dev-pipeline-report.schema.json` using any JSON Schema validator
   (e.g. `ajv`, `jsonschema` in Python, `check-jsonschema` CLI).

2. **Invariant checks** — Enforce project-specific rules:
   - `verification_complete` must be `true` before merge.
   - `safety.safe_to_push_pr` must be `true` for PR creation.
   - `codex_verdict` must not be `FAIL` (if Codex review was enabled).
   - `final_decision` must be `ACCEPTED` for the work to be merged.

3. **Report location** — The JSON report is written alongside the Markdown
   report in the pipeline output directory.

Example validation with `check-jsonschema`:

```bash
pip install check-jsonschema
check-jsonschema --schemafile schema/dev-pipeline-report.schema.json examples/dev-pipeline-report.sample.json
```

Example validation with Python:

```python
import json, jsonschema

with open("schema/dev-pipeline-report.schema.json") as f:
    schema = json.load(f)
with open("examples/dev-pipeline-report.sample.json") as f:
    report = json.load(f)

jsonschema.validate(report, schema)
```

## Not mandatory yet

The JSON contract is introduced in v0.2 as an opt-in enhancement. Existing
workflows that rely on the Markdown report are unaffected. The Markdown report
remains the primary deliverable and will continue to be generated regardless of
whether the JSON report is present.
