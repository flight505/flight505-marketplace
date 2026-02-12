#!/bin/bash
set -euo pipefail

# Phase 3: Add webhook notification workflows to all plugin repos
# This script automates adding notify-marketplace.yml to each plugin submodule

echo "========================================="
echo "Phase 3: Webhook Setup Script"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_FILE="$MARKETPLACE_ROOT/templates/notify-marketplace.yml"

# Verify template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}❌ Error: Template not found at $TEMPLATE_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found template: $TEMPLATE_FILE${NC}"
echo ""

# Plugin repos to update
PLUGINS=(
    "sdk-bridge"
    "taskplex"
    "storybook-assistant"
    "claude-project-planner"
    "nano-banana"
)

# Track results
SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

echo "Adding webhook workflows to ${#PLUGINS[@]} plugins..."
echo ""

for plugin in "${PLUGINS[@]}"; do
    echo "-------------------------------------------"
    echo "Processing: $plugin"
    echo "-------------------------------------------"

    PLUGIN_DIR="$MARKETPLACE_ROOT/$plugin"

    # Check if plugin directory exists
    if [ ! -d "$PLUGIN_DIR" ]; then
        echo -e "${RED}❌ Plugin directory not found: $PLUGIN_DIR${NC}"
        ((ERROR_COUNT++))
        echo ""
        continue
    fi

    cd "$PLUGIN_DIR"

    # Create .github/workflows directory
    WORKFLOW_DIR=".github/workflows"
    WORKFLOW_FILE="$WORKFLOW_DIR/notify-marketplace.yml"

    # Check if workflow already exists
    if [ -f "$WORKFLOW_FILE" ]; then
        echo -e "${YELLOW}⚠️  Workflow already exists: $WORKFLOW_FILE${NC}"
        echo "   Skipping (delete manually if you want to replace)"
        ((SKIP_COUNT++))
        echo ""
        continue
    fi

    # Create directory
    mkdir -p "$WORKFLOW_DIR"
    echo -e "${GREEN}✅ Created directory: $WORKFLOW_DIR${NC}"

    # Copy template
    cp "$TEMPLATE_FILE" "$WORKFLOW_FILE"
    echo -e "${GREEN}✅ Copied template to: $WORKFLOW_FILE${NC}"

    # Show git status
    echo ""
    echo "Git status:"
    git status --short | grep -E "\.github/workflows" || echo "   (no changes detected)"

    ((SUCCESS_COUNT++))
    echo ""
done

echo "========================================="
echo "Summary"
echo "========================================="
echo -e "${GREEN}✅ Success: $SUCCESS_COUNT${NC}"
echo -e "${YELLOW}⚠️  Skipped: $SKIP_COUNT${NC}"
echo -e "${RED}❌ Errors:  $ERROR_COUNT${NC}"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "Next steps:"
    echo ""
    echo "1. Review changes in each plugin directory"
    echo "2. Commit and push to each plugin repo:"
    echo ""
    for plugin in "${PLUGINS[@]}"; do
        PLUGIN_DIR="$MARKETPLACE_ROOT/$plugin"
        if [ -d "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/.github/workflows/notify-marketplace.yml" ]; then
            if ! git -C "$PLUGIN_DIR" diff --quiet .github/workflows/notify-marketplace.yml 2>/dev/null; then
                echo "   cd $plugin"
                echo "   git add .github/workflows/notify-marketplace.yml"
                echo "   git commit -m 'feat: add marketplace webhook notification'"
                echo "   git push origin main"
                echo "   cd .."
                echo ""
            fi
        fi
    done
    echo "3. Verify MARKETPLACE_UPDATE_TOKEN secret is added to each repo"
    echo "4. Test with a version bump in any plugin"
    echo ""
    echo "See PHASE3_WEBHOOKS_GUIDE.md for detailed instructions."
fi

echo "========================================="
