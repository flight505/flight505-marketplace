#!/bin/bash
# TaskPlex plugin test suite — 8 sections, pure bash + jq, no API calls
# Usage: ./run-tests.sh [--save] [--ci] [--section N]
# --save   Append JSONL record to test-history.jsonl
# --ci     No colors, JSON summary to stdout
# --section N  Run only section N (1-8)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../../taskplex" && pwd)"
RESULTS_DIR="$SCRIPT_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PASS=0
FAIL=0
WARN=0
NOTES=()

# Per-section tracking
SEC_NAME=""
SEC_PASS=0
SEC_FAIL=0
SEC_WARN=0
SEC_NAMES=()
SEC_PASSES=()
SEC_FAILS=()
SEC_WARNS=()

# Flags
SAVE=false
CI=false
SECTION_FILTER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --save) SAVE=true; shift ;;
    --ci) CI=true; shift ;;
    --section) SECTION_FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Colors (disabled in CI mode)
if [ "$CI" = true ]; then
  GREEN="" RED="" YELLOW="" CYAN="" NC=""
else
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
fi

flush_section() {
  if [ -n "$SEC_NAME" ]; then
    SEC_NAMES+=("$SEC_NAME")
    SEC_PASSES+=("$SEC_PASS")
    SEC_FAILS+=("$SEC_FAIL")
    SEC_WARNS+=("$SEC_WARN")
  fi
  SEC_NAME=""
  SEC_PASS=0
  SEC_FAIL=0
  SEC_WARN=0
}

