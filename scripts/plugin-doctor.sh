#!/bin/bash
set -euo pipefail

# Plugin Doctor — Native CLI Validation + Cache Drift Detection
#
# Three checks:
#   1. `claude plugin validate` per plugin (source-level, no API key)
#   2. Cache drift detection — compares source against installed cache
#      using installed_plugins.json, git SHAs, and file diffs
#      (works inside a running session; does NOT call `claude plugin list`)
#   3. Offline sanity — executable hooks, valid event names, no duplicate hooks field
#
# Exit 0 = all pass, Exit 1 = any failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

read -ra PLUGINS <<< "$(get_plugins_string)"
MARKETPLACE_NAME="flight505-plugins"
FAILURES=0
WARNINGS=0

# Plugin cache and registry paths
PLUGIN_CACHE="$HOME/.claude/plugins/cache/$MARKETPLACE_NAME"
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"
MARKETPLACE_CLONE="$HOME/.claude/plugins/marketplaces/$MARKETPLACE_NAME"

# Valid hook event names (case-sensitive, Claude Code CLI spec)
VALID_EVENTS="PreToolUse PostToolUse PostToolUseFailure Stop Notification SubagentStart SubagentStop TaskCompleted PreCompact SessionStart SessionEnd PermissionRequest"

get_plugin_path() {
    local plugin=$1
    echo "$MARKETPLACE_ROOT/$plugin"
}

fail() { echo -e "${RED}FAIL: $1${NC}"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}WARN: $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
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

# ─── Check 2: Cache drift detection ────────────────────────────────
# Compares source against installed cache by reading files directly.
# Does NOT call `claude plugin list` (hangs inside a running session).
check_cache_drift() {
    echo ""
    echo -e "${BLUE}=== Check 2: Cache drift detection ===${NC}"

    # 2a. Is the marketplace registered?
    if [ ! -f "$KNOWN_MARKETPLACES" ]; then
        warn "No known_marketplaces.json — plugins may not be installed"
        info "Run: claude plugin marketplace add flight505/flight505-marketplace"
        return 0
    fi

    local mp_registered
    mp_registered=$(jq -r ".[\"$MARKETPLACE_NAME\"] // empty" "$KNOWN_MARKETPLACES" 2>/dev/null) || true
    if [ -z "$mp_registered" ]; then
        warn "$MARKETPLACE_NAME not registered as a known marketplace"
        info "Run: claude plugin marketplace add flight505/flight505-marketplace"
        return 0
    fi
    pass "Marketplace '$MARKETPLACE_NAME' registered"

    # 2b. Per-plugin: compare source SHA against installed SHA and cache content
    for plugin in "${PLUGINS[@]}"; do
        local src_path
        src_path=$(get_plugin_path "$plugin")
        local src_manifest="$src_path/.claude-plugin/plugin.json"

        # Skip if source doesn't exist (submodule not initialized)
        if [ ! -f "$src_manifest" ]; then
            info "$plugin: source not found (submodule not initialized?)"
            continue
        fi

        local src_version
        src_version=$(jq -r '.version' "$src_manifest" 2>/dev/null) || true

        # Check if plugin is in installed_plugins.json
        local installed_entry
        installed_entry=$(jq -r ".plugins[\"${plugin}@${MARKETPLACE_NAME}\"][0] // empty" "$INSTALLED_JSON" 2>/dev/null) || true

        if [ -z "$installed_entry" ]; then
            warn "$plugin v$src_version: not in installed_plugins.json (cached but not installed?)"
            info "Run: claude plugin install ${plugin}@${MARKETPLACE_NAME}"
            continue
        fi

        local installed_version installed_sha install_path
        installed_version=$(echo "$installed_entry" | jq -r '.version') || true
        installed_sha=$(echo "$installed_entry" | jq -r '.gitCommitSha // empty') || true
        install_path=$(echo "$installed_entry" | jq -r '.installPath') || true

        # Compare versions
        if [ "$src_version" != "$installed_version" ]; then
            fail "$plugin: version drift — source=$src_version, installed=$installed_version"
            info "Run: claude plugin update ${plugin}@${MARKETPLACE_NAME}  (then restart Claude Code)"
            continue
        fi

        # Compare git SHAs if available
        local src_sha=""
        if git -C "$src_path" rev-parse HEAD >/dev/null 2>&1; then
            src_sha=$(git -C "$src_path" rev-parse HEAD 2>/dev/null) || true
        fi

        if [ -n "$installed_sha" ] && [ -n "$src_sha" ] && [ "$installed_sha" != "$src_sha" ]; then
            fail "$plugin v$src_version: commit drift — source=${src_sha:0:7}, installed=${installed_sha:0:7}"
            info "Source has newer commits. Run: claude plugin update ${plugin}@${MARKETPLACE_NAME}  (then restart)"
            continue
        fi

        # Compare cached plugin.json against source plugin.json
        local cached_manifest="$install_path/.claude-plugin/plugin.json"
        if [ -f "$cached_manifest" ]; then
            if ! diff -q "$src_manifest" "$cached_manifest" >/dev/null 2>&1; then
                fail "$plugin v$src_version: plugin.json differs between source and cache"
                diff "$src_manifest" "$cached_manifest" 2>/dev/null | sed 's/^/       /' || true
                info "Run: claude plugin update ${plugin}@${MARKETPLACE_NAME}  (then restart)"
                continue
            fi
        fi

        pass "$plugin v$src_version (sha ${installed_sha:0:7})"
    done

    # 2c. Check marketplace clone freshness
    if [ -d "$MARKETPLACE_CLONE" ]; then
        local clone_head
        clone_head=$(git -C "$MARKETPLACE_CLONE" rev-parse HEAD 2>/dev/null) || true
        local source_head
        source_head=$(git -C "$MARKETPLACE_ROOT" rev-parse HEAD 2>/dev/null) || true

        if [ -n "$clone_head" ] && [ -n "$source_head" ] && [ "$clone_head" != "$source_head" ]; then
            warn "Marketplace clone is behind source (clone=${clone_head:0:7}, source=${source_head:0:7})"
            info "Run: claude plugin marketplace update $MARKETPLACE_NAME"
        else
            pass "Marketplace clone in sync (${clone_head:0:7})"
        fi
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

        # 3c. Manifest must NOT have a "hooks" field (hooks/hooks.json is auto-discovered)
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
check_cache_drift
check_offline_sanity

echo ""
if [ $FAILURES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
elif [ $FAILURES -eq 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s), 0 failures.${NC}"
    exit 0
else
    echo -e "${RED}$FAILURES failure(s), $WARNINGS warning(s).${NC}"
    exit 1
fi
