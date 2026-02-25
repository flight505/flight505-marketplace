#!/usr/bin/env bash
# Shared utilities for marketplace scripts.
# Source this file: source "$(dirname "$0")/common.sh"

if [[ -z "${MARKETPLACE_ROOT:-}" ]]; then
    _candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
    if [[ -f "$_candidate/.claude-plugin/marketplace.json" ]]; then
        MARKETPLACE_ROOT="$_candidate"
    else
        MARKETPLACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
    fi
    unset _candidate
fi
MARKETPLACE_JSON="$MARKETPLACE_ROOT/.claude-plugin/marketplace.json"

# Get plugin list from marketplace.json (single source of truth)
get_plugins() {
    jq -r '.plugins[].name' "$MARKETPLACE_JSON"
}

# Get plugin list as a bash-compatible space-separated string
get_plugins_string() {
    get_plugins | tr '\n' ' ' | sed 's/ $//'
}

# Get plugin list as a pipe-separated regex pattern (for grep/regex matching)
get_plugins_regex() {
    get_plugins | paste -sd '|' -
}

# Check if a plugin name is valid
is_valid_plugin() {
    local name="$1"
    get_plugins | grep -qx "$name"
}
