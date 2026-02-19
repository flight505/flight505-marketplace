#!/bin/bash
# PostToolUse Hook - Session-Aware Plugin Cache Management
# Detects plugin version bumps and manages cache clearing safely
# Outputs JSON as required by Claude Code hooks

set -euo pipefail

# Read stdin (tool use metadata)
TOOL_INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Edit/Write operations on plugin.json files
if [[ ! "$TOOL_NAME" =~ ^(Edit|Write)$ ]] || [[ ! "$FILE_PATH" =~ plugin\.json$ ]]; then
    echo '{}'
    exit 0
fi

# Only process plugin.json files in submodules (not marketplace.json)
if [[ ! "$FILE_PATH" =~ ^(sdk-bridge|taskplex|storybook-assistant|claude-project-planner|nano-banana)/ ]]; then
    echo '{}'
    exit 0
fi

# Extract plugin name from path
PLUGIN_NAME=$(echo "$FILE_PATH" | cut -d'/' -f1)

# Get plugin version from file
get_plugin_version() {
    local plugin_file="$1"
    if [[ -f "$plugin_file" ]]; then
        jq -r '.version // empty' "$plugin_file" 2>/dev/null
    fi
}

# Check if this is a version change
PLUGIN_FILE="$FILE_PATH"
NEW_VERSION=$(get_plugin_version "$PLUGIN_FILE")

if [[ -z "$NEW_VERSION" ]]; then
    echo '{}'
    exit 0
fi

# Clear plugin cache
CACHE_DIR="$HOME/.claude/plugins/cache/flight505-plugins/$PLUGIN_NAME"

if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
    # Output informational JSON (pass, no block)
    jq -n --arg plugin "$PLUGIN_NAME" --arg version "$NEW_VERSION" '{
        "description": ("Cache cleared for " + $plugin + " v" + $version + ". Reinstall plugin to pick up changes.")
    }'
else
    echo '{}'
fi

exit 0
