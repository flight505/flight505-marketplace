#!/bin/bash
set -euo pipefail

# Plugin Doctor — Native CLI Validation
# Uses `claude plugin validate` and `claude plugin list --json` to catch
# issues that hand-coded validators miss (duplicate hooks, schema drift, etc.)
# Exit 0 = all pass, Exit 1 = any failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PLUGINS=("sdk-bridge" "taskplex" "storybook-assistant" "claude-project-planner" "nano-banana")
FAILURES=0

# Valid hook event names (case-sensitive, Claude Code CLI spec)
VALID_EVENTS="PreToolUse PostToolUse PostToolUseFailure Stop Notification SubagentStart SubagentStop TaskCompleted PreCompact SessionStart SessionEnd PermissionRequest"

get_plugin_path() {
    local plugin=$1
    case $plugin in
        sdk-bridge) echo "$MARKETPLACE_ROOT/sdk-bridge/plugins/sdk-bridge" ;;
        *)          echo "$MARKETPLACE_ROOT/$plugin" ;;
    esac
}

fail() { echo -e "${RED}FAIL: $1${NC}"; FAILURES=$((FAILURES + 1)); }
pass() { echo -e "${GREEN}  OK: $1${NC}"; }
info() { echo -e "${BLUE}  --  $1${NC}"; }

# ─── Check 1: claude plugin validate ────────────────────────────────
check_cli_validate() {
    echo ""
    echo -e "${BLUE}=== Check 1: claude plugin validate ===${NC}"

    if ! command -v claude >/dev/null 2>&1; then
        echo -e "${YELLOW}SKIP: claude CLI not found (install from https://claude.ai/code)${NC}"
        return 0
    fi

    for plugin in "${PLUGINS[@]}"; do
        local path
        path=$(get_plugin_path "$plugin")
        if claude plugin validate "$path" >/dev/null 2>&1; then
            pass "$plugin"
        else
            fail "$plugin — claude plugin validate failed"
            claude plugin validate "$path" 2>&1 | sed 's/^/       /' || true
        fi
    done

    # Marketplace-level validation
    if claude plugin validate "$MARKETPLACE_ROOT" >/dev/null 2>&1; then
        pass "marketplace (root)"
    else
        fail "marketplace (root) — claude plugin validate failed"
        claude plugin validate "$MARKETPLACE_ROOT" 2>&1 | sed 's/^/       /' || true
    fi
}

# ─── Check 2: installed plugin error detection ─────────────────────
check_installed_errors() {
    echo ""
    echo -e "${BLUE}=== Check 2: Installed plugin error detection ===${NC}"

    if ! command -v claude >/dev/null 2>&1; then
        echo -e "${YELLOW}SKIP: claude CLI not found${NC}"
        return 0
    fi

    local errors
    errors=$(claude plugin list --json 2>/dev/null \
        | jq -r '[.[] | select(.id | test("flight505")) | select(.errors != null and (.errors | length > 0))] | .[] | "\(.id): \(.errors | join("; "))"' 2>/dev/null) || true

    if [ -z "$errors" ]; then
        pass "No errors in installed flight505 plugins"
    else
        echo "$errors" | while IFS= read -r line; do
            fail "$line"
        done
    fi
}

# ─── Check 3: Offline sanity checks ────────────────────────────────
check_offline_sanity() {
    echo ""
    echo -e "${BLUE}=== Check 3: Offline sanity checks ===${NC}"

    for plugin in "${PLUGINS[@]}"; do
        local path
        path=$(get_plugin_path "$plugin")
        local hooks_dir="$path/hooks"
        local hooks_json="$hooks_dir/hooks.json"
        local manifest="$path/.claude-plugin/plugin.json"

        # 3a. Hook scripts must be executable
        if [ -d "$hooks_dir" ]; then
            while IFS= read -r script; do
                if [ ! -x "$script" ]; then
                    fail "$plugin: not executable — $script"
                fi
            done < <(find "$hooks_dir" -name "*.sh" -type f 2>/dev/null)
        fi

        # 3b. hooks.json event names must be valid
        if [ -f "$hooks_json" ]; then
            local events
            events=$(jq -r '.hooks | keys[]' "$hooks_json" 2>/dev/null) || true
            for event in $events; do
                if ! echo "$VALID_EVENTS" | tr ' ' '\n' | grep -qx "$event"; then
                    fail "$plugin: unknown hook event '$event' in hooks.json"
                fi
            done
            pass "$plugin: hook events valid"
        fi

        # 3c. Manifest must NOT have a "hooks" field pointing to auto-discovered hooks.json
        if [ -f "$manifest" ]; then
            local hooks_field
            hooks_field=$(jq -r 'if .hooks then (.hooks | type) else empty end' "$manifest" 2>/dev/null) || true
            if [ -n "$hooks_field" ]; then
                fail "$plugin: plugin.json has explicit 'hooks' field ($hooks_field) — remove it; hooks/hooks.json is auto-discovered"
            fi
        fi
    done

    # 3d. Marketplace-level check
    local mp_manifest="$MARKETPLACE_ROOT/.claude-plugin/plugin.json"
    if [ -f "$mp_manifest" ]; then
        local mp_hooks
        mp_hooks=$(jq -r 'if .hooks then (.hooks | type) else empty end' "$mp_manifest" 2>/dev/null) || true
        if [ -n "$mp_hooks" ]; then
            fail "marketplace plugin.json has explicit 'hooks' field — remove it; hooks/hooks.json is auto-discovered"
        fi
    fi

    pass "Offline sanity checks complete"
}

# ─── Main ───────────────────────────────────────────────────────────
echo -e "${BLUE}Plugin Doctor — Native CLI Validation${NC}"
echo -e "${BLUE}Marketplace: $MARKETPLACE_ROOT${NC}"

check_cli_validate
check_installed_errors
check_offline_sanity

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
else
    echo -e "${RED}$FAILURES failure(s) detected.${NC}"
    exit 1
fi
