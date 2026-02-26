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
source "$SCRIPT_DIR/common.sh"
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

# Plugin dir = plugin name (enforced by validator)
get_plugin_dir() {
  echo "$1"
}

# Validation functions

validate_json_syntax() {
  local plugin_json="$1"
  local plugin_name="$2"

  if ! jq empty "$plugin_json" 2>/dev/null; then
    echo -e "${RED}✗${NC} $plugin_name: Invalid JSON syntax"
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
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
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
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
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
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
      ERRORS_FOUND=$((ERRORS_FOUND + 1))
      continue
    fi

    # Check if the path exists
    local skill_path="$MARKETPLACE_ROOT/$plugin_dir/${skill#./}"

    if [ ! -d "$skill_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Skill directory not found: $skill"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
      continue
    fi

    # Check if SKILL.md exists in the directory
    if [ ! -f "$skill_path/SKILL.md" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Missing SKILL.md in $skill"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
      ERRORS_FOUND=$((ERRORS_FOUND + 1))
      continue
    fi

    # Check if it ends with .md
    if [[ ! "$agent" =~ \.md$ ]]; then
      echo -e "${RED}✗${NC} $plugin_name: Agent '$agent' must end with '.md'"
      has_errors=true
      ERRORS_FOUND=$((ERRORS_FOUND + 1))
      continue
    fi

    # Check if the file exists
    local agent_path="$MARKETPLACE_ROOT/$plugin_dir/${agent#./}"

    if [ ! -f "$agent_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Agent file not found: $agent"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
      continue
    fi

    # Check if it ends with .md
    if [[ ! "$command" =~ \.md$ ]]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Command '$command' should end with '.md'"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
      continue
    fi

    # Check if file exists
    local command_path="$MARKETPLACE_ROOT/$plugin_dir/${command#./}"

    if [ ! -f "$command_path" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: Command file not found: $command"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    return 0
  fi

  if [ "$plugin_version" != "$marketplace_version" ]; then
    echo -e "${RED}✗${NC} $plugin_name: Version mismatch - plugin.json: $plugin_version, marketplace.json: $marketplace_version"
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
    return 1
  fi

  return 0
}

validate_hooks_json() {
  local plugin_name="$1"
  local plugin_dir="$2"

  local hooks_json="$MARKETPLACE_ROOT/$plugin_dir/hooks/hooks.json"
  [ ! -f "$hooks_json" ] && return 0

  if ! jq empty "$hooks_json" 2>/dev/null; then
    echo -e "${RED}✗${NC} $plugin_name: hooks/hooks.json is invalid JSON"
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
    return 1
  fi

  # Valid hook events
  local valid_events="PreToolUse PostToolUse PostToolUseFailure Stop Notification SubagentStart SubagentStop TaskCompleted PreCompact SessionStart SessionEnd PermissionRequest TeammateIdle UserPromptSubmit"

  local events
  events=$(jq -r '.hooks | keys[]' "$hooks_json" 2>/dev/null) || true
  for event in $events; do
    if ! echo "$valid_events" | tr ' ' '\n' | grep -qx "$event"; then
      echo -e "${RED}✗${NC} $plugin_name: unknown hook event '$event'"
      ERRORS_FOUND=$((ERRORS_FOUND + 1))
    fi
  done

  # Hook script commands must resolve to existing executables
  local commands
  commands=$(jq -r '.. | objects | .command? // empty' "$hooks_json" 2>/dev/null) || true
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    # Extract the CLAUDE_PLUGIN_ROOT path from the command (may be preceded by interpreter)
    local script_path
    script_path=$(echo "$cmd" | grep -o '\${CLAUDE_PLUGIN_ROOT}/[^ ]*' | head -1 | sed "s|\${CLAUDE_PLUGIN_ROOT}/||")
    [ -z "$script_path" ] && continue  # No plugin-root path (e.g. system command)
    local full="$MARKETPLACE_ROOT/$plugin_dir/$script_path"
    if [ ! -f "$full" ]; then
      echo -e "${RED}✗${NC} $plugin_name: hook script not found: $script_path"
      ERRORS_FOUND=$((ERRORS_FOUND + 1))
    elif [ ! -x "$full" ]; then
      echo -e "${YELLOW}⚠${NC} $plugin_name: hook script not executable: $script_path"
      WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
  done <<< "$commands"

  # SubagentStart/Stop matchers must have matching agent files
  local matchers
  matchers=$(jq -r '.hooks | to_entries[] | select(.key == "SubagentStart" or .key == "SubagentStop") | .value[] | .matcher // empty' "$hooks_json" 2>/dev/null | sort -u) || true
  while IFS= read -r matcher; do
    [ -z "$matcher" ] && continue
    # Matchers can be pipe-separated regex patterns — check each part
    echo "$matcher" | tr '|' '\n' | while IFS= read -r part; do
      [ -z "$part" ] && continue
      local agent_file="$MARKETPLACE_ROOT/$plugin_dir/agents/${part}.md"
      if [ ! -f "$agent_file" ]; then
        echo -e "${RED}✗${NC} $plugin_name: hook matcher '$part' has no agents/${part}.md"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
      fi
    done
  done <<< "$matchers"

  return 0
}

# Extract YAML frontmatter field (awk-based, BSD/macOS compatible)
_get_fm_field() {
  local file="$1" field="$2"
  awk '/^---$/{if(f)exit;f=1;next} f{print}' "$file" 2>/dev/null \
    | grep "^${field}:" \
    | sed "s/^${field}:[[:space:]]*//" \
    | head -1 || true
}

validate_agent_frontmatter() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  local agents
  agents=$(jq -r '.agents[]?' "$plugin_json" 2>/dev/null) || true
  [ -z "$agents" ] && return 0

  local valid_models="sonnet opus haiku inherit"
  local valid_perms="default acceptEdits dontAsk bypassPermissions plan"

  while IFS= read -r agent_path; do
    [ -z "$agent_path" ] && continue
    local full="$MARKETPLACE_ROOT/$plugin_dir/${agent_path#./}"
    [ ! -f "$full" ] && continue

    local agent_name
    agent_name=$(basename "$agent_path" .md)

    # Check required frontmatter fields
    for field in name description model permissionMode; do
      local val
      val=$(_get_fm_field "$full" "$field")
      if [ -z "$val" ]; then
        echo -e "${YELLOW}⚠${NC} $plugin_name: agents/$agent_name missing frontmatter '$field'"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
      fi
    done

    # Validate model enum
    local model_val
    model_val=$(_get_fm_field "$full" "model")
    if [ -n "$model_val" ]; then
      local model_ok=0
      for m in $valid_models; do [ "$model_val" = "$m" ] && model_ok=1 && break; done
      if [ "$model_ok" -eq 0 ]; then
        echo -e "${RED}✗${NC} $plugin_name: agents/$agent_name has invalid model '$model_val'"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
      fi
    fi

    # Validate permissionMode enum
    local perm_val
    perm_val=$(_get_fm_field "$full" "permissionMode")
    if [ -n "$perm_val" ]; then
      local perm_ok=0
      for p in $valid_perms; do [ "$perm_val" = "$p" ] && perm_ok=1 && break; done
      if [ "$perm_ok" -eq 0 ]; then
        echo -e "${RED}✗${NC} $plugin_name: agents/$agent_name has invalid permissionMode '$perm_val'"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
      fi
    fi

    # Validate frontmatter skills list references exist
    local impl_skills
    impl_skills=$(awk '
      /^---$/{if(f)exit;f=1;next}
      f && /^skills:/{s=1;next}
      f && s && /^[a-z]/{s=0}
      f && s && /^  - /{gsub(/^[[:space:]]*-[[:space:]]*/,"");print}
    ' "$full" 2>/dev/null)
    while IFS= read -r skill; do
      [ -z "$skill" ] && continue
      local skill_md="$MARKETPLACE_ROOT/$plugin_dir/skills/$skill/SKILL.md"
      if [ ! -f "$skill_md" ]; then
        echo -e "${RED}✗${NC} $plugin_name: agents/$agent_name references skill '$skill' but skills/$skill/SKILL.md not found"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
      fi
    done <<< "$impl_skills"
  done <<< "$agents"

  return 0
}

validate_skill_frontmatter() {
  local plugin_json="$1"
  local plugin_name="$2"
  local plugin_dir="$3"

  local skills
  skills=$(jq -r '.skills[]?' "$plugin_json" 2>/dev/null) || true
  [ -z "$skills" ] && return 0

  while IFS= read -r skill_path; do
    [ -z "$skill_path" ] && continue
    local skill_md="$MARKETPLACE_ROOT/$plugin_dir/${skill_path#./}/SKILL.md"
    [ ! -f "$skill_md" ] && continue

    local skill_name
    skill_name=$(basename "$skill_path")

    # Check required frontmatter fields
    for field in name description; do
      local val
      val=$(_get_fm_field "$skill_md" "$field")
      if [ -z "$val" ]; then
        echo -e "${YELLOW}⚠${NC} $plugin_name: skills/$skill_name missing frontmatter '$field'"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
      fi
    done
  done <<< "$skills"

  return 0
}

validate_shell_scripts() {
  local plugin_name="$1"
  local plugin_dir="$2"

  local full_dir="$MARKETPLACE_ROOT/$plugin_dir"

  # Find all .sh files in scripts/ and hooks/
  for dir in scripts hooks; do
    local search_dir="$full_dir/$dir"
    [ ! -d "$search_dir" ] && continue

    while IFS= read -r script; do
      [ -z "$script" ] && continue
      local rel="${script#$full_dir/}"
      if ! bash -n "$script" 2>/dev/null; then
        echo -e "${RED}✗${NC} $plugin_name: $rel has syntax errors"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
      fi
    done < <(find "$search_dir" -maxdepth 2 -name "*.sh" -type f -not -path "*/node_modules/*" 2>/dev/null)
  done

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

for plugin_name in $(get_plugins); do
  plugin_dir=$(get_plugin_dir "$plugin_name")
  plugin_json="$plugin_dir/.claude-plugin/plugin.json"

  echo -e "${BLUE}Validating:${NC} $plugin_name"
  echo "  Path: $plugin_json"

  if [ ! -f "$plugin_json" ]; then
    echo -e "${RED}✗${NC} Plugin manifest not found: $plugin_json"
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
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

    # Deep validation: hooks, frontmatter, scripts, cross-refs
    validate_hooks_json "$plugin_name" "$plugin_dir"
    validate_agent_frontmatter "$plugin_json" "$plugin_name" "$plugin_dir"
    validate_skill_frontmatter "$plugin_json" "$plugin_name" "$plugin_dir"
    validate_shell_scripts "$plugin_name" "$plugin_dir"
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
