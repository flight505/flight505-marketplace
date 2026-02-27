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

header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
pass()   { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1"; NOTES+=("FAIL: $1"); }
warn()   { WARN=$((WARN + 1)); echo -e "  ${YELLOW}⚠${NC} $1"; NOTES+=("WARN: $1"); }

should_run() { [ "$SECTION_FILTER" -eq 0 ] || [ "$SECTION_FILTER" -eq "$1" ]; }

VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null)

echo "TaskPlex Test Suite v${VERSION}"
echo "Plugin dir: $PLUGIN_DIR"

# ─── SECTION 1: File Structure ──────────────────────────────────────
if should_run 1; then
header "1. Plugin File Structure"

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
header "2. Plugin Manifest Validation"

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
header "3. Hooks Configuration"

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

# SubagentStart matchers reference real agents
while IFS= read -r matcher; do
  [ -z "$matcher" ] || [ "$matcher" = "null" ] && continue
  # Split pipe-separated matchers
  IFS='|' read -ra parts <<< "$matcher"
  for part in "${parts[@]}"; do
    if [ -f "$PLUGIN_DIR/agents/${part}.md" ]; then
      pass "SubagentStart matcher '$part' → agents/${part}.md exists"
    else
      warn "SubagentStart matcher '$part' has no matching agent file"
    fi
  done
done < <(jq -r '.hooks.SubagentStart[]? | .matcher // empty' "$hooks_file" 2>/dev/null)

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
header "4. Hook Unit Tests"

TEST_DIR="/tmp/taskplex-test-$$"
mkdir -p "$TEST_DIR"
cleanup_test() { rm -rf "$TEST_DIR"; }
trap cleanup_test EXIT

# 4.1 stop-guard.sh
HOOK="$PLUGIN_DIR/hooks/stop-guard.sh"
if [ -f "$HOOK" ]; then
  # No prd.json → allows stop (exit 0)
  cd "$TEST_DIR" && rm -f prd.json
  actual_exit=0
  echo '{"session_id":"test","stop_hook_active":false}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "stop-guard: no prd.json → allows stop"; else fail "stop-guard: no prd.json → got exit $actual_exit"; fi

  # Pending stories → blocks (exit 2)
  cat > "$TEST_DIR/prd.json" <<'PRDEOF'
{"project":"test","userStories":[{"id":"US-001","title":"Test","passes":false}]}
PRDEOF
  actual_exit=0
  echo '{"session_id":"test","stop_hook_active":false}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 2 ]; then pass "stop-guard: pending stories → blocks (exit 2)"; else fail "stop-guard: pending stories → got exit $actual_exit"; fi

  # stop_hook_active=true → allows even with pending (anti-loop)
  actual_exit=0
  echo '{"session_id":"test","stop_hook_active":true}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "stop-guard: stop_hook_active=true → allows (anti-loop)"; else fail "stop-guard: anti-loop → got exit $actual_exit"; fi

  # All passing → allows stop
  cat > "$TEST_DIR/prd.json" <<'PRDEOF'
{"project":"test","userStories":[{"id":"US-001","title":"Test","passes":true}]}
PRDEOF
  actual_exit=0
  echo '{"session_id":"test","stop_hook_active":false}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "stop-guard: all passing → allows stop"; else fail "stop-guard: all passing → got exit $actual_exit"; fi

  rm -f "$TEST_DIR/prd.json"
  cd "$SCRIPT_DIR"
fi

