#!/usr/bin/env bash
set -euo pipefail

#
# hermes-dev-pipeline-kit — doctor.sh
# Health-check for installed dev-pipeline-kit components.
# Returns: 0 if PASS or PARTIAL, 1 if FAIL.
#

HERMES_SKILLS_DIR="$HOME/.hermes/skills"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

core_pass=0
core_fail=0
opt_pass=0
opt_missing=0

# --- Helper ------------------------------------------------------------------

check_core() {
    local label="$1"
    local path="$2"
    if [[ -f "$path" ]]; then
        echo "  PASS  $label"
        core_pass=$((core_pass + 1))
    else
        echo "  FAIL  $label"
        echo "        ($path — not found)"
        core_fail=$((core_fail + 1))
    fi
}

check_optional() {
    local label="$1"
    local path="$2"
    if [[ -e "$path" ]]; then
        echo "  [ok]    $label"
        opt_pass=$((opt_pass + 1))
    else
        echo "  [--]    $label (not found)"
        opt_missing=$((opt_missing + 1))
    fi
}

check_core_executable() {
    local label="$1"
    local path="$2"
    if [[ -f "$path" && -x "$path" ]]; then
        echo "  PASS  $label"
        core_pass=$((core_pass + 1))
    else
        echo "  FAIL  $label"
        echo "        ($path — not found or not executable)"
        core_fail=$((core_fail + 1))
    fi
}

check_core_dir() {
    local label="$1"
    local path="$2"
    if [[ -d "$path" ]]; then
        echo "  PASS  $label"
        core_pass=$((core_pass + 1))
    else
        echo "  FAIL  $label"
        echo "        ($path — directory not found)"
        core_fail=$((core_fail + 1))
    fi
}

# --- Header ------------------------------------------------------------------

echo "========================================"
echo " hermes-dev-pipeline-kit doctor"
echo "========================================"
echo ""

# --- Core file checks (from kit source if available, else installed) ----------

echo "--- Core Skill Files ---"

if [[ -d "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator" ]]; then
    INSTALLED_ORCHESTRATOR="$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator"
    check_core \
        "dev-pipeline-orchestrator SKILL.md" \
        "$INSTALLED_ORCHESTRATOR/SKILL.md"
    check_core \
        "dev-pipeline-report SKILL.md" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-report/SKILL.md"
    check_core \
        "claudecode-work-order.md template" \
        "$INSTALLED_ORCHESTRATOR/templates/claudecode-work-order.md"
    check_core \
        "codex-plan-review.md template" \
        "$INSTALLED_ORCHESTRATOR/templates/codex-plan-review.md"
    check_core \
        "codex-diff-review.md template" \
        "$INSTALLED_ORCHESTRATOR/templates/codex-diff-review.md"
    check_core \
        "hermes-verification-report.md template" \
        "$INSTALLED_ORCHESTRATOR/templates/hermes-verification-report.md"
    check_core \
        "final-evidence-report.md template" \
        "$INSTALLED_ORCHESTRATOR/templates/final-evidence-report.md"
    check_core_executable \
        "installed append-event.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/append-event.sh"
    check_core_executable \
        "installed transition-check.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/transition-check.sh"
    check_core_executable \
        "installed replay-run.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/replay-run.sh"
    check_core_executable \
        "installed run-init.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/run-init.sh"
    check_core_executable \
        "installed record-command.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/record-command.sh"
    check_core_executable \
        "installed drive-s-run.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/drive-s-run.sh"
    check_core_executable \
        "installed generate-run-state.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/generate-run-state.sh"
    check_core_executable \
        "installed final-report.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/final-report.sh"
    check_core_executable \
        "installed policy-check.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/policy-check.sh"
    check_core_executable \
        "installed fail-run.sh" \
        "$INSTALLED_ORCHESTRATOR/bin/fail-run.sh"
else
    # Not installed yet — check kit source files instead
    echo "  [info] Skills not yet installed. Checking kit source files..."
    check_core "orchestrator SKILL.md (source)" "$KIT_ROOT/skills/software-development/dev-pipeline-orchestrator/SKILL.md"
    check_core "report SKILL.md (source)" "$KIT_ROOT/skills/software-development/dev-pipeline-report/SKILL.md"
    check_core "claudecode-work-order.md (source)" "$KIT_ROOT/skills/software-development/dev-pipeline-orchestrator/templates/claudecode-work-order.md"
