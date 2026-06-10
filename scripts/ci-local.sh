#!/usr/bin/env bash
# ci-local.sh — Local aggregate validation for hermes-dev-pipeline-kit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

section() {
  echo ""
  echo "== $1 =="
}

expect_fail() {
  local label="$1"
  shift

  if "$@"; then
    echo "FAIL: $label should fail"
    exit 1
  fi

  echo "PASS: $label failed as expected"
}

json_check() {
  local file="$1"
  python3 -m json.tool "$file" >/dev/null
  echo "PASS: JSON parse $file"
}

security_scan() {
  local secret_raw secret_hits personal_raw personal_hits bad_files
  local secret_pattern secret_assignment_pattern
  local key_material_pattern
  local user_name account_name project_name upstream_owner upstream_repo numeric_id
  local personal_pattern

  section "Safety scan"

  key_material_pattern="ssh""-rsa|BEGIN .*K""EY"
  secret_pattern="API""_KEY|SEC""RET|TOK""EN|PASS""WORD|PRIVATE""_KEY|OPEN""AI|ANTH""ROPIC|GH""_TO""KEN|${key_material_pattern}"
  secret_assignment_pattern="(API""_KEY|SEC""RET|TOK""EN|PASS""WORD|PRIVATE""_KEY|OPEN""AI|ANTH""ROPIC|GH""_TO""KEN)[[:space:]]*[:=]|${key_material_pattern}"

  secret_raw=$(grep -RInE \
    "$secret_pattern" \
    "$REPO_ROOT" --exclude-dir=.git --exclude="policy-check.sh" --exclude="ci-local.sh" 2>/dev/null || true)

  # Broad policy text names sensitive categories by design. Fail only
  # assignment-like values, private keys, or SSH public keys.
  secret_hits=$(printf "%s\n" "$secret_raw" \
    | grep -E "$secret_assignment_pattern" \
    | grep -vE "scripts/(policy-check|ci-local)\\.sh:" || true)

  if [[ -n "$secret_hits" ]]; then
    echo "FAIL: secret-like assignment or key material found"
    echo "$secret_hits"
    exit 1
  fi
  echo "PASS: no secret assignments or key material found"

  user_name="song""shiyao"
  account_name="pangli""haoshuai"
  project_name="resume""forcm"
  upstream_owner="JOY""CEQL"
  upstream_repo="magic""-resume"
  numeric_id="106""2250152"
  personal_pattern="\\/Users\\/${user_name}|${user_name}|${numeric_id}|${account_name}|${project_name}|${upstream_owner}|${upstream_repo}"

  personal_raw=$(grep -RInE \
    "$personal_pattern" \
    "$REPO_ROOT" --exclude-dir=.git --exclude="policy-check.sh" --exclude="ci-local.sh" 2>/dev/null || true)

  personal_hits=$(printf "%s\n" "$personal_raw" \
    | grep -vE "scripts/(policy-check|ci-local)\\.sh:" || true)

  if [[ -n "$personal_hits" ]]; then
    echo "FAIL: personal or business-project reference found"
    echo "$personal_hits"
    exit 1
  fi
  echo "PASS: no personal or business-project references found"

  bad_files=$(find "$REPO_ROOT" -not -path "*/.git/*" \
    \( -name "*.bak*" -o -name "*backup*" -o -name ".env" -o -name "*.log" \) 2>/dev/null || true)

  if [[ -n "$bad_files" ]]; then
    echo "FAIL: backup/env/log files found"
    echo "$bad_files"
    exit 1
  fi
  echo "PASS: no backup/env/log files found"
}

