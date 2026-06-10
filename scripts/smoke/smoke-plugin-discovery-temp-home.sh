#!/usr/bin/env bash
# smoke-plugin-discovery-temp-home.sh — verify Hermes can discover the plugin in a temp HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/plugins/hermes-evidence-runtime"
PLUGIN_NAME="hermes-evidence-runtime"
TMP_HOME="/tmp/hermes-plugin-discovery-home"
OUTPUT_PATH="/tmp/hermes-plugin-discovery-output.txt"
REAL_HOME="${HOME:-}"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

resolve_hermes_bin() {
  if [[ -n "${HERMES_BIN_OVERRIDE:-}" && -x "$HERMES_BIN_OVERRIDE" ]]; then
    printf '%s\n' "$HERMES_BIN_OVERRIDE"
    return 0
  fi

  local candidate raw resolved
  candidate="$(command -v hermes 2>/dev/null || true)"
  if [[ -z "$candidate" ]]; then
    return 1
  fi

  # Some local launchers derive the real Hermes venv path from $HOME and then
  # override HERMES_HOME. Parse that launcher and call the real binary directly
  # so this smoke can point HERMES_HOME at /tmp without writing real HOME.
  if [[ -f "$candidate" ]]; then
    raw="$(grep -E '^HERMES_BIN=' "$candidate" 2>/dev/null | head -1 || true)"
    if [[ -n "$raw" ]]; then
      resolved="${raw#HERMES_BIN=}"
      resolved="${resolved%\"}"
      resolved="${resolved#\"}"
      resolved="${resolved//\$HOME/$REAL_HOME}"
      resolved="${resolved//\$\{HOME\}/$REAL_HOME}"
      if [[ -x "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi

    raw="$(grep -E '^exec ".*hermes" "\$@"' "$candidate" 2>/dev/null | head -1 || true)"
    if [[ -n "$raw" ]]; then
      resolved="${raw#exec \"}"
      resolved="${resolved%%\"*}"
      if [[ -x "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
  fi

  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

real_plugin_path="$REAL_HOME/.hermes/plugins/$PLUGIN_NAME"
real_home_before="absent"
if [[ -e "$real_plugin_path" ]]; then
  real_home_before="present"
fi

rm -rf "$TMP_HOME"
mkdir -p "$TMP_HOME/.hermes/plugins"
cp -R "$PLUGIN_SRC" "$TMP_HOME/.hermes/plugins/$PLUGIN_NAME"

plugin_copied="no"
if [[ -f "$TMP_HOME/.hermes/plugins/$PLUGIN_NAME/plugin.yaml" ]]; then
  plugin_copied="yes"
fi

HERMES_BIN="$(resolve_hermes_bin || true)"
if [[ -z "$HERMES_BIN" ]]; then
  {
    echo "plugin copied: $plugin_copied"
    echo "real HOME touched: no"
    echo "hermes plugins command: DISCOVERY_UNSUPPORTED"
    echo "plugin discovered: no"
    echo "tool listing available: unknown"
    echo "output path: $OUTPUT_PATH"
    echo "verdict: PARTIAL"
    echo "reason: hermes command not found"
  } | tee "$OUTPUT_PATH"
  exit 2
fi

if ! "$HERMES_BIN" plugins --help 2>&1 | grep -Eq '\blist\b|\bls\b'; then
  {
    echo "plugin copied: $plugin_copied"
    echo "real HOME touched: no"
    echo "hermes plugins command: DISCOVERY_UNSUPPORTED"
    echo "plugin discovered: no"
    echo "tool listing available: unknown"
    echo "output path: $OUTPUT_PATH"
    echo "verdict: PARTIAL"
    echo "reason: hermes plugins list is unavailable"
  } | tee "$OUTPUT_PATH"
  exit 2
fi

LIST_ARGS=(plugins list --user)
if "$HERMES_BIN" plugins list --help 2>&1 | grep -q -- '--json'; then
  LIST_ARGS+=(--json)
elif "$HERMES_BIN" plugins list --help 2>&1 | grep -q -- '--plain'; then
  LIST_ARGS+=(--plain)
fi

set +e
HERMES_HOME="$TMP_HOME/.hermes" HERMES_PLUGINS_DEBUG=1 \
  "$HERMES_BIN" "${LIST_ARGS[@]}" >"$OUTPUT_PATH" 2>&1
list_exit=$?
set -e

plugin_discovered="no"
if grep -q "$PLUGIN_NAME" "$OUTPUT_PATH"; then
  plugin_discovered="yes"
fi

real_home_after="absent"
if [[ -e "$real_plugin_path" ]]; then
  real_home_after="present"
fi

real_home_touched="no"
if [[ "$real_home_before" != "$real_home_after" ]]; then
  real_home_touched="yes"
fi

command_display="HERMES_HOME=$TMP_HOME/.hermes HERMES_PLUGINS_DEBUG=1 $HERMES_BIN ${LIST_ARGS[*]}"

tool_listing="unknown"
if grep -Eq 'evidence_doctor|evidence_active_run_status|evidence_run_init|evidence_drive_s_run' "$OUTPUT_PATH"; then
  tool_listing="yes"
fi

verdict="FAIL"
if [[ "$list_exit" -eq 0 && "$plugin_copied" == "yes" && "$plugin_discovered" == "yes" && "$real_home_touched" == "no" ]]; then
  verdict="PASS"
fi

echo "plugin copied: $plugin_copied"
echo "real HOME touched: $real_home_touched"
echo "hermes plugins command: $command_display"
echo "plugin discovered: $plugin_discovered"
echo "tool listing available: $tool_listing"
echo "output path: $OUTPUT_PATH"
echo "verdict: $verdict"

if [[ "$verdict" != "PASS" ]]; then
  echo "--- discovery output ---"
  sed -n '1,160p' "$OUTPUT_PATH" || true
  exit 1
fi

echo "smoke-plugin-discovery-temp-home: PASS"
