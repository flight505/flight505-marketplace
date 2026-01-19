#!/bin/bash
set -euo pipefail

# Setup development hooks for plugin testing
# This configures Claude Code to automatically validate plugins after edits

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS_FILE="$MARKETPLACE_ROOT/.claude/settings.local.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Plugin Development Hooks Setup                 ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# Create .claude directory if it doesn't exist
mkdir -p "$MARKETPLACE_ROOT/.claude"

# Check if settings file exists
if [ -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}⚠️  Settings file already exists: $SETTINGS_FILE${NC}"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled. No changes made."
        exit 0
    fi
fi

# Create hooks configuration
cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/validate-plugin-manifests.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '✅ Plugin development hooks loaded. Validation will run after Write/Edit operations.'"
          }
        ]
      }
    ]
  }
}
EOF

echo -e "${GREEN}✅ Development hooks configured${NC}"
echo ""
echo "Created: $SETTINGS_FILE"
echo ""
echo -e "${BLUE}What this does:${NC}"
echo ""
echo "1. ${GREEN}PostToolUse Hook (Write|Edit):${NC}"
echo "   - Runs after every file write or edit"
echo "   - Executes: ./scripts/validate-plugin-manifests.sh"
echo "   - Catches manifest errors immediately"
echo "   - Provides real-time feedback"
echo ""
echo "2. ${GREEN}SessionStart Hook:${NC}"
echo "   - Displays confirmation when Claude Code starts"
echo "   - Reminds you that validation is active"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo "1. Start Claude Code in this directory:"
echo "   ${YELLOW}cd $MARKETPLACE_ROOT${NC}"
echo "   ${YELLOW}claude${NC}"
echo ""
echo "2. Try editing a plugin file:"
echo "   ${YELLOW}Edit sdk-bridge/.claude-plugin/plugin.json${NC}"
echo ""
echo "3. Watch for automatic validation output"
echo ""
echo -e "${YELLOW}Note:${NC} This file (.claude/settings.local.json) is gitignored"
echo "      and only affects this local development environment."
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