header() {
  flush_section
  SEC_NAME="$2"
  echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

pass()   { PASS=$((PASS + 1)); SEC_PASS=$((SEC_PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { FAIL=$((FAIL + 1)); SEC_FAIL=$((SEC_FAIL + 1)); echo -e "  ${RED}✗${NC} $1"; NOTES+=("FAIL: $1"); }
warn()   { WARN=$((WARN + 1)); SEC_WARN=$((SEC_WARN + 1)); echo -e "  ${YELLOW}⚠${NC} $1"; NOTES+=("WARN: $1"); }

should_run() { [ "$SECTION_FILTER" -eq 0 ] || [ "$SECTION_FILTER" -eq "$1" ]; }

# Helper: run a hook script and check exit code
# Args: $1=description, $2=hook_path, $3=stdin_input, $4=expected_exit, $5=cwd (optional)
run_hook() {
  local desc="$1" hook="$2" input="$3" expected_exit="$4" cwd="${5:-$(pwd)}"
  local actual_exit=0
  echo "$input" | (cd "$cwd" && bash "$hook") > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    pass "$desc"
  else
    fail "$desc (exit $actual_exit, expected $expected_exit)"
  fi
}

VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null)

echo "TaskPlex Test Suite v${VERSION}"
echo "Plugin dir: $PLUGIN_DIR"

# ─── SECTION 1: File Structure ──────────────────────────────────────
if should_run 1; then
header "1. Plugin File Structure" "file_structure"

# Check all files referenced in plugin.json exist
manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"

# Commands
while IFS= read -r cmd; do
  cmd_path="${cmd#./}"
  if [ -f "$PLUGIN_DIR/$cmd_path" ]; then
    pass "command: $cmd_path exists"
  else
    fail "command: $cmd_path MISSING"
  fi
done < <(jq -r '.commands[]' "$manifest" 2>/dev/null)

# Skills — each entry should have SKILL.md
while IFS= read -r skill; do
  skill_path="${skill#./}"
  if [ -f "$PLUGIN_DIR/$skill_path/SKILL.md" ]; then
    pass "skill: $skill_path/SKILL.md exists"
  else
    fail "skill: $skill_path/SKILL.md MISSING"
  fi
done < <(jq -r '.skills[]' "$manifest" 2>/dev/null)

# Agents
while IFS= read -r agent; do
  agent_path="${agent#./}"
  if [ -f "$PLUGIN_DIR/$agent_path" ]; then
    pass "agent: $agent_path exists"
  else
    fail "agent: $agent_path MISSING"
  fi
done < <(jq -r '.agents[]' "$manifest" 2>/dev/null)

# Core files
for f in CLAUDE.md README.md hooks/hooks.json .claude-plugin/plugin.json; do
  if [ -f "$PLUGIN_DIR/$f" ]; then
    pass "$f exists"
  else
    fail "$f MISSING"
  fi
done

# Hook scripts referenced in hooks.json must exist
while IFS= read -r cmd_path; do
  # Resolve ${CLAUDE_PLUGIN_ROOT} to plugin dir
  resolved="${cmd_path//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
  # Strip arguments after script path
  script_file=$(echo "$resolved" | awk '{print $1}')
  if [ -f "$script_file" ]; then
    pass "hook script: $(basename "$script_file") exists"
  else
    fail "hook script: $script_file MISSING"
  fi
done < <(jq -r '.. | objects | .command // empty' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)

fi

# ─── SECTION 2: Plugin Manifest ─────────────────────────────────────
if should_run 2; then
header "2. Plugin Manifest Validation" "manifest"

manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"

# Valid JSON
if jq empty "$manifest" 2>/dev/null; then
  pass "plugin.json is valid JSON"
else
  fail "plugin.json is INVALID JSON"
fi

# Required fields
for field in name version description author license repository skills agents commands; do
  if jq -e ".$field" "$manifest" >/dev/null 2>&1; then
    pass "Field '$field' present"
  else
    fail "Field '$field' missing"
  fi
done

# Author structure
if jq -e '.author.name and .author.url' "$manifest" >/dev/null 2>&1; then
  pass "Author has name and url"
else
  fail "Author must have {name, url} structure"
fi

# Semver check
version=$(jq -r '.version' "$manifest")
if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  pass "Version '$version' is valid semver"
else
  fail "Version '$version' is not valid semver"
fi

# No 'hooks' field (auto-discovered)
if jq -e '.hooks' "$manifest" >/dev/null 2>&1; then
  fail "plugin.json should NOT have 'hooks' field (auto-discovered)"
else
  pass "No 'hooks' field (correctly auto-discovered)"
fi

# Skills paths start with ./
skills_ok=true
while IFS= read -r skill; do
  if [ "${skill:0:2}" != "./" ]; then
    fail "Skill path '$skill' doesn't start with ./"
    skills_ok=false
  fi
done < <(jq -r '.skills[]' "$manifest" 2>/dev/null)
$skills_ok && pass "All skill paths start with ./"

# Agent paths start with ./ and end with .md
agents_ok=true
while IFS= read -r agent; do
  if [ "${agent:0:2}" != "./" ]; then
    fail "Agent path '$agent' doesn't start with ./"
    agents_ok=false
  fi
  case "$agent" in
    *.md) ;;
    *) fail "Agent path '$agent' doesn't end with .md"; agents_ok=false ;;
  esac
done < <(jq -r '.agents[]' "$manifest" 2>/dev/null)
$agents_ok && pass "All agent paths start with ./ and end with .md"

fi

# ─── SECTION 3: Hooks Configuration ─────────────────────────────────
if should_run 3; then
header "3. Hooks Configuration" "hooks_config"

hooks_file="$PLUGIN_DIR/hooks/hooks.json"

# Valid JSON
if jq empty "$hooks_file" 2>/dev/null; then
  pass "hooks.json is valid JSON"
else
  fail "hooks.json is INVALID JSON"
fi

# Valid hook events
valid_events="PreToolUse PostToolUse PostToolUseFailure PermissionRequest UserPromptSubmit Notification Stop SubagentStart SubagentStop SessionStart SessionEnd TeammateIdle TaskCompleted PreCompact"
while IFS= read -r event; do
  if echo "$valid_events" | grep -qw "$event"; then
    pass "Hook event '$event' is valid"
  else
    fail "Hook event '$event' is NOT a valid Claude Code event"
  fi
done < <(jq -r '.hooks | keys[]' "$hooks_file" 2>/dev/null)

# Hook scripts are executable (non-async ones)
while IFS= read -r cmd_path; do
  resolved="${cmd_path//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
  script_file=$(echo "$resolved" | awk '{print $1}')
  if [ -f "$script_file" ] && [ -x "$script_file" ]; then
    pass "$(basename "$script_file") is executable"
  elif [ -f "$script_file" ]; then
    warn "$(basename "$script_file") exists but is NOT executable"
  fi
done < <(jq -r '.. | objects | .command // empty' "$hooks_file" 2>/dev/null)

# SubagentStop matchers reference real agents
while IFS= read -r matcher; do
  [ -z "$matcher" ] || [ "$matcher" = "null" ] && continue
  IFS='|' read -ra parts <<< "$matcher"
  for part in "${parts[@]}"; do
    if [ -f "$PLUGIN_DIR/agents/${part}.md" ]; then
      pass "SubagentStop matcher '$part' → agents/${part}.md exists"
    else
      warn "SubagentStop matcher '$part' has no matching agent file"
    fi
  done
done < <(jq -r '.hooks.SubagentStop[]? | .matcher // empty' "$hooks_file" 2>/dev/null)

# Sync hooks must have statusMessage and timeout
while IFS= read -r entry; do
  name=$(echo "$entry" | jq -r '.name')
  has_msg=$(echo "$entry" | jq -r '.has_status')
  has_timeout=$(echo "$entry" | jq -r '.has_timeout')
  is_async=$(echo "$entry" | jq -r '.is_async')

  if [ "$is_async" = "true" ]; then
    continue  # async hooks don't need statusMessage/timeout
  fi

  if [ "$has_msg" = "true" ]; then
    pass "Hook '$name' has statusMessage"
  else
    warn "Hook '$name' missing statusMessage"
  fi

  if [ "$has_timeout" = "true" ]; then
    pass "Hook '$name' has timeout"
  else
    warn "Hook '$name' missing timeout"
  fi
done < <(jq -r '
  .hooks | to_entries[] |
  .key as $event |
  .value[] | .hooks[]? |
  {
    name: ($event + " → " + (.command | split("/") | last | split(" ")[0])),
    has_status: (has("statusMessage")),
    has_timeout: (has("timeout")),
    is_async: (.async // false)
  } | @json
' "$hooks_file" 2>/dev/null)

fi

# ─── SECTION 4: Hook Unit Tests ──────────────────────────────────────
if should_run 4; then
header "4. Hook Unit Tests" "hook_unit_tests"

TEST_DIR="/tmp/taskplex-test-$$"
mkdir -p "$TEST_DIR"
cleanup_test() { rm -rf "$TEST_DIR"; }
trap cleanup_test EXIT

# 4.1 session-context.sh
HOOK="$PLUGIN_DIR/hooks/session-context.sh"
if [ -f "$HOOK" ]; then
  cd "$TEST_DIR"
  actual_exit=0
  output=$(echo '{"type":"startup"}' | bash "$HOOK" 2>/dev/null) || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "session-context: exits 0"; else fail "session-context: got exit $actual_exit"; fi

  if echo "$output" | jq . > /dev/null 2>&1; then
    pass "session-context: valid JSON output"
  else
    fail "session-context: invalid JSON output"
  fi

  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
  if [ -n "$ctx" ]; then
    pass "session-context: additionalContext non-empty"
  else
    fail "session-context: additionalContext empty"
  fi

  if echo "$ctx" | grep -qi "taskplex"; then
    pass "session-context: mentions TaskPlex"
  else
    warn "session-context: no TaskPlex reference in context"
  fi

  cd "$SCRIPT_DIR"
fi

# 4.2 check-destructive.sh
HOOK="$PLUGIN_DIR/scripts/check-destructive.sh"
if [ -f "$HOOK" ]; then
  # git push --force → deny
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash "$HOOK" 2>/dev/null)
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
  if [ "$decision" = "deny" ]; then pass "check-destructive: git push --force → denied"; else fail "check-destructive: git push --force → '$decision'"; fi

  # git reset --hard → deny
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}' | bash "$HOOK" 2>/dev/null)
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
  if [ "$decision" = "deny" ]; then pass "check-destructive: git reset --hard → denied"; else fail "check-destructive: git reset --hard → '$decision'"; fi

  # git push origin main → deny
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | bash "$HOOK" 2>/dev/null)
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
  if [ "$decision" = "deny" ]; then pass "check-destructive: push origin main → denied"; else fail "check-destructive: push origin main → '$decision'"; fi

  # git push --force-with-lease → allow
  exit_code=0
  echo '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}' | bash "$HOOK" > /dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then pass "check-destructive: --force-with-lease → allowed"; else fail "check-destructive: --force-with-lease → exit $exit_code"; fi

  # git status → allow
  exit_code=0
  echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOOK" > /dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then pass "check-destructive: git status → allowed"; else fail "check-destructive: git status → exit $exit_code"; fi

  # git push origin feature-branch → allow
  output=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin feature-branch"}}' | bash "$HOOK" 2>/dev/null)
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  if [ "$decision" != "deny" ]; then pass "check-destructive: push feature-branch → allowed"; else fail "check-destructive: push feature-branch → denied"; fi
fi

