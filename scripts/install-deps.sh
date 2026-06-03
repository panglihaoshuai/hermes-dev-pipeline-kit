#!/usr/bin/env bash
set -euo pipefail

#
# hermes-dev-pipeline-kit — install-deps.sh
# Checks and optionally installs recommended dependencies.
# Default: dry-run (report only). Use --yes to install approved deps.
#

DRY_RUN=1
YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y) YES=1; DRY_RUN=0 ;;
        *)
            echo "[ERROR] Unknown option: $arg"
            echo "Usage: $0 [--dry-run] [--yes|-y]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo " hermes-dev-pipeline-kit dependency check"
echo "========================================"
echo ""

FOUND=0
MISSING=0
INSTALLED=0
SKIPPED=0

# --- System tools (never auto-install) ---

check_system_tool() {
    local name="$1"
    if command -v "$name" &>/dev/null; then
        echo "  [ok] $name: $(command -v "$name")"
        ((FOUND++)) || true
    else
        echo "  [MISSING] $name — required, must be installed manually"
        ((MISSING++)) || true
    fi
}

echo "--- Required system tools ---"
check_system_tool git
check_system_tool bash
check_system_tool grep
echo ""

# --- Optional tools (never auto-install) ---

echo "--- Optional tools ---"
if command -v gh &>/dev/null; then
    echo "  [ok] gh (GitHub CLI): $(command -v gh)"
    ((FOUND++)) || true
else
    echo "  [--] gh (GitHub CLI): not found (optional, needed for GitHub Publish Lane)"
    echo "       Install: https://cli.github.com/"
    ((SKIPPED++)) || true
fi
echo ""

# --- Recommended Hermes skills ---

echo "--- Recommended Hermes skills ---"

check_hermes_skill() {
    local name="$1"
    local source="$2"
    local desc="$3"
    local skill_path="$HOME/.hermes/skills/$name"

    if [[ -d "$skill_path" ]]; then
        echo "  [ok] $name: installed at $skill_path"
        ((FOUND++)) || true
    else
        echo "  [--] $name: not found"
        echo "       Source: $source"
        echo "       $desc"
        if [[ $YES -eq 1 ]]; then
            echo "       [auto-install not supported for Hermes skills — install manually]"
        else
            echo "       [manual install required]"
        fi
        ((MISSING++)) || true
    fi
}

# Check for gstack in common locations
GSTACK_FOUND=0
for d in "$HOME/.hermes/skills/gstack" "$HOME/.hermes/skills/gstack/.hermes/skills" "$HOME/.hermes/profiles/default/skills/gstack"; do
    if [[ -d "$d" ]]; then
        echo "  [ok] gstack: found at $d"
        ((FOUND++)) || true
        GSTACK_FOUND=1
        break
    fi
done
if [[ $GSTACK_FOUND -eq 0 ]]; then
    echo "  [--] gstack: not found"
    echo "       Source: https://github.com/garrytan/gstack"
    echo "       Provides plan-eng-review, investigate, ship, review, retro skills"
    echo "       [manual install required — clone and copy to ~/.hermes/skills/]"
    ((MISSING++)) || true
fi
echo ""

# --- Recommended ClaudeCode skills ---

echo "--- Recommended ClaudeCode skills ---"

MATT_FOUND=0
for d in "$HOME/.claude/skills" "$HOME/.claude/commands"; do
    if [[ -d "$d" ]] && ls "$d"/*tdd* "$d"/*diagnose* "$d"/*prototype* 2>/dev/null | head -1 | grep -q .; then
        echo "  [ok] Matt Pocock skills: found in $d"
        ((FOUND++)) || true
        MATT_FOUND=1
        break
    fi
done
if [[ $MATT_FOUND -eq 0 ]]; then
    echo "  [--] Matt Pocock skills (tdd, diagnose, prototype, to-issues, grill-me): not found"
    echo "       Source: https://github.com/mattpocock/skills"
    echo "       Used by ClaudeCode when executing work orders"
    echo "       [manual install required — see source repo for instructions]"
    ((MISSING++)) || true
fi
echo ""

# --- Summary ---

echo "========================================"
echo " Dependency Check Summary"
echo "========================================"
echo ""
echo "  Found:    $FOUND"
echo "  Missing:  $MISSING"
echo "  Skipped:  $SKIPPED"
echo ""

if [[ $MISSING -eq 0 ]]; then
    echo "  Result: PASS — all dependencies available"
    exit 0
elif [[ $MISSING -le 2 ]]; then
    echo "  Result: PARTIAL — optional dependencies missing"
    echo "  Core pipeline will work. Install recommended deps for full functionality."
    exit 0
else
    echo "  Result: PARTIAL — several dependencies missing"
    echo "  Core pipeline will work. Install recommended deps for full functionality."
    exit 0
fi