# 4.2 task-completed.sh
HOOK="$PLUGIN_DIR/hooks/task-completed.sh"
if [ -f "$HOOK" ]; then
  cd "$TEST_DIR"
  rm -rf "$TEST_DIR/.claude"

  # No config → allows completion
  actual_exit=0
  echo '{}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "task-completed: no config → allows"; else fail "task-completed: no config → got exit $actual_exit"; fi

  # Passing test → allows
  mkdir -p "$TEST_DIR/.claude"
  printf '{"test_command":"exit 0"}' > "$TEST_DIR/.claude/taskplex.config.json"
  actual_exit=0
  echo '{}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "task-completed: passing test → allows"; else fail "task-completed: passing test → got exit $actual_exit"; fi

  # Failing test → blocks (exit 2)
  printf '{"test_command":"exit 1"}' > "$TEST_DIR/.claude/taskplex.config.json"
  actual_exit=0
  echo '{}' | bash "$HOOK" > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 2 ]; then pass "task-completed: failing test → blocks (exit 2)"; else fail "task-completed: failing test → got exit $actual_exit"; fi

  rm -rf "$TEST_DIR/.claude"
  cd "$SCRIPT_DIR"
fi

# 4.3 session-context.sh
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

# 4.4 inject-knowledge.sh
HOOK="$PLUGIN_DIR/hooks/inject-knowledge.sh"
if [ -f "$HOOK" ]; then
  cd "$TEST_DIR" && rm -f knowledge.db
  actual_exit=0
  output=$(echo '{"agent_type":"implementer","agent_id":"test-1"}' | bash "$HOOK" 2>/dev/null) || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "inject-knowledge: no DB → exits 0"; else fail "inject-knowledge: no DB → got exit $actual_exit"; fi

  # With seeded DB
  sqlite3 "$TEST_DIR/knowledge.db" "
    CREATE TABLE IF NOT EXISTS learnings (id INTEGER PRIMARY KEY AUTOINCREMENT, story_id TEXT, run_id TEXT, content TEXT, tags TEXT, source TEXT DEFAULT 'test', confidence REAL DEFAULT 1.0, created_at INTEGER DEFAULT (strftime('%s','now')));
    INSERT INTO learnings (story_id, run_id, content, tags) VALUES ('US-T', 'run-1', 'Test learning', '[\"test\"]');
  " 2>/dev/null || true

  actual_exit=0
  output2=$(echo '{"agent_type":"implementer","agent_id":"test-2"}' | bash "$HOOK" 2>/dev/null) || actual_exit=$?
  if [ "$actual_exit" -eq 0 ]; then pass "inject-knowledge: with DB → exits 0"; else fail "inject-knowledge: with DB → got exit $actual_exit"; fi

  rm -f "$TEST_DIR/knowledge.db"
  cd "$SCRIPT_DIR"
fi

# 4.5 check-destructive.sh
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

fi

# ─── SECTION 5: Script Unit Tests ───────────────────────────────────
if should_run 5; then
header "5. Script Unit Tests"

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

# 5.2 knowledge-db.sh — source and test key functions
source "$PLUGIN_DIR/scripts/knowledge-db.sh"
TEST_DB="/tmp/taskplex-kdb-test-$$.db"
init_knowledge_db "$TEST_DB"

TABLE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
if [ "$TABLE_COUNT" -eq 6 ]; then pass "knowledge-db: creates 6 tables"; else fail "knowledge-db: expected 6 tables, got $TABLE_COUNT"; fi

insert_learning "$TEST_DB" "US-T" "run-t" "Test learning" '[]'
LEARN_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;")
if [ "$LEARN_COUNT" -eq 1 ]; then pass "knowledge-db: insert_learning works"; else fail "knowledge-db: insert_learning failed"; fi

insert_error "$TEST_DB" "US-T" "run-t" "test_failure" "Test error" 1
ERR_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM error_history;")
if [ "$ERR_COUNT" -eq 1 ]; then pass "knowledge-db: insert_error works"; else fail "knowledge-db: insert_error failed"; fi

resolve_errors "$TEST_DB" "US-T"
RESOLVED=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM error_history WHERE resolved=1;")
if [ "$RESOLVED" -eq 1 ]; then pass "knowledge-db: resolve_errors works"; else fail "knowledge-db: resolve_errors failed"; fi

