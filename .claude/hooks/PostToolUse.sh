#!/bin/bash
# PostToolUse Hook - Session-Aware Plugin Cache Management
# Detects plugin version bumps and manages cache clearing safely

set -euo pipefail

# Read stdin (tool use metadata)
TOOL_INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Edit/Write operations on plugin.json files
if [[ ! "$TOOL_NAME" =~ ^(Edit|Write)$ ]] || [[ ! "$FILE_PATH" =~ plugin\.json$ ]]; then
    exit 0
fi

# Only process plugin.json files in submodules (not marketplace.json)
if [[ ! "$FILE_PATH" =~ ^(sdk-bridge|storybook-assistant|claude-project-planner|nano-banana)/ ]]; then
    exit 0
fi

# Extract plugin name from path
PLUGIN_NAME=$(echo "$FILE_PATH" | cut -d'/' -f1)

# Function to count active Claude Code sessions
count_claude_sessions() {
    # Count claude processes (exclude grep itself and this script)
    pgrep -f "claude" 2>/dev/null | grep -v "^$$\$" | wc -l | tr -d ' '
}

# Function to get plugin version from file
get_plugin_version() {
    local plugin_file="$1"
    if [[ -f "$plugin_file" ]]; then
        jq -r '.version // empty' "$plugin_file" 2>/dev/null
    fi
}

# Function to clear plugin cache safely
clear_plugin_cache() {
    local plugin="$1"
    local cache_dir="$HOME/.claude/plugins/cache/flight505-plugins/$plugin"

    if [[ -d "$cache_dir" ]]; then
        echo "[CACHE-MANAGER] Clearing cache for $plugin..."
        rm -rf "$cache_dir"
        echo "[CACHE-MANAGER] ✅ Cache cleared: $cache_dir"
        return 0
    else
        echo "[CACHE-MANAGER] ℹ️  No cache to clear for $plugin"
        return 0
    fi
}

# Check if this is a version change
PLUGIN_FILE="$FILE_PATH"
NEW_VERSION=$(get_plugin_version "$PLUGIN_FILE")

if [[ -z "$NEW_VERSION" ]]; then
    # Not a version field change, exit silently
    exit 0
fi

# Log the version change detection
echo "[CACHE-MANAGER] Detected version change in $PLUGIN_NAME: v$NEW_VERSION"

# Count active Claude Code sessions
SESSION_COUNT=$(count_claude_sessions)

echo "[CACHE-MANAGER] Active Claude Code sessions: $SESSION_COUNT"

# Decision logic based on session count
if [[ "$SESSION_COUNT" -eq 0 ]]; then
    echo "[CACHE-MANAGER] ⚠️  No active sessions detected (unusual during edit)"
    echo "[CACHE-MANAGER] Cache clearing skipped for safety"
    exit 0
elif [[ "$SESSION_COUNT" -eq 1 ]]; then
    echo "[CACHE-MANAGER] ✅ Single session detected - safe to clear cache"
    clear_plugin_cache "$PLUGIN_NAME"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Plugin Cache Cleared                                          ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  Plugin: $PLUGIN_NAME"
    echo "║  Version: v$NEW_VERSION"
    echo "║  Cache: Cleared automatically"
    echo "║"
    echo "║  Next steps:"
    echo "║  1. Commit and push: git commit -m 'chore: bump $PLUGIN_NAME to v$NEW_VERSION'"
    echo "║  2. Reinstall plugin: /plugin uninstall $PLUGIN_NAME@flight505-plugins"
    echo "║                      /plugin install $PLUGIN_NAME@flight505-plugins"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
else
    echo "[CACHE-MANAGER] ⚠️  Multiple sessions detected ($SESSION_COUNT)"
    echo "[CACHE-MANAGER] Cache clearing skipped to avoid conflicts"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  Multiple Claude Code Sessions Detected                    ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  Plugin: $PLUGIN_NAME"
    echo "║  Version: v$NEW_VERSION"
    echo "║  Sessions: $SESSION_COUNT active"
    echo "║"
    echo "║  Cache NOT cleared automatically (conflict risk)"
    echo "║"
    echo "║  Manual steps after closing other sessions:"
    echo "║  1. Exit all other Claude Code sessions"
    echo "║  2. Clear cache: rm -rf ~/.claude/plugins/cache/flight505-plugins/$PLUGIN_NAME"
    echo "║  3. Reinstall: /plugin uninstall $PLUGIN_NAME@flight505-plugins"
    echo "║               /plugin install $PLUGIN_NAME@flight505-plugins"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
fi

exit 0
