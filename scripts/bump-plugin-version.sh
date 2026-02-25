#!/bin/bash
set -euo pipefail

# Version Bump Script for flight505-marketplace Plugins
# Usage: ./scripts/bump-plugin-version.sh <plugin-name> <new-version> [--dry-run]
#
# Examples:
#   ./scripts/bump-plugin-version.sh sdk-bridge 2.3.0
#   ./scripts/bump-plugin-version.sh claude-project-planner 1.5.0 --dry-run

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse arguments
if [ $# -lt 2 ]; then
  echo -e "${RED}Error: Missing arguments${NC}"
  echo "Usage: $0 <plugin-name> <new-version> [--dry-run]"
  echo ""
  echo "Available plugins:"
  for p in $(get_plugins); do echo "  - $p"; done
  exit 1
fi

PLUGIN_NAME="$1"
NEW_VERSION="$2"
DRY_RUN=false

if [ $# -eq 3 ] && [ "$3" = "--dry-run" ]; then
  DRY_RUN=true
  echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
  echo ""
fi

# Validate semantic version format
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo -e "${RED}Error: Invalid version format. Use semantic versioning (e.g., 1.2.3)${NC}"
  exit 1
fi

# Determine plugin directory (name = dir, enforced by validator)
if ! is_valid_plugin "$PLUGIN_NAME"; then
  echo -e "${RED}Error: Unknown plugin '$PLUGIN_NAME'${NC}"
  echo "Valid plugins: $(get_plugins_string)"
  exit 1
fi
PLUGIN_DIR="$PLUGIN_NAME"
PLUGIN_JSON="$PLUGIN_NAME/.claude-plugin/plugin.json"

# Verify plugin directory exists
if [ ! -d "$PLUGIN_DIR" ]; then
  echo -e "${RED}Error: Plugin directory not found: $PLUGIN_DIR${NC}"
  echo "Make sure you're in the marketplace root directory"
  exit 1
fi

# Get current version
if [ ! -f "$PLUGIN_JSON" ]; then
  echo -e "${RED}Error: plugin.json not found: $PLUGIN_JSON${NC}"
  exit 1
fi

CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_JSON")

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Version Bump: $PLUGIN_NAME${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Current version: ${YELLOW}$CURRENT_VERSION${NC}"
echo -e "  New version:     ${GREEN}$NEW_VERSION${NC}"
echo ""

# Check if version is actually changing
if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  echo -e "${YELLOW}⚠️  Warning: New version is same as current version${NC}"
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 0
  fi
fi

# Step 1: Update plugin.json in submodule
echo -e "${BLUE}Step 1:${NC} Updating plugin.json..."
if [ "$DRY_RUN" = false ]; then
  cd "$PLUGIN_DIR"

  # Update version in plugin.json
  jq --arg version "$NEW_VERSION" '.version = $version' \
    "${PLUGIN_JSON#$PLUGIN_DIR/}" > "${PLUGIN_JSON#$PLUGIN_DIR/}.tmp"
  mv "${PLUGIN_JSON#$PLUGIN_DIR/}.tmp" "${PLUGIN_JSON#$PLUGIN_DIR/}"

  echo -e "${GREEN}✓${NC} Updated $PLUGIN_JSON"

  # Commit in submodule
  git add "${PLUGIN_JSON#$PLUGIN_DIR/}"
  git commit -m "chore: bump version to $NEW_VERSION"
  echo -e "${GREEN}✓${NC} Committed in $PLUGIN_NAME repo"

  cd ..
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would update $PLUGIN_JSON"
  echo -e "${YELLOW}[DRY RUN]${NC} Would commit in $PLUGIN_NAME repo"
fi

# Step 1.5: Update README badge
echo ""
echo -e "${BLUE}Step 1.5:${NC} Updating README badge..."
README_FILE="$PLUGIN_DIR/README.md"

if [ -f "$README_FILE" ]; then
  if [ "$DRY_RUN" = false ]; then
    # Use sed to update version badge (works on both macOS and Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS version of sed
      sed -i '' "s/version-$CURRENT_VERSION-blue\.svg/version-$NEW_VERSION-blue.svg/g" "$README_FILE"
    else
      # Linux version of sed
      sed -i "s/version-$CURRENT_VERSION-blue\.svg/version-$NEW_VERSION-blue.svg/g" "$README_FILE"
    fi

    echo -e "${GREEN}✓${NC} Updated README badge: $CURRENT_VERSION → $NEW_VERSION"

    # Commit README update separately
    cd "$PLUGIN_DIR"
    git add README.md
    git commit -m "docs: update version badge to $NEW_VERSION"
    echo -e "${GREEN}✓${NC} Committed README badge update"
    cd ..
  else
    echo -e "${YELLOW}[DRY RUN]${NC} Would update $README_FILE badge"
  fi
else
  echo -e "${YELLOW}⚠️  Warning: README.md not found in $PLUGIN_DIR${NC}"
fi

# Step 2: Update marketplace.json
echo ""
echo -e "${BLUE}Step 2:${NC} Updating marketplace.json..."
if [ "$DRY_RUN" = false ]; then
  jq --arg name "$PLUGIN_NAME" --arg version "$NEW_VERSION" \
    '(.plugins[] | select(.name == $name) | .version) = $version' \
    .claude-plugin/marketplace.json > .claude-plugin/marketplace.json.tmp
  mv .claude-plugin/marketplace.json.tmp .claude-plugin/marketplace.json

  echo -e "${GREEN}✓${NC} Updated marketplace.json"
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would update marketplace.json"
fi

# Step 3: Bump marketplace version
echo ""
echo -e "${BLUE}Step 3:${NC} Bumping marketplace version..."
CURRENT_MARKETPLACE_VERSION=$(jq -r '.version' .claude-plugin/marketplace.json)
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_MARKETPLACE_VERSION"
PATCH=$((VERSION_PARTS[2] + 1))
NEW_MARKETPLACE_VERSION="${VERSION_PARTS[0]}.${VERSION_PARTS[1]}.${PATCH}"

if [ "$DRY_RUN" = false ]; then
  jq --arg version "$NEW_MARKETPLACE_VERSION" '.version = $version' \
    .claude-plugin/marketplace.json > .claude-plugin/marketplace.json.tmp
  mv .claude-plugin/marketplace.json.tmp .claude-plugin/marketplace.json

  echo -e "${GREEN}✓${NC} Marketplace: $CURRENT_MARKETPLACE_VERSION → $NEW_MARKETPLACE_VERSION"
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would bump marketplace: $CURRENT_MARKETPLACE_VERSION → $NEW_MARKETPLACE_VERSION"
fi

# Step 4: Commit marketplace changes
echo ""
echo -e "${BLUE}Step 4:${NC} Committing marketplace changes..."
if [ "$DRY_RUN" = false ]; then
  git add .claude-plugin/marketplace.json "$PLUGIN_DIR"
  git commit -m "chore: update $PLUGIN_NAME to v$NEW_VERSION

- Updated $PLUGIN_NAME submodule pointer
- Synced marketplace.json version
- Bumped marketplace version to $NEW_MARKETPLACE_VERSION
"
  echo -e "${GREEN}✓${NC} Committed in marketplace repo"
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would commit in marketplace repo"
fi

# Step 5: Push to plugin repo
echo ""
echo -e "${BLUE}Step 5:${NC} Pushing to plugin repo..."
if [ "$DRY_RUN" = false ]; then
  cd "$PLUGIN_DIR"
  git push origin main
  echo -e "${GREEN}✓${NC} Pushed $PLUGIN_NAME to GitHub"

  # Create git tag
  git tag "v$NEW_VERSION"
  git push origin "v$NEW_VERSION"
  echo -e "${GREEN}✓${NC} Created and pushed tag v$NEW_VERSION"

  cd ..
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would push $PLUGIN_NAME to GitHub"
  echo -e "${YELLOW}[DRY RUN]${NC} Would create tag v$NEW_VERSION"
fi

# Step 6: Push marketplace
echo ""
echo -e "${BLUE}Step 6:${NC} Pushing marketplace..."
if [ "$DRY_RUN" = false ]; then
  git push origin main
  echo -e "${GREEN}✓${NC} Pushed marketplace to GitHub"
else
  echo -e "${YELLOW}[DRY RUN]${NC} Would push marketplace to GitHub"
fi

# Step 7: Wait and verify webhook (only if not dry run)
if [ "$DRY_RUN" = false ]; then
  echo ""
  echo -e "${BLUE}Step 7:${NC} Waiting for webhook (30 seconds)..."
  echo -e "${YELLOW}Note: This will only work if MARKETPLACE_UPDATE_TOKEN is valid${NC}"
  sleep 5

  for i in {1..5}; do
    echo -n "."
    sleep 5
  done
  echo ""

  echo ""
  echo -e "${GREEN}✓ Webhook should have triggered${NC}"
  echo ""
  echo "Verify the update:"
  echo "  1. Check GitHub Actions: https://github.com/flight505/flight505-marketplace/actions"
  echo "  2. Check latest workflow run for 'Auto-update Plugin Submodules'"
  echo "  3. If webhook failed (401), regenerate MARKETPLACE_UPDATE_TOKEN"
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Version bump complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  Plugin:      $PLUGIN_NAME"
echo "  Version:     $CURRENT_VERSION → $NEW_VERSION"
echo "  Marketplace: $CURRENT_MARKETPLACE_VERSION → $NEW_MARKETPLACE_VERSION"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}This was a dry run. No changes were made.${NC}"
  echo "Run without --dry-run to apply changes."
fi