# Decision insert + query
insert_decision "$TEST_DB" "US-T" "run-t" "implement" "sonnet" "" "First attempt"
DECISION=$(query_decisions "$TEST_DB" "US-T")
if echo "$DECISION" | grep -q "implement|sonnet"; then pass "knowledge-db: insert_decision + query_decisions works"; else fail "knowledge-db: decision query failed"; fi

# Run lifecycle
insert_run "$TEST_DB" "run-t" "taskplex/test" "sequential" "sonnet" 3
update_run "$TEST_DB" "run-t" 2 1
RUN_COMPLETED=$(sqlite3 "$TEST_DB" "SELECT completed FROM runs WHERE id='run-t';")
if [ "$RUN_COMPLETED" = "2" ]; then pass "knowledge-db: run lifecycle works"; else fail "knowledge-db: run lifecycle failed (completed=$RUN_COMPLETED)"; fi

# SQL injection safety (single quotes in content)
insert_learning "$TEST_DB" "US-SQL" "run-t" "Don't use single 'quotes' in SQL" '[]'
SAFE_COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-SQL';")
if [ "$SAFE_COUNT" = "1" ]; then pass "knowledge-db: SQL injection safe (single quotes)"; else fail "knowledge-db: SQL injection safety failed"; fi

# Migration from knowledge.md
KDB_MD="/tmp/taskplex-kdb-md-$$.md"
cat > "$KDB_MD" <<'KDBEOF'
## Codebase Patterns

## Environment Notes

## Recent Learnings
- [US-010] This project uses pnpm for package management
- [US-011] Config files are in src/config/
KDBEOF
KDB_MIGRATE="/tmp/taskplex-kdb-migrate-$$.db"
init_knowledge_db "$KDB_MIGRATE"
migrate_knowledge_md "$KDB_MIGRATE" "$KDB_MD"
MIGRATED=$(sqlite3 "$KDB_MIGRATE" "SELECT COUNT(*) FROM learnings WHERE source='migration';")
if [ "$MIGRATED" = "2" ]; then pass "knowledge-db: migrate_knowledge_md works"; else fail "knowledge-db: migration failed (got $MIGRATED)"; fi
# Idempotency check
migrate_knowledge_md "$KDB_MIGRATE" "$KDB_MD"
MIGRATED2=$(sqlite3 "$KDB_MIGRATE" "SELECT COUNT(*) FROM learnings WHERE source='migration';")
if [ "$MIGRATED2" = "2" ]; then pass "knowledge-db: migration is idempotent"; else fail "knowledge-db: migration not idempotent (got $MIGRATED2)"; fi
rm -f "$KDB_MIGRATE" "$KDB_MD"

rm -f "$TEST_DB"

# 5.2b Bayesian confidence tracking
BAYES_DB="/tmp/taskplex-bayes-test-$$.db"
init_knowledge_db "$BAYES_DB"

# Verify new columns exist
BAYES_COLS=$(sqlite3 "$BAYES_DB" "PRAGMA table_info(learnings);" | grep -c "applied_count\|success_count")
if [ "$BAYES_COLS" -eq 2 ]; then pass "knowledge-db: Bayesian columns (applied_count, success_count) exist"; else fail "knowledge-db: missing Bayesian columns (got $BAYES_COLS)"; fi

# Insert learning and test application tracking
insert_learning "$BAYES_DB" "US-B1" "run-b" "Bayesian test learning" '["US-B1"]'
BAYES_ID=$(sqlite3 "$BAYES_DB" "SELECT id FROM learnings WHERE story_id='US-B1' LIMIT 1;")
record_learning_application "$BAYES_DB" "$BAYES_ID"
APPLIED=$(sqlite3 "$BAYES_DB" "SELECT applied_count FROM learnings WHERE id=$BAYES_ID;")
if [ "$APPLIED" = "1" ]; then pass "knowledge-db: record_learning_application increments count"; else fail "knowledge-db: applied_count expected 1, got $APPLIED"; fi

