#!/bin/bash
set -euo pipefail

# Quick development testing script for individual plugins
# Usage: ./scripts/dev-test.sh [plugin-name]
# Example: ./scripts/dev-test.sh sdk-bridge

PLUGIN=${1:-}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Available plugins
AVAILABLE_PLUGINS=("sdk-bridge" "storybook-assistant" "claude-project-planner" "nano-banana")

usage() {
    echo "Usage: $0 [plugin-name]"
    echo ""
    echo "Available plugins:"
    for p in "${AVAILABLE_PLUGINS[@]}"; do
        echo "  - $p"
    done
    echo ""
    echo "Examples:"
    echo "  $0 sdk-bridge              # Test single plugin"
    echo "  $0                         # Test all plugins"
    exit 1
}

test_plugin() {
    local plugin=$1
    local plugin_dir="$MARKETPLACE_ROOT/$plugin"

    # Handle sdk-bridge nested structure (special case)
    local manifest_path
    if [ "$plugin" = "sdk-bridge" ]; then
        manifest_path="$plugin_dir/plugins/sdk-bridge/.claude-plugin/plugin.json"
        plugin_dir="$plugin_dir/plugins/sdk-bridge"
    else
        manifest_path="$plugin_dir/.claude-plugin/plugin.json"
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: $plugin${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check plugin directory exists
    if [ ! -d "$plugin_dir" ]; then
        echo -e "${RED}❌ Plugin directory not found: $plugin_dir${NC}"
        return 1
    fi

    # Step 1: Validate manifest
    echo -e "${YELLOW}Step 1: Validating plugin manifest...${NC}"
    if [ ! -f "$manifest_path" ]; then
        echo -e "${RED}❌ Missing plugin.json at: $manifest_path${NC}"
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "$manifest_path" 2>/dev/null; then
        echo -e "${RED}❌ Invalid JSON in plugin.json${NC}"
        return 1
    fi

    # Extract plugin info
    PLUGIN_NAME=$(jq -r '.name' "$manifest_path")
    PLUGIN_VERSION=$(jq -r '.version' "$manifest_path")
    PLUGIN_DESC=$(jq -r '.description' "$manifest_path")

    echo -e "${GREEN}✅ Manifest valid${NC}"
    echo "   Name: $PLUGIN_NAME"
    echo "   Version: $PLUGIN_VERSION"
    echo "   Description: $PLUGIN_DESC"
    echo ""

    # Step 2: Check structure
    echo -e "${YELLOW}Step 2: Checking plugin structure...${NC}"

    local has_components=false

    # Check for commands
    if [ -d "$plugin_dir/commands" ]; then
        local cmd_count=$(find "$plugin_dir/commands" -name "*.md" -type f | wc -l | tr -d ' ')
        if [ "$cmd_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Commands: $cmd_count found${NC}"
            has_components=true
        fi
    fi

    # Check for skills
    if [ -d "$plugin_dir/skills" ]; then
        local skill_count=$(find "$plugin_dir/skills" -name "SKILL.md" -type f | wc -l | tr -d ' ')
        if [ "$skill_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Skills: $skill_count found${NC}"
            has_components=true
        fi
    fi

    # Check for agents
    if [ -d "$plugin_dir/agents" ]; then
        local agent_count=$(find "$plugin_dir/agents" -name "*.md" -type f | wc -l | tr -d ' ')
        if [ "$agent_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Agents: $agent_count found${NC}"
            has_components=true
        fi
    fi

    # Check for hooks
    if [ -f "$plugin_dir/hooks/hooks.json" ]; then
        echo -e "${GREEN}✅ Hooks: configured${NC}"
        has_components=true
    fi

    # Check for MCP servers
    if [ -f "$plugin_dir/.mcp.json" ] || jq -e '.mcpServers' "$plugin_dir/.claude-plugin/plugin.json" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ MCP: configured${NC}"
        has_components=true
    fi

    if [ "$has_components" = false ]; then
        echo -e "${YELLOW}⚠️  No components found (commands, skills, agents, hooks, MCP)${NC}"
    fi
    echo ""

    # Step 3: Check for executable scripts
    echo -e "${YELLOW}Step 3: Checking executable permissions...${NC}"
    local non_executable=$(find "$plugin_dir" \( -name "*.sh" -o -name "run-hook.cmd" \) ! -executable -type f 2>/dev/null || true)
    if [ -n "$non_executable" ]; then
        echo -e "${YELLOW}⚠️  Warning: Some scripts are not executable:${NC}"
        echo "$non_executable" | sed 's/^/   /'
        echo ""
        echo "   Fix with: chmod +x <script-path>"
    else
        echo -e "${GREEN}✅ All scripts executable${NC}"
    fi
    echo ""

    # Step 4: Test loading with --plugin-dir
    echo -e "${YELLOW}Step 4: Testing plugin load...${NC}"
    echo -e "${BLUE}   Running: claude --plugin-dir $plugin_dir${NC}"
    echo -e "${BLUE}   This will start Claude Code - type /help then /exit${NC}"
    echo ""
    read -p "Press Enter to continue or Ctrl+C to skip... " -r
    echo ""

    # Run Claude Code with the plugin
    claude --plugin-dir "$plugin_dir" || {
        echo -e "${RED}❌ Plugin failed to load${NC}"
        return 1
    }

    echo ""
    echo -e "${GREEN}✅ Plugin loaded successfully${NC}"
    echo ""

    # Summary
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ $plugin tests passed${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    return 0
}

# Main execution
cd "$MARKETPLACE_ROOT"

if [ -n "$PLUGIN" ]; then
    # Test single plugin
    if [[ ! " ${AVAILABLE_PLUGINS[@]} " =~ " ${PLUGIN} " ]]; then
        echo -e "${RED}Error: Unknown plugin '$PLUGIN'${NC}"
        echo ""
        usage
    fi

    test_plugin "$PLUGIN"
else
    # Test all plugins
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Plugin Development Testing Suite             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Testing all plugins..."

    failed_plugins=()
    for plugin in "${AVAILABLE_PLUGINS[@]}"; do
        if ! test_plugin "$plugin"; then
            failed_plugins+=("$plugin")
        fi
    done

    # Final summary
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   Final Summary                       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ${#failed_plugins[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All plugins passed tests${NC}"
        echo ""
        echo "Plugins tested: ${#AVAILABLE_PLUGINS[@]}"
        for p in "${AVAILABLE_PLUGINS[@]}"; do
            echo -e "  ${GREEN}✅${NC} $p"
        done
    else
        echo -e "${RED}❌ Some plugins failed${NC}"
        echo ""
        echo "Failed plugins:"
        for p in "${failed_plugins[@]}"; do
            echo -e "  ${RED}❌${NC} $p"
        done
        exit 1
    fi
fi

echo ""