# 4.3 validate-result.sh
HOOK="$PLUGIN_DIR/hooks/validate-result.sh"
if [ -f "$HOOK" ]; then
  cd "$TEST_DIR"
  rm -rf "$TEST_DIR/.claude"

  # Non-implementer → exits 0
  run_hook "validate-result: non-implementer → allows" "$HOOK" \
    '{"agent_type":"reviewer","stop_hook_active":false}' 0 "$TEST_DIR"

  # stop_hook_active=true → exits 0 (anti-loop)
  run_hook "validate-result: stop_hook_active=true → allows (anti-loop)" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":true}' 0 "$TEST_DIR"

  # No config → exits 0
  run_hook "validate-result: no config → allows" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 0 "$TEST_DIR"

  # Passing test → allows
  mkdir -p "$TEST_DIR/.claude"
  printf '{"test_command":"exit 0"}' > "$TEST_DIR/.claude/taskplex.config.json"
  run_hook "validate-result: passing test → allows" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 0 "$TEST_DIR"

  # Failing test → blocks (exit 2)
  printf '{"test_command":"exit 1"}' > "$TEST_DIR/.claude/taskplex.config.json"
  run_hook "validate-result: failing test → blocks (exit 2)" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 2 "$TEST_DIR"

  rm -rf "$TEST_DIR/.claude"
  cd "$SCRIPT_DIR"
