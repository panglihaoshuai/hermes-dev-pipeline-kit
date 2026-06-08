#!/usr/bin/env bash
set -euo pipefail

#
# hermes-dev-pipeline-kit — install.sh
# Installs dev-pipeline-orchestrator and dev-pipeline-report skills
# into ~/.hermes/skills/software-development/
#

DRY_RUN=0
YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) YES=1 ;;
        *)
            echo "[ERROR] Unknown option: $arg"
            echo "Usage: $0 [--dry-run] [--yes|-y]"
            exit 1
            ;;
    esac
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] No changes will be made."
    echo ""
elif [[ $YES -eq 0 ]]; then
    echo "[INFO] Running without --yes. Showing what would happen, then exiting."
    echo "       Use --yes to actually install, or --dry-run for preview."
    echo ""
    DRY_RUN=1
fi

# Resolve the directory where this script lives (the kit root's scripts/ dir)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HERMES_SKILLS_DIR="$HOME/.hermes/skills"
TARGET_PARENT="$HERMES_SKILLS_DIR/software-development"

SKILL_NAMES=(
    "dev-pipeline-orchestrator"
    "dev-pipeline-report"
)

HARNESS_SCRIPT_NAMES=(
    "append-event.sh"
    "transition-check.sh"
    "replay-run.sh"
    "run-init.sh"
    "record-command.sh"
    "generate-run-state.sh"
    "final-report.sh"
    "policy-check.sh"
)

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
DELEGATION_PROTOCOL_SOURCE="$KIT_ROOT/protocols/claude-delegation-protocol.md"

# --- Functions ---------------------------------------------------------------

timestamp() {
    date +"%Y%m%d-%H%M%S"
}

backup_existing() {
    local ts
    ts="$(timestamp)"
    local backup_dir="$HERMES_SKILLS_DIR/.backup-dev-pipeline-${ts}"

    local found=0
    for skill in "${SKILL_NAMES[@]}"; do
        if [[ -d "$TARGET_PARENT/$skill" ]]; then
            found=1
            break
        fi
    done

    if [[ $found -eq 1 ]]; then
        echo "[backup] Existing dev-pipeline skills found. Moving to: $backup_dir"
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN]   Would create $backup_dir"
        else
            mkdir -p "$backup_dir"
        fi
        for skill in "${SKILL_NAMES[@]}"; do
            if [[ -d "$TARGET_PARENT/$skill" ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    echo "[DRY-RUN]   Would move $TARGET_PARENT/$skill → $backup_dir/"
                else
                    mv "$TARGET_PARENT/$skill" "$backup_dir/"
                    echo "[backup]   Moved: $skill"
                fi
            fi
        done
    fi
}

install_skill() {
    local skill_name="$1"
    local src="$KIT_ROOT/skills/software-development/$skill_name"
    local dst="$TARGET_PARENT/$skill_name"

    if [[ ! -d "$src" ]]; then
        echo "[ERROR] Source skill directory not found: $src"
        echo "        Make sure you are running this script from the kit root or that the kit is complete."
        exit 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would copy $src → $dst"
    else
        mkdir -p "$TARGET_PARENT"
        cp -R "$src" "$dst"
        echo "[install] Copied: $skill_name → $dst"
    fi
}

install_harness_scripts() {
    local bin_dir="$TARGET_PARENT/dev-pipeline-orchestrator/bin"

    echo ""
    echo "--- Installing v0.4 state-machine harness scripts ---"

    for script in "${HARNESS_SCRIPT_NAMES[@]}"; do
        local src="$KIT_ROOT/scripts/$script"
        local dst="$bin_dir/$script"

        if [[ ! -f "$src" ]]; then
            echo "[ERROR] Required harness script not found: $src"
            exit 1
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would copy $src → $dst and chmod +x"
        else
            mkdir -p "$bin_dir"
            cp "$src" "$dst"
            chmod 755 "$dst"
            echo "[install] Copied harness script: $script → $dst"
        fi
    done
}

check_delegation_protocol() {
    echo ""
    echo "--- Checking Delegation Protocol in ~/.claude/CLAUDE.md ---"

    if [[ ! -f "$CLAUDE_MD" ]]; then
        echo "[warn] $CLAUDE_MD does not exist."
        print_delegation_hint
        return
    fi

    if grep -q "Hermes Delegation Protocol" "$CLAUDE_MD" 2>/dev/null; then
        echo "[ok] Delegation protocol already installed."
    else
        echo "[warn] 'Hermes Delegation Protocol' section NOT found in $CLAUDE_MD"
        print_delegation_hint
    fi
}

print_delegation_hint() {
    echo ""
    echo "==================================================================="
    echo "  ACTION REQUIRED (manual):"
    echo "  Append the following section to ~/.claude/CLAUDE.md:"
    echo "==================================================================="
    echo ""

    if [[ -f "$DELEGATION_PROTOCOL_SOURCE" ]]; then
        cat "$DELEGATION_PROTOCOL_SOURCE"
    else
        echo "  [!] Source file not found: $DELEGATION_PROTOCOL_SOURCE"
        echo "  [!] Please copy the Hermes Delegation Protocol manually."
    fi

    echo ""
    echo "==================================================================="
    echo ""
}

# --- Main --------------------------------------------------------------------

echo "========================================"
echo " hermes-dev-pipeline-kit installer"
echo "========================================"
echo ""

# 1. Ensure ~/.hermes/skills exists
if [[ ! -d "$HERMES_SKILLS_DIR" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would create $HERMES_SKILLS_DIR"
    else
        mkdir -p "$HERMES_SKILLS_DIR"
        echo "[setup] Created $HERMES_SKILLS_DIR"
    fi
else
    echo "[ok] $HERMES_SKILLS_DIR exists."
fi

# 2. Backup any existing dev-pipeline skills
backup_existing

# 3. Install skills
echo ""
echo "--- Installing skills ---"
for skill in "${SKILL_NAMES[@]}"; do
    install_skill "$skill"
done
install_harness_scripts

# 4. Check delegation protocol
check_delegation_protocol

# 5. Summary
echo ""
echo "========================================"
echo " Installation Summary"
echo "========================================"
echo ""
echo "Skills installed to: $TARGET_PARENT/"
for skill in "${SKILL_NAMES[@]}"; do
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] $skill (would be installed)"
    elif [[ -d "$TARGET_PARENT/$skill" ]]; then
        echo "  [ok] $skill"
    else
        echo "  [--] $skill (dry-run mode)"
    fi
done
if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] v0.4 state-machine harness scripts (would be installed to dev-pipeline-orchestrator/bin)"
else
    echo "  [ok] v0.4 state-machine harness scripts"
fi
echo ""
echo "No global dependencies were installed."
echo "No secrets were written."
echo ""
echo "Done."
