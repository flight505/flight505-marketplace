#!/bin/bash
set -euo pipefail

# Plugin Manifest Validation Script
# Validates all plugin.json files in the marketplace
# Usage: ./scripts/validate-plugin-manifests.sh [--fix]

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(dirname "$SCRIPT_DIR")"
FIX_MODE=false
ERRORS_FOUND=0
WARNINGS_FOUND=0

# Parse arguments
if [ $# -eq 1 ] && [ "$1" = "--fix" ]; then
  FIX_MODE=true
  echo -e "${YELLOW}🔧 FIX MODE ENABLED - Will attempt to auto-fix issues${NC}"
  echo ""
fi

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Plugin Manifest Validation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Plugin configuration - simple function to get plugin dir
get_plugin_dir() {
  case "$1" in
    "sdk-bridge") echo "sdk-bridge" ;;
    "taskplex") echo "taskplex" ;;
    "storybook-assistant") echo "storybook-assistant" ;;
    "claude-project-planner") echo "claude-project-planner" ;;
    "nano-banana") echo "nano-banana" ;;
    "ai-frontier") echo "ai-frontier" ;;
    *) echo "" ;;
  esac
}

# Validation functions

validate_json_syntax() {
  local plugin_json="$1"
  local plugin_name="$2"

  if ! jq empty "$plugin_json" 2>/dev/null; then
    echo -e "${RED}✗${NC} $plugin_name: Invalid JSON syntax"
    ((ERRORS_FOUND++))
    return 1
  fi
  return 0
}