fi

fi

# ─── SECTION 5: Script Unit Tests ───────────────────────────────────
if should_run 5; then
header "5. Script Unit Tests" "script_unit_tests"

# 5.1 bash -n syntax check on all .sh files
for script in "$PLUGIN_DIR"/scripts/*.sh "$PLUGIN_DIR"/hooks/*.sh; do
  [ -f "$script" ] || continue
  name=$(basename "$script")
  if bash -n "$script" 2>/dev/null; then
    pass "syntax: $name"
  else
    fail "syntax: $name has errors"
  fi
done

# 5.2 check-deps.sh — verify it runs and checks for claude + jq
if [ -f "$PLUGIN_DIR/scripts/check-deps.sh" ]; then
  exit_code=0
  output=$(bash "$PLUGIN_DIR/scripts/check-deps.sh" 2>&1) || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass "check-deps: all dependencies found"
  else
    warn "check-deps: missing deps: $output"
  fi
fi

fi

# ─── SECTION 6: Agent Spec Quality ──────────────────────────────────
if should_run 6; then
header "6. Agent Spec Quality" "agent_spec_quality"

valid_models="sonnet opus haiku inherit"
valid_permissions="default acceptEdits dontAsk bypassPermissions plan"

for agent_file in "$PLUGIN_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  name=$(basename "$agent_file" .md)

  # Extract YAML frontmatter (between first and second ---)
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent_file" | sed '1d;$d')

  # Required frontmatter fields
  for field in name description model permissionMode; do
    if echo "$frontmatter" | grep -q "^${field}:"; then
      pass "agent $name: has '$field'"
    else
      fail "agent $name: missing '$field'"
    fi
  done

  # Model validation
  model=$(echo "$frontmatter" | grep '^model:' | awk '{print $2}')
  if echo "$valid_models" | grep -qw "$model"; then
    pass "agent $name: model '$model' is valid"
  else
    fail "agent $name: model '$model' is not a valid model"
  fi

  # permissionMode validation
  perm=$(echo "$frontmatter" | grep '^permissionMode:' | awk '{print $2}')
  if echo "$valid_permissions" | grep -qw "$perm"; then
    pass "agent $name: permissionMode '$perm' is valid"
  else
    fail "agent $name: permissionMode '$perm' is not valid"
  fi

  # Word count > 200 (after frontmatter)
  word_count=$(awk 'BEGIN{n=0;f=0}/^---$/{n++;if(n==2){f=1;next}}f{print}' "$agent_file" | wc -w | tr -d ' ')
  if [ "$word_count" -gt 200 ]; then
    pass "agent $name: body has $word_count words (>200)"
  else
    warn "agent $name: body has only $word_count words (<200)"
  fi
done

fi

# ─── SECTION 7: Skill Quality ───────────────────────────────────────
if should_run 7; then
header "7. Skill Quality" "skill_quality"

for skill_dir in "$PLUGIN_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"

  # Skip if SKILL.md missing (already caught by Section 1)
  if [ ! -f "$skill_file" ]; then
    continue
  fi

  # Extract frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_file" | sed '1d;$d')

  # Required: name
  if echo "$frontmatter" | grep -q "^name:"; then
    pass "skill $name: has 'name'"
  else
    fail "skill $name: missing 'name' in frontmatter"
  fi

  # Required: description
  if echo "$frontmatter" | grep -q "^description:"; then
    pass "skill $name: has 'description'"
  else
    fail "skill $name: missing 'description' in frontmatter"
  fi

  # Word count > 100 (after frontmatter)
  word_count=$(awk 'BEGIN{n=0;f=0}/^---$/{n++;if(n==2){f=1;next}}f{print}' "$skill_file" | wc -w | tr -d ' ')
  if [ "$word_count" -gt 100 ]; then
    pass "skill $name: body has $word_count words (>100)"
  else
    warn "skill $name: body has only $word_count words (<100)"
  fi
done

fi

# ─── SECTION 8: Cross-References ────────────────────────────────────
if should_run 8; then
header "8. Cross-References" "cross_references"

manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"

# 8.1 Agent skills → skill directories exist
for agent_file in "$PLUGIN_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file" .md)
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$agent_file" | sed '1d;$d')

  # Extract skills list from frontmatter (handles YAML list format)
  skills_line=$(echo "$frontmatter" | grep -A 10 '^skills:' 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    case "$line" in
      "  - "*) echo "${line#  - }" ;;
      *) break ;;
    esac
  done || true)

  if [ -n "$skills_line" ]; then
    while IFS= read -r skill; do
      [ -z "$skill" ] && continue
      if [ -d "$PLUGIN_DIR/skills/$skill" ]; then
        pass "xref: agent $agent_name skill '$skill' → directory exists"
      else
        fail "xref: agent $agent_name skill '$skill' → directory MISSING"
      fi
    done <<< "$skills_line"
  fi
done

# 8.2 Skill directories on disk → referenced in plugin.json (exact path match)
for skill_dir in "$PLUGIN_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if jq -r '.skills[]' "$manifest" 2>/dev/null | grep -q "/$skill_name$"; then
    pass "xref: skill dir '$skill_name' → referenced in plugin.json"
  else
    warn "xref: skill dir '$skill_name' → NOT in plugin.json (orphaned?)"
  fi
done

# 8.3 Agent files on disk → referenced in plugin.json (exact path match)
for agent_file in "$PLUGIN_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file")
  if jq -r '.agents[]' "$manifest" 2>/dev/null | grep -q "/$agent_name"; then
    pass "xref: agent '$agent_name' → referenced in plugin.json"
  else
    warn "xref: agent '$agent_name' → NOT in plugin.json (orphaned?)"
  fi
done

fi

# ─── Summary ────────────────────────────────────────────────────────
flush_section

echo ""
echo -e "${CYAN}━━━ Summary ━━━${NC}"
TOTAL=$((PASS + FAIL + WARN))
SCORE=0
if [ "$TOTAL" -gt 0 ]; then
  # pass=1, warn=0.5, fail=0
  SCORE_NUM=$((PASS * 100 + WARN * 50))
  SCORE=$((SCORE_NUM / TOTAL))
fi

# Three-tier overall
if [ "$FAIL" -eq 0 ]; then
  OVERALL="PASS"
elif [ "$FAIL" -le 3 ]; then
  OVERALL="PASS_WITH_ISSUES"
else
  OVERALL="FAIL"
fi

echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warned:${NC} $WARN"
echo "  Total:   $TOTAL"
echo "  Score:   ${SCORE}%"
echo "  Overall: $OVERALL"

if [ ${#NOTES[@]} -gt 0 ]; then
  echo ""
  echo "Notes:"
  for note in "${NOTES[@]}"; do
    echo "  - $note"
  done
fi

# Save results
if [ "$SAVE" = true ]; then
  GIT_SHA=$(git -C "$PLUGIN_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

  # Build sections JSON
  SECTIONS_OBJ="{}"
  for i in "${!SEC_NAMES[@]}"; do
    SECTIONS_OBJ=$(echo "$SECTIONS_OBJ" | jq \
      --arg name "${SEC_NAMES[$i]}" \
      --argjson p "${SEC_PASSES[$i]}" \
      --argjson f "${SEC_FAILS[$i]}" \
      --argjson w "${SEC_WARNS[$i]}" \
      '. + {($name): {pass: $p, fail: $f, warn: $w}}')
  done

  # Build notes JSON array
  NOTES_JSON="[]"
  for note in "${NOTES[@]}"; do
    NOTES_JSON=$(echo "$NOTES_JSON" | jq --arg n "$note" '. + [$n]')
  done

  RECORD=$(jq -cn \
    --arg ts "$TIMESTAMP" \
    --arg suite "structural" \
    --arg plugin "taskplex" \
    --arg version "$VERSION" \
    --arg sha "$GIT_SHA" \
    --arg overall "$OVERALL" \
    --argjson pass "$PASS" \
    --argjson fail "$FAIL" \
    --argjson warn "$WARN" \
    --argjson total "$TOTAL" \
    --argjson score "$SCORE" \
    --argjson sections "$SECTIONS_OBJ" \
    --argjson notes "$NOTES_JSON" \
    '{timestamp: $ts, suite: $suite, plugin: $plugin, version: $version, git_sha: $sha, overall: $overall, passed: $pass, failed: $fail, warned: $warn, total: $total, score: $score, sections: $sections, notes: $notes}')

  echo "$RECORD" >> "$RESULTS_DIR/test-history.jsonl"
  echo ""
  echo "Results saved to $RESULTS_DIR/test-history.jsonl"
fi

# CI output
if [ "$CI" = true ]; then
  jq -n \
    --arg version "$VERSION" \
    --arg overall "$OVERALL" \
    --argjson pass "$PASS" \
    --argjson fail "$FAIL" \
    --argjson warn "$WARN" \
    --argjson total "$TOTAL" \
    --argjson score "$SCORE" \
    '{version: $version, overall: $overall, passed: $pass, failed: $fail, warned: $warn, total: $total, score: $score}'
fi

# Exit code
if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