fi

echo ""
echo "--- Kit Bootstrap Files ---"

check_core "BOOTSTRAP.md" "$KIT_ROOT/BOOTSTRAP.md"
check_core "manifest.yaml" "$KIT_ROOT/manifest.yaml"
check_core "README.md" "$KIT_ROOT/README.md"
check_core "AGENTS.md" "$KIT_ROOT/AGENTS.md"
check_core "CLAUDE.md" "$KIT_ROOT/CLAUDE.md"
check_core "plugin wrapper manifest (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/plugin.yaml"
check_core "plugin wrapper __init__.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/__init__.py"
check_core "plugin wrapper schemas.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/schemas.py"
check_core "plugin wrapper tools.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/tools.py"
check_core "plugin wrapper wrappers.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/wrappers.py"
check_core "plugin wrapper hooks.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/hooks.py"
check_core "plugin wrapper redaction.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/redaction.py"
check_core "plugin wrapper integrations/__init__.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/integrations/__init__.py"
check_core "plugin wrapper integrations/capability.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/integrations/capability.py"
check_core "plugin wrapper integrations/dynamic_workflows.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/integrations/dynamic_workflows.py"
check_core "plugin wrapper integrations/agentguard.py (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/integrations/agentguard.py"
check_core "plugin wrapper README.md (source)" "$KIT_ROOT/plugins/hermes-evidence-runtime/README.md"
check_core "install.sh" "$KIT_ROOT/scripts/install.sh"
check_core "uninstall.sh" "$KIT_ROOT/scripts/uninstall.sh"
check_core "install-deps.sh" "$KIT_ROOT/scripts/install-deps.sh"
check_core "doctor.sh" "$KIT_ROOT/scripts/doctor.sh"
check_core "ci-local.sh" "$KIT_ROOT/scripts/ci-local.sh"
check_core "append-event.sh" "$KIT_ROOT/scripts/append-event.sh"
check_core "transition-check.sh" "$KIT_ROOT/scripts/transition-check.sh"
check_core "replay-run.sh" "$KIT_ROOT/scripts/replay-run.sh"
check_core "run-init.sh" "$KIT_ROOT/scripts/run-init.sh"
check_core "record-command.sh" "$KIT_ROOT/scripts/record-command.sh"
check_core "drive-s-run.sh" "$KIT_ROOT/scripts/drive-s-run.sh"
    check_core "generate-run-state.sh" "$KIT_ROOT/scripts/generate-run-state.sh"
    check_core "final-report.sh" "$KIT_ROOT/scripts/final-report.sh"
    check_core "fail-run.sh" "$KIT_ROOT/scripts/fail-run.sh"
    check_core "validate-worker-result.sh" "$KIT_ROOT/scripts/validate-worker-result.sh"
    check_core "record-worker-result.sh" "$KIT_ROOT/scripts/record-worker-result.sh"
    check_core "normalize-worker-result.sh" "$KIT_ROOT/scripts/normalize-worker-result.sh"
    check_core "invoke-worker-dry-run.sh" "$KIT_ROOT/scripts/invoke-worker-dry-run.sh"
    check_core "simulate-worker-output.sh" "$KIT_ROOT/scripts/simulate-worker-output.sh"
    check_core "smoke-generated-run-state.sh" "$KIT_ROOT/scripts/smoke/smoke-generated-run-state.sh"