main() {
  cd "$REPO_ROOT"

  section "Bash syntax"
  bash -n scripts/*.sh
  bash -n scripts/smoke/*.sh
  echo "PASS: bash syntax"

  section "Manifest"
  bash scripts/check-manifest.sh

  section "Policy positive fixtures"
  bash scripts/policy-check.sh --run-state examples/run-state.sample.json
  bash scripts/policy-check.sh --report examples/dev-pipeline-report.sample.json
  bash scripts/policy-check.sh --run-state examples/policy/good-generated-file-with-evidence.json
  bash scripts/policy-check.sh --run-state examples/policy/good-skill-trace.json
  bash scripts/policy-check.sh --run-state examples/policy/good-chinese-skill-trace.json
  bash scripts/policy-check.sh --run-state examples/policy/good-owner-summary.json
  bash scripts/policy-check.sh --run-state examples/policy/good-compact-s-report.json
  bash scripts/policy-check.sh --run-state examples/policy/good-compact-structured-report.json
  bash scripts/policy-check.sh --run-state examples/policy/good-full-l-report.json
  bash scripts/policy-check.sh --run-state examples/policy/good-m-standard-with-claudecode.json
  bash scripts/policy-check.sh --run-state examples/policy/good-l-full-report.json
  bash scripts/policy-check.sh --run-state examples/policy/good-codex-deferred-partial.json
  bash scripts/policy-check.sh --run-state examples/policy/good-tdd-red-green-evidence.json
  bash scripts/policy-check.sh --run-state examples/policy/good-generated-run-state-with-provenance.json
  bash scripts/policy-check.sh --run-state examples/policy/good-tdd-command-log-red-green.json
  bash scripts/policy-check.sh --run-state examples/policy/good-v04-generated-run-state.json

  section "Policy negative fixtures"
  expect_fail "bad-forbidden-file" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-forbidden-file.json
  expect_fail "bad-acceptance-without-codex" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-acceptance-without-codex.json
  expect_fail "bad-generated-file" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-generated-file.json
  expect_fail "bad-missing-matt-skill-evidence" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-missing-matt-skill-evidence.json
  expect_fail "bad-missing-chinese-phase-label" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-missing-chinese-phase-label.json
  expect_fail "bad-missing-approval-inbox" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-missing-approval-inbox.json
  expect_fail "bad-l-compact-report" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-l-compact-report.json
  expect_fail "bad-failure-without-responsibility" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-failure-without-responsibility.json
  expect_fail "bad-compact-checklist-only" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-compact-checklist-only.json
  expect_fail "bad-ml-downgraded-to-s" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-ml-downgraded-to-s.json
  expect_fail "bad-missing-claudecode-for-ml" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-missing-claudecode-for-ml.json
  expect_fail "bad-full-report-missing-sections" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-full-report-missing-sections.json
  expect_fail "bad-verification-without-exit-code" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-verification-without-exit-code.json
  expect_fail "bad-acceptance-complete-with-missing-matt-evidence" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-acceptance-complete-with-missing-matt-evidence.json
  expect_fail "bad-self-improvement-side-effect" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-self-improvement-side-effect.json
  expect_fail "bad-synthetic-run-state-without-provenance" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-synthetic-run-state-without-provenance.json
  expect_fail "bad-claudecode-writes-acceptance" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-claudecode-writes-acceptance.json
  expect_fail "bad-tdd-text-only-no-command-log" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-tdd-text-only-no-command-log.json
  expect_fail "bad-codex-pass-while-deferred" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-codex-pass-while-deferred.json
  expect_fail "bad-event-chain-tampered" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-event-chain-tampered.json
  expect_fail "bad-state-transition-skip" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-state-transition-skip.json
  expect_fail "bad-generated-run-state-without-replay" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-generated-run-state-without-replay.json
  expect_fail "bad-green-before-red" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-green-before-red.json
  expect_fail "bad-final-report-before-policy" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-final-report-before-policy.json
  expect_fail "bad-complete-with-failed-policy" \
    bash scripts/policy-check.sh --run-state examples/policy/bad-complete-with-failed-policy.json

  section "Smoke tests"
  bash scripts/smoke/smoke-small-fix.sh
  bash scripts/smoke/smoke-forbidden-file.sh
  bash scripts/smoke/smoke-codex-required.sh
  bash scripts/smoke/smoke-publish-lane-stop.sh
  bash scripts/smoke/smoke-generated-run-state.sh
  bash scripts/smoke/smoke-installed-evidence-harness.sh
  bash scripts/smoke/smoke-real-task-medium.sh
  bash scripts/smoke/smoke-command-log-append-replay.sh
  bash scripts/smoke/smoke-state-machine-medium.sh
  bash scripts/smoke/smoke-state-machine-tamper.sh
  bash scripts/smoke/smoke-failure-finalization.sh
  bash scripts/smoke/smoke-s-level-driver.sh
  bash scripts/smoke/smoke-s-level-driver-failure.sh

  section "JSON parse"
  json_check schema/run-state.schema.json
  json_check schema/dev-pipeline-report.schema.json
  json_check schema/run-manifest.schema.json
  json_check schema/command-log.schema.json
  json_check schema/claudecode-result.schema.json
  json_check schema/generated-run-state.schema.json
  json_check schema/event.schema.json
  json_check schema/state.schema.json
  json_check schema/state-machine.schema.json
  json_check schema/replay-result.schema.json
  json_check schema/artifact-manifest.schema.json
  json_check examples/run-state.sample.json
  json_check examples/dev-pipeline-report.sample.json
  for f in examples/policy/*.json; do
    json_check "$f"
  done

  security_scan

  echo ""
  echo "ci-local: PASS"
}

main "$@"
