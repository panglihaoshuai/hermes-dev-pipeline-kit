#!/usr/bin/env bash
# smoke-publish-lane-stop.sh — publish requested, no push approval => pipeline correctly stopped.
# Expected: policy-check PASS (the run-state has no rule violations; the stop is correct behavior).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_CHECK="$SCRIPT_DIR/../policy-check.sh"
TMPFILE=$(mktemp /tmp/smoke-publish-XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" <<'EOF'
{
  "run_id": "smoke-publish-lane-stop",
  "project": "smoke-test",
  "mode": "auto_run",
  "current_gate": "Gate 9.5",
  "classification": {
    "scale": "S",
    "reasons": ["Publish lane stop test"],
    "risk_level": "low"
  },
  "work_orders": [
    {
      "id": "wo-smoke",
      "owner": "hermes",
      "required_skill": "hermes-dev-pipeline-kit",
      "status": "completed",
      "files": ["src/foo.ts"],
      "retries": 0
    }
  ],
  "allowed_files": ["src/foo.ts"],
  "forbidden_files": [".env"],
  "modified_files": ["src/foo.ts"],
  "command_evidence": [
    {
      "command": "npm test",
      "exit_code": 0,
      "key_output": "All tests passed",
      "pass_fail": "PASS"
    }
  ],
  "codex": {
    "plan_review_verdict": "NOT_REQUIRED",
    "diff_review_verdict": "NOT_REQUIRED",
    "disabled_by_user": false
  },
  "verification": {
    "git_diff_name_status": "M\tsrc/foo.ts",
    "git_diff_check_exit": 0,
    "tests_pass": true,
    "typecheck_exit": 0
  },
  "acceptance": {
    "complete": false,
    "final_decision": "PENDING"
  },
  "approval_gates": {
    "commit_approved": false,
    "push_approved": false,
    "pr_approved": false,
    "repo_create_approved": false
  },
  "publish_requested": true,
  "stopped_reason": "publish approval required",
  "baseline_debt": [],
  "follow_up_backlog": []
}
EOF

PASS=true

# policy-check.sh must exit 0 — no rule violations, pipeline correctly held at gate
if "$POLICY_CHECK" --run-state "$TMPFILE"; then
  echo "PASS: policy-check exited 0 (publish lane correctly stopped, no rule violations)"
else
  echo "FAIL: policy-check exited non-zero unexpectedly"
  PASS=false
fi

if $PASS; then
  echo ""
  echo "=== smoke-publish-lane-stop: ALL CHECKS PASSED ==="
  exit 0
else
  echo ""
  echo "=== smoke-publish-lane-stop: FAILED ==="
  exit 1
fi