check_core "smoke-failure-finalization.sh" "$KIT_ROOT/scripts/smoke/smoke-failure-finalization.sh"
check_core "smoke-state-machine-medium.sh" "$KIT_ROOT/scripts/smoke/smoke-state-machine-medium.sh"
check_core "smoke-state-machine-tamper.sh" "$KIT_ROOT/scripts/smoke/smoke-state-machine-tamper.sh"
check_core "smoke-plugin-wrapper.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-wrapper.sh"
check_core "smoke-plugin-discovery-temp-home.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-discovery-temp-home.sh"
    check_core "smoke-plugin-hooks-source.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-source.sh"
    check_core "smoke-plugin-hooks-discovery-temp-home.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-discovery-temp-home.sh"
    check_core "smoke-plugin-hooks-v07-unit.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-v07-unit.sh"
    check_core "smoke-plugin-hooks-v07-simulated.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-v07-simulated.sh"
    check_core "smoke-plugin-hooks-v07-real-runtime.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-v07-real-runtime.sh"
    check_core "smoke-plugin-hooks-v07-non-mutation.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-v07-non-mutation.sh"
    check_core "smoke-plugin-hooks-v07-secret-canary.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-hooks-v07-secret-canary.sh"
    check_core "smoke-plugin-v08-c-dry-run.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-v08-c-dry-run.sh"
    check_core "smoke-plugin-v09-integration-backends.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-v09-integration-backends.sh"
    check_core "smoke-plugin-v09-agentguard-native.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-v09-agentguard-native.sh"
    check_core "smoke-plugin-v09-dynamic-real-child.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-v09-dynamic-real-child.sh"
    check_core "smoke-plugin-v09-combined-real-backends.sh" "$KIT_ROOT/scripts/smoke/smoke-plugin-v09-combined-real-backends.sh"
    check_core "smoke-worker-result-contract.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-result-contract.sh"
    check_core "smoke-worker-result-invalid-acceptance.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-result-invalid-acceptance.sh"
    check_core "smoke-worker-normalizer.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-normalizer.sh"
    check_core "smoke-worker-normalizer-to-run-state.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-normalizer-to-run-state.sh"
    check_core "smoke-worker-dry-run-disabled.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-dry-run-disabled.sh"
    check_core "smoke-worker-dry-run-to-run-state.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-dry-run-to-run-state.sh"
    check_core "smoke-worker-dry-run-real-optional.sh" "$KIT_ROOT/scripts/smoke/smoke-worker-dry-run-real-optional.sh"
check_core "run-manifest.schema.json" "$KIT_ROOT/schema/run-manifest.schema.json"
check_core "command-log.schema.json" "$KIT_ROOT/schema/command-log.schema.json"
check_core "claudecode-result.schema.json" "$KIT_ROOT/schema/claudecode-result.schema.json"
check_core "generated-run-state.schema.json" "$KIT_ROOT/schema/generated-run-state.schema.json"
check_core "event.schema.json" "$KIT_ROOT/schema/event.schema.json"
check_core "state.schema.json" "$KIT_ROOT/schema/state.schema.json"
check_core "state-machine.schema.json" "$KIT_ROOT/schema/state-machine.schema.json"
check_core "replay-result.schema.json" "$KIT_ROOT/schema/replay-result.schema.json"
    check_core "artifact-manifest.schema.json" "$KIT_ROOT/schema/artifact-manifest.schema.json"
    check_core "worker-result.schema.json" "$KIT_ROOT/schema/worker-result.schema.json"
    check_core "hook-event.schema.json" "$KIT_ROOT/schema/hook-event.schema.json"
    check_core "approval-inbox.schema.json" "$KIT_ROOT/schema/approval-inbox.schema.json"
    check_core "orchestration-backend-result.schema.json" "$KIT_ROOT/schema/orchestration-backend-result.schema.json"
    check_core "security-backend-decision.schema.json" "$KIT_ROOT/schema/security-backend-decision.schema.json"
    check_core_dir "examples/worker-results directory" "$KIT_ROOT/examples/worker-results"
    check_core "protocols/claude-delegation-protocol.md" "$KIT_ROOT/protocols/claude-delegation-protocol.md"
check_core "docs/agent-install.md" "$KIT_ROOT/docs/agent-install.md"

echo ""
echo "--- Delegation Protocol in ~/.claude/CLAUDE.md ---"

delegation_ok=0
if [[ -f "$CLAUDE_MD" ]]; then
    if grep -q "Hermes Delegation Protocol" "$CLAUDE_MD" 2>/dev/null; then
        echo "  PASS  Hermes Delegation Protocol"
        core_pass=$((core_pass + 1))
        delegation_ok=1
    else
        echo "  WARN  Hermes Delegation Protocol (not found in $CLAUDE_MD)"
        echo "        Run: bash scripts/install.sh --yes, then manually append the protocol."
        core_fail=$((core_fail + 1))
    fi
else
    echo "  WARN  $CLAUDE_MD does not exist"
    echo "        Create it and append the Hermes Delegation Protocol from protocols/claude-delegation-protocol.md"
    core_fail=$((core_fail + 1))
fi

echo ""
echo "--- Content Checks (installed SKILL.md files) ---"

SEARCH_TARGETS=()
if [[ -f "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/SKILL.md" ]]; then
    SEARCH_TARGETS+=("$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/SKILL.md")
    SEARCH_TARGETS+=("$HERMES_SKILLS_DIR/software-development/dev-pipeline-report/SKILL.md")