# Test success tracking
record_learning_success "$BAYES_DB" "US-B1"
SUCCESS=$(sqlite3 "$BAYES_DB" "SELECT success_count FROM learnings WHERE id=$BAYES_ID;")
if [ "$SUCCESS" = "1" ]; then pass "knowledge-db: record_learning_success increments count"; else fail "knowledge-db: success_count expected 1, got $SUCCESS"; fi

# Test Bayesian formula: with applied_count < 2, should use time-decay
# (fresh learning = time-decay ≈ 1.0)
DECAY_CONF=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CASE WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2) ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at)) END, 3) FROM learnings WHERE id=$BAYES_ID;")
if [ "$DECAY_CONF" = "1.0" ] || [ "$DECAY_CONF" = "1.000" ]; then
  pass "knowledge-db: Bayesian fallback to time-decay when applied_count < 2"
else
  fail "knowledge-db: Bayesian time-decay expected ~1.0, got $DECAY_CONF"
fi

# Apply again to trigger Bayesian mode (applied_count=2)
record_learning_application "$BAYES_DB" "$BAYES_ID"
APPLIED2=$(sqlite3 "$BAYES_DB" "SELECT applied_count FROM learnings WHERE id=$BAYES_ID;")
if [ "$APPLIED2" = "2" ]; then pass "knowledge-db: applied_count incremented to 2"; else fail "knowledge-db: applied_count expected 2, got $APPLIED2"; fi

# Now Bayesian formula: (1+1)/(2+2) = 0.5
BAYES_CONF=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CASE WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2) ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at)) END, 3) FROM learnings WHERE id=$BAYES_ID;")
if [ "$BAYES_CONF" = "0.5" ] || [ "$BAYES_CONF" = "0.500" ]; then
  pass "knowledge-db: Bayesian confidence = (1+1)/(2+2) = 0.5"
else
  fail "knowledge-db: Bayesian confidence expected 0.5, got $BAYES_CONF"
fi

# Record another success → (2+1)/(2+2) = 0.75
record_learning_success "$BAYES_DB" "US-B1"
BAYES_CONF2=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CASE WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2) ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at)) END, 3) FROM learnings WHERE id=$BAYES_ID;")
if [ "$BAYES_CONF2" = "0.75" ] || [ "$BAYES_CONF2" = "0.750" ]; then
  pass "knowledge-db: Bayesian confidence = (2+1)/(2+2) = 0.75"
else
  fail "knowledge-db: Bayesian confidence expected 0.75, got $BAYES_CONF2"
fi

# Test query_learnings_with_ids returns id column
RESULT_WITH_IDS=$(query_learnings_with_ids "$BAYES_DB" 10 '["US-B1"]')
if echo "$RESULT_WITH_IDS" | grep -q "^${BAYES_ID}|"; then
  pass "knowledge-db: query_learnings_with_ids returns id column"
else
  fail "knowledge-db: query_learnings_with_ids missing id column"
fi

rm -f "$BAYES_DB"

# 5.3 decision-call.sh — source and check function definitions
if [ -f "$PLUGIN_DIR/scripts/decision-call.sh" ]; then
  # Just syntax check — functions need runtime context
  if bash -n "$PLUGIN_DIR/scripts/decision-call.sh" 2>/dev/null; then
    pass "decision-call.sh: syntax OK"
  else
    fail "decision-call.sh: syntax errors"
  fi
fi

fi

# ─── SECTION 6: Agent Spec Quality ──────────────────────────────────
if should_run 6; then
header "6. Agent Spec Quality"

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
header "7. Skill Quality"

for skill_dir in "$PLUGIN_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"

  # SKILL.md exists
  if [ -f "$skill_file" ]; then
    pass "skill $name: SKILL.md exists"
  else
    fail "skill $name: SKILL.md MISSING"
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
header "8. Cross-References"

manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"