validate_required_fields() {
  local plugin_json="$1"
  local plugin_name="$2"

  local required_fields=("name" "version" "description" "author")
  local missing_fields=()

  for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" "$plugin_json" >/dev/null 2>&1; then
      missing_fields+=("$field")
    fi
  done

  if [ ${#missing_fields[@]} -gt 0 ]; then
    echo -e "${RED}✗${NC} $plugin_name: Missing required fields: ${missing_fields[*]}"
    ((ERRORS_FOUND++))
    return 1
  fi

  return 0
}

validate_version_format() {
  local plugin_json="$1"
  local plugin_name="$2"

  local version=$(jq -r '.version' "$plugin_json")

  if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${RED}✗${NC} $plugin_name: Invalid version format '$version' (expected X.Y.Z)"
    ((ERRORS_FOUND++))
    return 1
  fi

  return 0
}

validate_skills_format() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  # Check if skills field exists
  if ! jq -e '.skills' "$plugin_json" >/dev/null 2>&1; then
    return 0  # Skills are optional
  fi

  local skills=$(jq -r '.skills[]?' "$plugin_json" 2>/dev/null || echo "")

  if [ -z "$skills" ]; then
    return 0  # Empty skills array is OK
  fi

  local has_errors=false

  while IFS= read -r skill; do
    # Check if it starts with ./ (relative path)
    if [[ ! "$skill" =~ ^\.\/ ]]; then
      echo -e "${RED}✗${NC} $plugin_name: Skill '$skill' must be a relative path starting with './' (e.g., './skills/$skill')"
      has_errors=true
      ((ERRORS_FOUND++))
      continue
    fi

    # Check if the path exists
    local skill_path="$MARKETPLACE_ROOT/$plugin_dir/${skill#./}"

    if [ ! -d "$skill_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Skill directory not found: $skill"
      ((WARNINGS_FOUND++))
      continue
    fi

    # Check if SKILL.md exists in the directory
    if [ ! -f "$skill_path/SKILL.md" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Missing SKILL.md in $skill"
      ((WARNINGS_FOUND++))
    fi
  done <<< "$skills"

  if [ "$has_errors" = true ]; then
    return 1
  fi

  return 0
}

validate_agents_format() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  # Check if agents field exists
  if ! jq -e '.agents' "$plugin_json" >/dev/null 2>&1; then
    return 0  # Agents are optional
  fi

  local agents=$(jq -r '.agents[]?' "$plugin_json" 2>/dev/null || echo "")

  if [ -z "$agents" ]; then
    return 0  # Empty agents array is OK
  fi

  local has_errors=false

  while IFS= read -r agent; do
    # Check if it starts with ./ (relative path)
    if [[ ! "$agent" =~ ^\.\/ ]]; then
      echo -e "${RED}✗${NC} $plugin_name: Agent '$agent' must be a relative path starting with './' (e.g., './agents/$agent.md')"
      has_errors=true
      ((ERRORS_FOUND++))
      continue
    fi

    # Check if it ends with .md
    if [[ ! "$agent" =~ \.md$ ]]; then
      echo -e "${RED}✗${NC} $plugin_name: Agent '$agent' must end with '.md'"
      has_errors=true
      ((ERRORS_FOUND++))
      continue
    fi

    # Check if the file exists
    local agent_path="$MARKETPLACE_ROOT/$plugin_dir/${agent#./}"

    if [ ! -f "$agent_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Agent file not found: $agent"
      ((WARNINGS_FOUND++))
    fi
  done <<< "$agents"

  if [ "$has_errors" = true ]; then
    return 1
  fi

  return 0
}

validate_commands_format() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  # Check if commands field exists
  if ! jq -e '.commands' "$plugin_json" >/dev/null 2>&1; then
    return 0  # Commands are optional
  fi

  # Commands can be a string (directory) or array of files
  local commands_type=$(jq -r '.commands | type' "$plugin_json" 2>/dev/null)

  if [ "$commands_type" = "string" ]; then
    local commands_dir=$(jq -r '.commands' "$plugin_json")
    local full_path="$MARKETPLACE_ROOT/$plugin_dir/${commands_dir#./}"

    if [ ! -d "$full_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Commands directory not found: $commands_dir"
      ((WARNINGS_FOUND++))
    fi
    return 0
  fi

  # Array of command files
  local commands=$(jq -r '.commands[]?' "$plugin_json" 2>/dev/null || echo "")

  if [ -z "$commands" ]; then
    return 0
  fi

  while IFS= read -r command; do
    # Check if it starts with ./
    if [[ ! "$command" =~ ^\.\/ ]]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Command '$command' should start with './' (recommended)"
      ((WARNINGS_FOUND++))
      continue
    fi

    # Check if it ends with .md
    if [[ ! "$command" =~ \.md$ ]]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Command '$command' should end with '.md'"
      ((WARNINGS_FOUND++))
      continue
    fi

    # Check if file exists
    local command_path="$MARKETPLACE_ROOT/$plugin_dir/${command#./}"

    if [ ! -f "$command_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Command file not found: $command"
      ((WARNINGS_FOUND++))
    fi
  done <<< "$commands"

  return 0
}

validate_marketplace_sync() {
  local plugin_json="$1"
  local plugin_name="$2"

  local plugin_version=$(jq -r '.version' "$plugin_json")
  local marketplace_version=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .version' "$MARKETPLACE_ROOT/.claude-plugin/marketplace.json")

  if [ -z "$marketplace_version" ]; then
    echo -e "${YELLOW}⚠${NC} $plugin_name: Not found in marketplace.json"
    ((WARNINGS_FOUND++))
    return 0
  fi

  if [ "$plugin_version" != "$marketplace_version" ]; then
    echo -e "${RED}✗${NC} $plugin_name: Version mismatch - plugin.json: $plugin_version, marketplace.json: $marketplace_version"
    ((ERRORS_FOUND++))
    return 1
  fi

  return 0
}

# Auto-fix function for skills/agents
auto_fix_paths() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  echo -e "${BLUE}Attempting to fix $plugin_name...${NC}"

  local temp_file="${plugin_json}.tmp"
  cp "$plugin_json" "$temp_file"

  # Fix skills - add ./skills/ prefix
  local skills=$(jq -r '.skills[]?' "$temp_file" 2>/dev/null || echo "")
  if [ -n "$skills" ]; then
    local fixed_skills="[]"
    while IFS= read -r skill; do
      if [[ ! "$skill" =~ ^\.\/ ]]; then
        fixed_skills=$(echo "$fixed_skills" | jq --arg skill "./skills/$skill" '. += [$skill]')
        echo -e "  ${GREEN}→${NC} Fixed skill: $skill → ./skills/$skill"
      else
        fixed_skills=$(echo "$fixed_skills" | jq --arg skill "$skill" '. += [$skill]')
      fi
    done <<< "$skills"

    jq --argjson skills "$fixed_skills" '.skills = $skills' "$temp_file" > "${temp_file}.2"
    mv "${temp_file}.2" "$temp_file"
  fi

  # Fix agents - add ./agents/ prefix and .md suffix
  local agents=$(jq -r '.agents[]?' "$temp_file" 2>/dev/null || echo "")
  if [ -n "$agents" ]; then
    local fixed_agents="[]"
    while IFS= read -r agent; do
      if [[ ! "$agent" =~ ^\.\/ ]]; then
        local fixed_agent="./agents/$agent"
        if [[ ! "$fixed_agent" =~ \.md$ ]]; then
          fixed_agent="${fixed_agent}.md"
        fi
        fixed_agents=$(echo "$fixed_agents" | jq --arg agent "$fixed_agent" '. += [$agent]')
        echo -e "  ${GREEN}→${NC} Fixed agent: $agent → $fixed_agent"
      else
        fixed_agents=$(echo "$fixed_agents" | jq --arg agent "$agent" '. += [$agent]')
      fi
    done <<< "$agents"

    jq --argjson agents "$fixed_agents" '.agents = $agents' "$temp_file" > "${temp_file}.2"
    mv "${temp_file}.2" "$temp_file"
  fi

  # Move fixed file
  mv "$temp_file" "$plugin_json"
  echo -e "${GREEN}✓${NC} Fixed $plugin_json"
}

# Main validation loop
cd "$MARKETPLACE_ROOT"

for plugin_name in "sdk-bridge" "taskplex" "storybook-assistant" "claude-project-planner" "nano-banana" "ai-frontier"; do
  plugin_dir=$(get_plugin_dir "$plugin_name")
  plugin_json="$plugin_dir/.claude-plugin/plugin.json"

  echo -e "${BLUE}Validating:${NC} $plugin_name"
  echo "  Path: $plugin_json"

  if [ ! -f "$plugin_json" ]; then
    echo -e "${RED}✗${NC} Plugin manifest not found: $plugin_json"
    ((ERRORS_FOUND++))
    echo ""
    continue
  fi

  # Run validations
  plugin_valid=true

  validate_json_syntax "$plugin_json" "$plugin_name" || plugin_valid=false

  if [ "$plugin_valid" = true ]; then
    validate_required_fields "$plugin_json" "$plugin_name" || plugin_valid=false
    validate_version_format "$plugin_json" "$plugin_name" || plugin_valid=false
    validate_marketplace_sync "$plugin_json" "$plugin_name" || plugin_valid=false

    # Format validations (can be auto-fixed)
    needs_fix=false
    validate_skills_format "$plugin_json" "$plugin_name" "$plugin_dir" || needs_fix=true
    validate_agents_format "$plugin_json" "$plugin_name" "$plugin_dir" || needs_fix=true
    validate_commands_format "$plugin_json" "$plugin_name" "$plugin_dir"

    # Auto-fix if enabled and needed
    if [ "$FIX_MODE" = true ] && [ "$needs_fix" = true ]; then
      auto_fix_paths "$plugin_json" "$plugin_name" "$plugin_dir"
      echo -e "${GREEN}✓${NC} Re-validating after fixes..."
      validate_skills_format "$plugin_json" "$plugin_name" "$plugin_dir"
      validate_agents_format "$plugin_json" "$plugin_name" "$plugin_dir"
    fi
  fi

  if [ "$plugin_valid" = true ]; then
    echo -e "${GREEN}✓${NC} $plugin_name validation passed"
  fi

  echo ""
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

if [ $ERRORS_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
  echo -e "${GREEN}✅ All plugins validated successfully!${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  exit 0
else
  if [ $ERRORS_FOUND -gt 0 ]; then
    echo -e "${RED}❌ Validation failed with $ERRORS_FOUND error(s)${NC}"
  fi
  if [ $WARNINGS_FOUND -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $WARNINGS_FOUND warning(s)${NC}"
  fi
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

  if [ $ERRORS_FOUND -gt 0 ] && [ "$FIX_MODE" = false ]; then
    echo ""
    echo -e "${YELLOW}Tip: Run with --fix to automatically fix common issues:${NC}"
    echo "  ./scripts/validate-plugin-manifests.sh --fix"
  fi

  exit 1
fi
