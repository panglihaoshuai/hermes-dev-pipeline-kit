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

# --- Header ------------------------------------------------------------------

echo "========================================"
echo " hermes-dev-pipeline-kit doctor"
echo "========================================"
echo ""

# --- Core file checks (from kit source if available, else installed) ----------

echo "--- Core Skill Files ---"

if [[ -d "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator" ]]; then
    check_core \
        "dev-pipeline-orchestrator SKILL.md" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/SKILL.md"
    check_core \
        "dev-pipeline-report SKILL.md" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-report/SKILL.md"
    check_core \
        "claudecode-work-order.md template" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/templates/claudecode-work-order.md"
    check_core \
        "codex-plan-review.md template" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/templates/codex-plan-review.md"
    check_core \
        "codex-diff-review.md template" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/templates/codex-diff-review.md"
    check_core \
        "hermes-verification-report.md template" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/templates/hermes-verification-report.md"
    check_core \
        "final-evidence-report.md template" \
        "$HERMES_SKILLS_DIR/software-development/dev-pipeline-orchestrator/templates/final-evidence-report.md"
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
check_core "install.sh" "$KIT_ROOT/scripts/install.sh"
check_core "uninstall.sh" "$KIT_ROOT/scripts/uninstall.sh"
check_core "install-deps.sh" "$KIT_ROOT/scripts/install-deps.sh"
check_core "doctor.sh" "$KIT_ROOT/scripts/doctor.sh"
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
