#!/usr/bin/env bash
set -euo pipefail

#
# hermes-dev-pipeline-kit — uninstall.sh
# Removes dev-pipeline-orchestrator and dev-pipeline-report skills
# from ~/.hermes/skills/software-development/
#

DRY_RUN=0
AUTO_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --yes|-y)
            AUTO_YES=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--dry-run] [--yes|-y]" >&2
            exit 1
            ;;
    esac
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] No changes will be made."
    echo ""
fi

TARGET_PARENT="$HOME/.hermes/skills/software-development"

SKILL_NAMES=(
    "dev-pipeline-orchestrator"
    "dev-pipeline-report"
)

echo "========================================"
echo " hermes-dev-pipeline-kit uninstaller"
echo "========================================"
echo ""

removed=0
skipped=0

# Collect what will be removed
declare -a TO_REMOVE=()
for skill in "${SKILL_NAMES[@]}"; do
    target="$TARGET_PARENT/$skill"
    if [[ -d "$target" ]]; then
        TO_REMOVE+=("$target")
        echo "[found] $target"
        ((removed++))
    else
        echo "[skip] Not found: $target"
        ((skipped++))
    fi
done

echo ""

# If nothing to remove, just report and exit
if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    echo "Nothing to remove. All skills already absent."
    echo "Done."
    exit 0
fi

# Dry-run: show what would be removed, do NOT delete, do NOT ask
if [[ $DRY_RUN -eq 1 ]]; then
    echo "========================================"
    echo " Dry-Run Summary"
    echo "========================================"
    echo ""
    for target in "${TO_REMOVE[@]}"; do
        echo "  Would remove: $target"
    done
    echo ""
    echo "Would remove: ${#TO_REMOVE[@]} skill(s)"
    echo "Skipped: $skipped skill(s) (not found)"
    echo ""
    echo "(No changes made — dry-run mode.)"
    exit 0
fi

# Confirmation prompt (unless --yes was passed)
if [[ $AUTO_YES -eq 0 ]]; then
    echo "The following will be permanently deleted:"
    for target in "${TO_REMOVE[@]}"; do
        echo "  - $target"
    done
    echo ""
    read -r -p "Are you sure? This will permanently delete the listed directories. [y/N] " answer
    case "$answer" in
        [yY])
            ;;
        *)
            echo "Aborted."
            exit 1
            ;;
    esac
    echo ""
fi

# Perform the actual removal
removed=0
for target in "${TO_REMOVE[@]}"; do
    rm -rf "$target"
    echo "[removed] $target"
    ((removed++))
done

# Clean up empty parent if nothing left
if [[ -d "$TARGET_PARENT" ]]; then
    remaining=$(find "$TARGET_PARENT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$remaining" -eq 0 ]]; then
        rmdir "$TARGET_PARENT" 2>/dev/null && echo "[cleanup] Removed empty directory: $TARGET_PARENT" || true
    fi
fi

echo ""
echo "========================================"
echo " Uninstall Summary"
echo "========================================"
echo ""
echo "  Removed: $removed skill(s)"
echo "  Skipped: $skipped skill(s) (not found)"
echo ""
echo "Note: Other skills in ~/.hermes/skills/ were NOT touched."
echo "Done."
