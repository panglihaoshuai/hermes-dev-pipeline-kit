#!/usr/bin/env bash
# smoke-small-fix.sh — S-level task, Codex optional, evidence present, acceptance allowed.
# Expected: policy-check PASS on all run-state rules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_CHECK="$SCRIPT_DIR/../policy-check.sh"
TMPFILE=$(mktemp /tmp/smoke-small-fix-XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" <<'EOF'
{
  "run_id": "smoke-small-fix",
  "project": "smoke-test",
  "mode": "auto_run",
  "current_gate": "Gate 9",
  "classification": {
    "scale": "S",
    "reasons": ["Small fix"],
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
    "complete": true,
    "final_decision": "ACCEPTED"
  },
  "owner_summary": {
    "task": "S-level small fix smoke",
    "status_color": "green",
    "current_stage_label": "Hermes 验证",
    "progress": {
      "intake": "complete",
      "planning": "complete",
      "work_order_split": "complete",
      "execution": "complete",
      "verification": "complete",
      "codex_review": "not_required",
      "approval": "not_required"
    },
    "largest_risk": "无阻塞风险。",
    "needs_user_decision": false,
    "next_action": "自动继续或停止。"
  },
  "stage_updates": [
    {
      "from": "ClaudeCode 工单执行",
      "to": "Hermes 验证",
      "tools_or_skills": ["dev-pipeline-orchestrator", "policy-check.sh"],
      "goal": "验证 S-level 小修",
      "next_gate_condition": "policy-check PASS",
      "needs_user_decision": false
    }
  ],
  "responsibility_trace": [
    {
      "item": "测试验证",
      "owner": "Hermes",
      "status": "complete",
      "evidence": "npm test exit code 0",
      "blocking": false
    }
  ],
  "approval_inbox": [],
  "skill_trace": {
    "display_language": "zh-CN",
    "current_phase_label": "Hermes 验证",
    "current_phase_internal": "verification",
    "user_visible_skill_banner": true,
    "entry_skill": "dev-pipeline-orchestrator",
    "mode": "auto_run",
    "phase": "verification",
    "hermes_skills": [
      {
        "name": "gstack plan-eng-review",
        "planned": false,
        "used": false,
        "evidence": "",
        "verdict": "SKIPPED",
        "skipped_reason": "S-level smoke fixture does not require gstack plan review."
      }
    ],
    "claudecode_skills": [],
    "codex_gates": [
      {
        "name": "diff review",
        "required": false,
        "used": false,
        "verdict": "SKIPPED"
      }
    ],
    "policy_check": {
      "planned": true,
      "used": true,
      "exit_code": 0
    },
    "missing_evidence": [],
    "acceptance_impact": "none"
  },
  "approval_gates": {
    "commit_approved": true,
    "push_approved": false,
    "pr_approved": false,
    "repo_create_approved": false
  },
  "baseline_debt": [],
  "follow_up_backlog": []
}
EOF

PASS=true

# policy-check.sh must exit 0 for a clean S-level run-state
if "$POLICY_CHECK" --run-state "$TMPFILE"; then
  echo "PASS: policy-check exited 0 for S-level small fix"
else
  echo "FAIL: policy-check exited non-zero for S-level small fix"
  PASS=false
fi

if $PASS; then
  echo ""
  echo "=== smoke-small-fix: ALL CHECKS PASSED ==="
  exit 0
else
  echo ""
  echo "=== smoke-small-fix: FAILED ==="
  exit 1
fi