else
    SEARCH_TARGETS+=("$KIT_ROOT/skills/software-development/dev-pipeline-orchestrator/SKILL.md")
    SEARCH_TARGETS+=("$KIT_ROOT/skills/software-development/dev-pipeline-report/SKILL.md")
fi

CONTENT_CHECKS=(
    "auto_run"
    "Simple Prompt Intake Protocol"
    "GitHub Publish"
    "Completion Boundary Policy"
    "Codex Default Permission"
)

for pattern in "${CONTENT_CHECKS[@]}"; do
    found=0
    for f in "${SEARCH_TARGETS[@]}"; do
        if [[ -f "$f" ]] && grep -qi "$pattern" "$f" 2>/dev/null; then
            found=1
            break
        fi
    done

    if [[ $found -eq 1 ]]; then
        echo "  PASS  $pattern"
        core_pass=$((core_pass + 1))
    else
        echo "  FAIL  $pattern (not found in SKILL.md files)"
        core_fail=$((core_fail + 1))
    fi
done

# --- Optional dependency checks ----------------------------------------------

echo ""
echo "--- Optional Dependencies ---"

if command -v gh &>/dev/null; then
    echo "  [ok]    gh (GitHub CLI): $(command -v gh)"
    opt_pass=$((opt_pass + 1))
else
    echo "  [--]    gh (GitHub CLI): not found (optional, for GitHub Publish Lane)"
    opt_missing=$((opt_missing + 1))
fi

GSTACK_FOUND=0
for d in "$HOME/.hermes/skills/gstack" "$HOME/.hermes/profiles/default/skills/gstack"; do
    if [[ -d "$d" ]]; then
        echo "  [ok]    gstack: $d"
        opt_pass=$((opt_pass + 1))
        GSTACK_FOUND=1
        break
    fi
done
if [[ $GSTACK_FOUND -eq 0 ]]; then
    echo "  [--]    gstack: not found (recommended, for plan-eng-review/investigate/ship)"
    echo "          Source: https://github.com/garrytan/gstack"
    opt_missing=$((opt_missing + 1))
fi

MATT_FOUND=0
for d in "$HOME/.claude/skills" "$HOME/.claude/commands"; do
    if [[ -d "$d" ]] && ls "$d"/*tdd* "$d"/*diagnose* 2>/dev/null | head -1 | grep -q . 2>/dev/null; then
        echo "  [ok]    Matt Pocock skills: $d"
        opt_pass=$((opt_pass + 1))
        MATT_FOUND=1
        break
    fi
done
if [[ $MATT_FOUND -eq 0 ]]; then
    echo "  [--]    Matt Pocock skills: not found (recommended, for tdd/diagnose/prototype)"
    echo "          Source: https://github.com/mattpocock/skills"
    opt_missing=$((opt_missing + 1))
fi

# --- Missing Tooling Report --------------------------------------------------

if [[ $opt_missing -gt 0 ]]; then
    echo ""
    echo "--- Missing Tooling Report ---"
    echo "  $opt_missing optional dependency(ies) not found."
    echo "  Core pipeline will work. Run 'bash scripts/install-deps.sh' for details."
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "========================================"
echo " Results"
echo "========================================"
echo ""

total_core=$((core_pass + core_fail))
echo "  Core:     $core_pass / $total_core pass"
echo "  Optional: $opt_pass found, $opt_missing missing"
echo ""

if [[ $core_fail -eq 0 && $opt_missing -eq 0 ]]; then
    echo "  Overall: PASS"
    echo ""
    exit 0
elif [[ $core_fail -eq 0 && $opt_missing -gt 0 ]]; then
    echo "  Overall: PARTIAL"
    echo "  Core installation OK. Optional dependencies missing."
    echo ""
    exit 0
elif [[ $core_fail -eq 1 && $delegation_ok -eq 0 ]]; then
    # Only delegation protocol is missing — core skills are installed
    echo "  Overall: PARTIAL"
    echo "  Core skills installed. Delegation protocol needs manual append to ~/.claude/CLAUDE.md."
    echo ""
    exit 0
else
    echo "  Overall: FAIL"
    echo "  $core_fail core check(s) failed. Run 'bash scripts/install.sh --yes' to fix."
    echo ""
    exit 1
fi