# 8.1 plugin.json skills → skill directories exist
while IFS= read -r skill; do
  skill_path="${skill#./}"
  if [ -d "$PLUGIN_DIR/$skill_path" ]; then
    pass "xref: plugin.json skill '$skill_path' → directory exists"
  else
    fail "xref: plugin.json skill '$skill_path' → directory MISSING"
  fi
done < <(jq -r '.skills[]' "$manifest" 2>/dev/null)

# 8.2 plugin.json agents → agent files exist
while IFS= read -r agent; do
  agent_path="${agent#./}"
  if [ -f "$PLUGIN_DIR/$agent_path" ]; then
    pass "xref: plugin.json agent '$agent_path' → file exists"
  else
    fail "xref: plugin.json agent '$agent_path' → file MISSING"
  fi
done < <(jq -r '.agents[]' "$manifest" 2>/dev/null)

# 8.3 Agent skills → skill directories exist
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

# 8.4 hooks.json SubagentStart/Stop matchers → agent files
for event in SubagentStart SubagentStop; do
  while IFS= read -r matcher; do
    [ -z "$matcher" ] || [ "$matcher" = "null" ] && continue
    IFS='|' read -ra parts <<< "$matcher"
    for part in "${parts[@]}"; do
      if [ -f "$PLUGIN_DIR/agents/${part}.md" ]; then
        pass "xref: hooks $event matcher '$part' → agent file exists"
      else
        fail "xref: hooks $event matcher '$part' → agent file MISSING"
      fi
    done
  done < <(jq -r ".hooks.${event}[]? | .matcher // empty" "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)
done

# 8.5 Skill directories on disk → referenced in plugin.json
for skill_dir in "$PLUGIN_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if jq -r '.skills[]' "$manifest" 2>/dev/null | grep -q "$skill_name"; then
    pass "xref: skill dir '$skill_name' → referenced in plugin.json"
  else
    warn "xref: skill dir '$skill_name' → NOT in plugin.json (orphaned?)"
  fi
done

# 8.6 Agent files on disk → referenced in plugin.json
for agent_file in "$PLUGIN_DIR"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file")
  if jq -r '.agents[]' "$manifest" 2>/dev/null | grep -q "$agent_name"; then
    pass "xref: agent '$agent_name' → referenced in plugin.json"
  else
    warn "xref: agent '$agent_name' → NOT in plugin.json (orphaned?)"
  fi
done

fi

# ─── Summary ────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━ Summary ━━━${NC}"
TOTAL=$((PASS + FAIL + WARN))
SCORE=0
if [ "$TOTAL" -gt 0 ]; then
  # pass=1, warn=0.5, fail=0
  SCORE_NUM=$((PASS * 100 + WARN * 50))
  SCORE=$((SCORE_NUM / TOTAL))
fi

echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warned:${NC} $WARN"
echo "  Total:   $TOTAL"
echo "  Score:   ${SCORE}%"

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
  RECORD=$(jq -n \
    --arg ts "$TIMESTAMP" \
    --arg version "$VERSION" \
    --arg sha "$GIT_SHA" \
    --argjson pass "$PASS" \
    --argjson fail "$FAIL" \
    --argjson warn "$WARN" \
    --argjson total "$TOTAL" \
    --argjson score "$SCORE" \
    '{timestamp: $ts, version: $version, git_sha: $sha, passed: $pass, failed: $fail, warned: $warn, total: $total, score: $score}')

  echo "$RECORD" >> "$RESULTS_DIR/test-history.jsonl"
  echo ""
  echo "Results saved to $RESULTS_DIR/test-history.jsonl"
fi

# CI output
if [ "$CI" = true ]; then
  jq -n \
    --arg version "$VERSION" \
    --argjson pass "$PASS" \
    --argjson fail "$FAIL" \
    --argjson warn "$WARN" \
    --argjson total "$TOTAL" \
    --argjson score "$SCORE" \
    '{version: $version, passed: $pass, failed: $fail, warned: $warn, total: $total, score: $score}'
fi

# Exit code
if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
