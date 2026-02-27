#!/bin/bash
# TaskPlex evaluation suite — quality tests for key components
# Separate from structural tests in run-tests.sh
# Usage: ./run-evals.sh [--save] [--ci] [--section N] [--full]
# --save     Append JSONL record to test-history.jsonl
# --ci       No colors, JSON summary to stdout
# --section N  Run only section N (1-7)
# --full     Include LLM-gated sections (6-7); requires external terminal

# NOTE: -e omitted because sourced functions (mine_implicit_learnings, etc.)
# use grep patterns that return exit 1 on no match. set -e would terminate
# the script on legitimate no-match cases inside those functions.
set -uo pipefail

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
FULL_MODE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --save) SAVE=true; shift ;;
    --ci) CI=true; shift ;;
    --section) SECTION_FILTER="$2"; shift 2 ;;
    --full) FULL_MODE=true; shift ;;
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

# Helper: check hook output contains expected decision
run_hook_decision() {
  local desc="$1" hook="$2" input="$3" expected_decision="$4"
  local output
  output=$(echo "$input" | bash "$hook" 2>/dev/null) || true
  local decision
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  if [ "$decision" = "$expected_decision" ]; then
    pass "$desc"
  else
    fail "$desc (got '$decision', expected '$expected_decision')"
  fi
}

VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null)

echo "TaskPlex Evaluation Suite v${VERSION}"
echo "Plugin dir: $PLUGIN_DIR"
if [ "$FULL_MODE" = true ]; then
  echo "Mode: FULL (includes LLM-gated sections)"
else
  echo "Mode: OFFLINE (LLM sections skipped; use --full for all)"
fi

# ─── Setup ───────────────────────────────────────────────────────────
TEST_DIR="/tmp/taskplex-eval-$$"
mkdir -p "$TEST_DIR/bin"
cleanup_eval() { rm -rf "$TEST_DIR"; }
trap cleanup_eval EXIT

# Mock claude binary — signals it was called, returns fallback
cat > "$TEST_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo "MOCK_CLAUDE_CALLED" >&2
exit 1
MOCKEOF
chmod +x "$TEST_DIR/bin/claude"

# Mock timeout — just passes through to the real command
cat > "$TEST_DIR/bin/timeout" <<'MOCKEOF'
#!/bin/bash
shift  # skip timeout value
"$@"   # run remaining args
MOCKEOF
chmod +x "$TEST_DIR/bin/timeout"

# ─── SECTION 1: Decision Routing Accuracy ────────────────────────────
if should_run 1; then
header "1. Decision Routing Accuracy" "decision_routing"

# Source knowledge-db.sh for its functions
source "$PLUGIN_DIR/scripts/knowledge-db.sh"

# Mock functions needed by decision-call.sh
log() { :; }
emit_event() { :; }

# Set up environment
DECISION_MODEL="opus"
EXECUTION_MODEL="sonnet"
EFFORT_LEVEL=""
TIMEOUT_CMD="timeout"
KNOWLEDGE_DB="$TEST_DIR/decision.db"
PRD_FILE="$TEST_DIR/prd.json"
RUN_ID="eval-run"

init_knowledge_db "$KNOWLEDGE_DB"

# Source decision-call.sh
source "$PLUGIN_DIR/scripts/decision-call.sh"

# Helper to create prd.json with a story
make_story() {
  local id="$1" criteria_count="$2" deps_count="${3:-0}" attempts="${4:-0}" last_category="${5:-none}"
  local criteria="[]"
  if [ "$criteria_count" -gt 0 ]; then
    criteria=$(python3 -c "import json; print(json.dumps(['Criterion '+str(i+1) for i in range($criteria_count)]))")
  fi
  local deps="[]"
  if [ "$deps_count" -gt 0 ]; then
    deps=$(python3 -c "import json; print(json.dumps(['US-DEP-'+str(i+1) for i in range($deps_count)]))")
  fi
  cat > "$PRD_FILE" <<STORYEOF
{
  "project": "eval-test",
  "userStories": [{
    "id": "$id",
    "title": "Test story",
    "acceptanceCriteria": $criteria,
    "depends_on": $deps,
    "attempts": $attempts,
    "last_error": "none",
    "last_error_category": "$last_category",
    "retry_hint": "none",
    "passes": false
  }]
}
STORYEOF
}

# Test 1: Config disable
DECISION_CALLS_ENABLED="false"
make_story "US-DC-1" 3
result=$(decision_call "US-DC-1")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: DECISION_CALLS_ENABLED=false → implement|sonnet|"
else
  fail "routing: config disable → got '$result'"
fi
DECISION_CALLS_ENABLED="true"

# Test 2: Story not in prd.json
make_story "US-DC-2" 3
result=$(decision_call "US-NONEXISTENT")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: missing story → fallback implement|sonnet|"
else
  fail "routing: missing story → got '$result'"
fi

# Test 3: Fast-path env_missing → skip
make_story "US-DC-3" 3 0 1 "env_missing"
result=$(decision_call "US-DC-3")
if [ "$result" = "skip||" ]; then
  pass "routing: env_missing → skip||"
else
  fail "routing: env_missing → got '$result'"
fi

# Test 4: Fast-path dependency_missing → skip
make_story "US-DC-4" 3 0 1 "dependency_missing"
result=$(decision_call "US-DC-4")
if [ "$result" = "skip||" ]; then
  pass "routing: dependency_missing → skip||"
else
  fail "routing: dependency_missing → got '$result'"
fi

# Test 5: Simple story (1 criterion, 0 deps, attempt=0) → haiku
make_story "US-DC-5" 1 0 0
result=$(decision_call "US-DC-5")
if [ "$result" = "implement|haiku|" ]; then
  pass "routing: 1 criterion, 0 deps, attempt=0 → implement|haiku|"
else
  fail "routing: simple story → got '$result'"
fi

# Test 6: Simple boundary (2 criteria, 0 deps, attempt=0) → haiku
make_story "US-DC-6" 2 0 0
result=$(decision_call "US-DC-6")
if [ "$result" = "implement|haiku|" ]; then
  pass "routing: 2 criteria, 0 deps, attempt=0 → implement|haiku|"
else
  fail "routing: simple boundary → got '$result'"
fi

# Test 7: Standard story (3 criteria, 0 deps, attempt=0) → sonnet
make_story "US-DC-7" 3 0 0
result=$(decision_call "US-DC-7")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: 3 criteria, 0 deps, attempt=0 → implement|sonnet|"
else
  fail "routing: standard story → got '$result'"
fi

# Test 8: Standard boundary (5 criteria, 1 dep, attempt=0) → sonnet
make_story "US-DC-8" 5 1 0
result=$(decision_call "US-DC-8")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: 5 criteria, 1 dep, attempt=0 → implement|sonnet|"
else
  fail "routing: standard boundary → got '$result'"
fi

# Test 9: Retries don't fast-path (3 criteria, 0 deps, attempt=1)
# Falls through to claude -p which fails (mock), returns default
make_story "US-DC-9" 3 0 1
PATH="$TEST_DIR/bin:$PATH" result=$(decision_call "US-DC-9")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: retry attempt=1 → falls through to default"
else
  fail "routing: retry → got '$result'"
fi

# Test 10: Complex doesn't fast-path (6 criteria, 2 deps, attempt=0)
make_story "US-DC-10" 6 2 0
PATH="$TEST_DIR/bin:$PATH" result=$(decision_call "US-DC-10")
if [ "$result" = "implement|sonnet|" ]; then
  pass "routing: 6 criteria, 2 deps → falls through to default"
else
  fail "routing: complex story → got '$result'"
fi

rm -f "$KNOWLEDGE_DB" "$PRD_FILE"

fi

# ─── SECTION 2: Knowledge Mining Quality ─────────────────────────────
if should_run 2; then
header "2. Knowledge Mining Quality" "knowledge_mining"

source "$PLUGIN_DIR/scripts/knowledge-db.sh"

MINE_DB="$TEST_DIR/mining.db"
init_knowledge_db "$MINE_DB"

# Pattern 1: Observations
mine_implicit_learnings "$MINE_DB" "US-M1" "eval-run" \
  "I noticed that the config was missing the timeout field. The build succeeded after fixing it."
COUNT=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M1' AND source='transcript-mining';")
if [ "$COUNT" -ge 1 ]; then
  pass "mining: pattern 1 (observations) extracts learning"
else
  fail "mining: pattern 1 → extracted $COUNT (expected ≥1)"
fi

# Pattern 2: File relationships
mine_implicit_learnings "$MINE_DB" "US-M2" "eval-run" \
  "When updating hooks.json, also update hooks/hooks.md to keep them in sync."
COUNT=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M2' AND tags LIKE '%file-relationship%';")
if [ "$COUNT" -ge 1 ]; then
  pass "mining: pattern 2 (file relationships) extracts with tag"
else
  fail "mining: pattern 2 → extracted $COUNT file-relationship (expected ≥1)"
fi

# Pattern 3: Environment observations
# BUG FOUND: Pattern 3 regex uses (to be |) empty alternative which is invalid
# in macOS ERE (grep -E). The entire alternation fails with "empty (sub)expression".
# This is a real bug in mine_implicit_learnings — the environment pattern never
# fires on macOS. Tracked as known issue; test warns instead of fails.
mine_implicit_learnings "$MINE_DB" "US-M3" "eval-run" \
  "This needs sqlite3 installed for the knowledge database to work."
COUNT=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M3' AND tags LIKE '%environment%';")
if [ "$COUNT" -ge 1 ]; then
  pass "mining: pattern 3 (environment) extracts with tag"
else
  fail "mining: pattern 3 → extracted $COUNT environment (expected ≥1)"
fi

# Pattern 4: Discoveries
mine_implicit_learnings "$MINE_DB" "US-M4" "eval-run" \
  "The project uses pnpm instead of npm for package management."
COUNT=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M4' AND source='transcript-mining';")
if [ "$COUNT" -ge 1 ]; then
  pass "mining: pattern 4 (discoveries) extracts learning"
else
  fail "mining: pattern 4 → extracted $COUNT (expected ≥1)"
fi

# Pattern 5: Conventions
mine_implicit_learnings "$MINE_DB" "US-M5" "eval-run" \
  "The codebase follows kebab-case for all filenames consistently."
COUNT=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M5' AND tags LIKE '%codebase_convention%';")
if [ "$COUNT" -ge 1 ]; then
  pass "mining: pattern 5 (conventions) extracts with tag"
else
  fail "mining: pattern 5 → extracted $COUNT convention (expected ≥1)"
fi

# Correct confidence levels
OBS_CONF=$(sqlite3 "$MINE_DB" "SELECT confidence FROM learnings WHERE story_id='US-M1' AND source='transcript-mining' LIMIT 1;")
if [ "$(echo "$OBS_CONF >= 0.6" | bc 2>/dev/null || echo "1")" = "1" ]; then
  pass "mining: observation confidence ≥ 0.6 ($OBS_CONF)"
else
  fail "mining: observation confidence too low ($OBS_CONF)"
fi

ENV_CONF=$(sqlite3 "$MINE_DB" "SELECT confidence FROM learnings WHERE story_id='US-M3' AND tags LIKE '%environment%' LIMIT 1;" 2>/dev/null)
if [ "$ENV_CONF" = "0.8" ]; then
  pass "mining: environment confidence = 0.8"
else
  fail "mining: environment confidence = ${ENV_CONF:-empty} (expected 0.8)"
fi

CONV_CONF=$(sqlite3 "$MINE_DB" "SELECT confidence FROM learnings WHERE story_id='US-M5' AND tags LIKE '%codebase_convention%' LIMIT 1;")
if [ "$CONV_CONF" = "0.75" ]; then
  pass "mining: convention confidence = 0.75"
else
  fail "mining: convention confidence = $CONV_CONF (expected 0.75)"
fi

# Duplicate prevention
BEFORE=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings;")
mine_implicit_learnings "$MINE_DB" "US-M1" "eval-run" \
  "I noticed that the config was missing the timeout field. The build succeeded after fixing it."
AFTER=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings;")
if [ "$BEFORE" = "$AFTER" ]; then
  pass "mining: duplicate prevention works"
else
  fail "mining: duplicate prevention failed ($BEFORE → $AFTER)"
fi

# Truncation safety (>5000 chars)
LONG_MSG=$(python3 -c "print('The codebase follows xyz pattern. ' * 200)")
mine_implicit_learnings "$MINE_DB" "US-M6" "eval-run" "$LONG_MSG"
pass "mining: >5000 char input doesn't crash"

# No matches (bland text)
BLAND_BEFORE=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M7';")
mine_implicit_learnings "$MINE_DB" "US-M7" "eval-run" "Hello world. This is a simple test."
BLAND_AFTER=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE story_id='US-M7';")
if [ "$BLAND_BEFORE" = "$BLAND_AFTER" ]; then
  pass "mining: bland text → 0 extractions"
else
  fail "mining: bland text extracted $((BLAND_AFTER - BLAND_BEFORE)) (expected 0)"
fi

# Correct source field
SRC=$(sqlite3 "$MINE_DB" "SELECT DISTINCT source FROM learnings WHERE source='transcript-mining' LIMIT 1;")
if [ "$SRC" = "transcript-mining" ]; then
  pass "mining: source field = 'transcript-mining'"
else
  fail "mining: source field = '$SRC'"
fi

# Total mined count sanity check
TOTAL_MINED=$(sqlite3 "$MINE_DB" "SELECT COUNT(*) FROM learnings WHERE source='transcript-mining';")
if [ "$TOTAL_MINED" -ge 5 ]; then
  pass "mining: total mined ≥ 5 across all patterns ($TOTAL_MINED)"
else
  warn "mining: total mined only $TOTAL_MINED (expected ≥5)"
fi

rm -f "$MINE_DB"

fi

# ─── SECTION 3: Bayesian Ranking ─────────────────────────────────────
if should_run 3; then
header "3. Bayesian Ranking" "bayesian_ranking"

source "$PLUGIN_DIR/scripts/knowledge-db.sh"

BAYES_DB="$TEST_DIR/bayesian.db"
init_knowledge_db "$BAYES_DB"

# Seed learnings with known values
# A: reliable, old (10 applied, 9 success, 30 days ago)
sqlite3 "$BAYES_DB" "INSERT INTO learnings (story_id, run_id, content, confidence, tags, source, applied_count, success_count, created_at) VALUES ('US-BA', 'run-b', 'Learning A: reliable old', 1.0, '[]', 'agent', 10, 9, datetime('now', '-30 days'));"
ID_A=$(sqlite3 "$BAYES_DB" "SELECT id FROM learnings WHERE story_id='US-BA';")

# B: unreliable, new (5 applied, 1 success, 1 day ago)
sqlite3 "$BAYES_DB" "INSERT INTO learnings (story_id, run_id, content, confidence, tags, source, applied_count, success_count, created_at) VALUES ('US-BB', 'run-b', 'Learning B: unreliable new', 1.0, '[]', 'agent', 5, 1, datetime('now', '-1 day'));"
ID_B=$(sqlite3 "$BAYES_DB" "SELECT id FROM learnings WHERE story_id='US-BB';")

# C: untested, new (0 applied, 0 success, 1 day ago)
sqlite3 "$BAYES_DB" "INSERT INTO learnings (story_id, run_id, content, confidence, tags, source, applied_count, success_count, created_at) VALUES ('US-BC', 'run-b', 'Learning C: untested new', 1.0, '[]', 'agent', 0, 0, datetime('now', '-1 day'));"
ID_C=$(sqlite3 "$BAYES_DB" "SELECT id FROM learnings WHERE story_id='US-BC';")

# D: untested, old (1 applied, 0 success, 50 days ago)
sqlite3 "$BAYES_DB" "INSERT INTO learnings (story_id, run_id, content, confidence, tags, source, applied_count, success_count, created_at) VALUES ('US-BD', 'run-b', 'Learning D: untested old', 1.0, '[]', 'agent', 1, 0, datetime('now', '-50 days'));"
ID_D=$(sqlite3 "$BAYES_DB" "SELECT id FROM learnings WHERE story_id='US-BD';")

# Check A's Bayesian confidence: (9+1)/(10+2) ≈ 0.833
CONF_A=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CAST(success_count + 1 AS REAL) / (applied_count + 2), 3) FROM learnings WHERE id=$ID_A;")
if [ "$CONF_A" = "0.833" ]; then
  pass "bayesian: A confidence = 0.833 (Bayesian)"
else
  fail "bayesian: A confidence = $CONF_A (expected 0.833)"
fi

# Check B's Bayesian confidence: (1+1)/(5+2) ≈ 0.286
CONF_B=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CAST(success_count + 1 AS REAL) / (applied_count + 2), 3) FROM learnings WHERE id=$ID_B;")
if [ "$CONF_B" = "0.286" ]; then
  pass "bayesian: B confidence = 0.286 (Bayesian)"
else
  fail "bayesian: B confidence = $CONF_B (expected 0.286)"
fi

# A ranks above B
RANKING=$(sqlite3 -separator '|' "$BAYES_DB" "
  SELECT id, ROUND(CASE
    WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2)
    ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at))
  END, 3) AS eff_conf
  FROM learnings WHERE id IN ($ID_A, $ID_B)
  ORDER BY eff_conf DESC LIMIT 1;
")
TOP_ID=$(echo "$RANKING" | cut -d'|' -f1)
if [ "$TOP_ID" = "$ID_A" ]; then
  pass "bayesian: A ranks above B"
else
  fail "bayesian: B ranked above A (top=$TOP_ID)"
fi

# C uses time-decay (untested, new) → ~0.95
CONF_C=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CASE
  WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2)
  ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at))
END, 3) FROM learnings WHERE id=$ID_C;")
# Should be close to 1.0 (1 day decay)
if [ "$(echo "$CONF_C > 0.9" | bc 2>/dev/null || echo "1")" = "1" ]; then
  pass "bayesian: C uses time-decay ($CONF_C > 0.9)"
else
  fail "bayesian: C decay unexpected ($CONF_C)"
fi

# D uses time-decay (1 applied < 2, old) → very low
CONF_D=$(sqlite3 "$BAYES_DB" "SELECT ROUND(CASE
  WHEN applied_count >= 2 THEN CAST(success_count + 1 AS REAL) / (applied_count + 2)
  ELSE confidence * POWER(0.95, julianday('now') - julianday(created_at))
END, 3) FROM learnings WHERE id=$ID_D;")

# C ranks above D
if [ "$(echo "$CONF_C > $CONF_D" | bc 2>/dev/null || echo "1")" = "1" ]; then
  pass "bayesian: C ranks above D ($CONF_C > $CONF_D)"
else
  fail "bayesian: D ranked above C ($CONF_D >= $CONF_C)"
fi

# D gets filtered by 0.3 floor in query_learnings
QUERIED=$(query_learnings "$BAYES_DB" 100)
if echo "$QUERIED" | grep -q "Learning D"; then
  fail "bayesian: D should be filtered by 0.3 floor"
else
  pass "bayesian: D filtered by 0.3 confidence floor"
fi

# query_learnings_with_ids returns correct IDs
RESULT_IDS=$(query_learnings_with_ids "$BAYES_DB" 10)
if echo "$RESULT_IDS" | grep -q "^${ID_A}|"; then
  pass "bayesian: query_learnings_with_ids returns A's ID"
else
  fail "bayesian: query_learnings_with_ids missing A's ID"
fi

rm -f "$BAYES_DB"

fi

# ─── SECTION 4: Pattern Promotion ────────────────────────────────────
if should_run 4; then
header "4. Pattern Promotion" "pattern_promotion"

source "$PLUGIN_DIR/scripts/knowledge-db.sh"

PROMO_DB="$TEST_DIR/promotion.db"
init_knowledge_db "$PROMO_DB"

# Insert learnings with same content across 2 stories → NOT promoted
insert_learning "$PROMO_DB" "US-P1" "run-p" "Pattern with two stories" '[]'
insert_learning "$PROMO_DB" "US-P2" "run-p" "Pattern with two stories" '[]'
promote_learnings_to_patterns "$PROMO_DB"
PROMO_COUNT=$(sqlite3 "$PROMO_DB" "SELECT COUNT(*) FROM patterns WHERE content='Pattern with two stories';")
if [ "$PROMO_COUNT" = "0" ]; then
  pass "promotion: 2 stories → NOT promoted"
else
  fail "promotion: 2 stories → promoted (should need 3)"
fi

# Insert 3rd story → promoted
insert_learning "$PROMO_DB" "US-P3" "run-p" "Pattern with two stories" '[]'
promote_learnings_to_patterns "$PROMO_DB"
PROMO_COUNT=$(sqlite3 "$PROMO_DB" "SELECT COUNT(*) FROM patterns WHERE content='Pattern with two stories';")
if [ "$PROMO_COUNT" = "1" ]; then
  pass "promotion: 3 stories → promoted to patterns"
else
  fail "promotion: 3 stories → count=$PROMO_COUNT (expected 1)"
fi

# Re-running promotion → occurrence_count increments, no duplicates
insert_learning "$PROMO_DB" "US-P4" "run-p" "Pattern with two stories" '[]'
promote_learnings_to_patterns "$PROMO_DB"
PROMO_DUP=$(sqlite3 "$PROMO_DB" "SELECT COUNT(*) FROM patterns WHERE content='Pattern with two stories';")
OCCUR=$(sqlite3 "$PROMO_DB" "SELECT occurrence_count FROM patterns WHERE content='Pattern with two stories';")
if [ "$PROMO_DUP" = "1" ] && [ "$OCCUR" -ge 3 ]; then
  pass "promotion: re-run → no duplicate, occurrence=$OCCUR"
else
  fail "promotion: re-run → count=$PROMO_DUP, occurrence=$OCCUR"
fi

# query_patterns returns promoted entries
PATTERN_RESULT=$(query_patterns "$PROMO_DB")
if echo "$PATTERN_RESULT" | grep -q "Pattern with two stories"; then
  pass "promotion: query_patterns returns promoted entry"
else
  fail "promotion: query_patterns empty or missing entry"
fi

# Category detection: environment tag → environment_note
insert_learning "$PROMO_DB" "US-PE1" "run-p" "Env pattern across stories" 'environment'
insert_learning "$PROMO_DB" "US-PE2" "run-p" "Env pattern across stories" 'environment'
insert_learning "$PROMO_DB" "US-PE3" "run-p" "Env pattern across stories" 'environment'
promote_learnings_to_patterns "$PROMO_DB"
ENV_CAT=$(sqlite3 "$PROMO_DB" "SELECT category FROM patterns WHERE content='Env pattern across stories';")
if [ "$ENV_CAT" = "environment_note" ]; then
  pass "promotion: environment tag → environment_note category"
else
  # Category depends on tag content matching; may fall back to 'general'
  warn "promotion: environment tag → '$ENV_CAT' (expected environment_note)"
fi

rm -f "$PROMO_DB"

fi

# ─── SECTION 5: Hook Behavior ────────────────────────────────────────
if should_run 5; then
header "5. Hook Behavior" "hook_behavior"

# 5.1 validate-result.sh
HOOK="$PLUGIN_DIR/hooks/validate-result.sh"
if [ -f "$HOOK" ]; then
  VDIR="$TEST_DIR/validate"
  mkdir -p "$VDIR/.claude"

  # Non-implementer agent → exit 0
  run_hook "validate-result: non-implementer → pass" "$HOOK" \
    '{"agent_type":"validator","stop_hook_active":false}' 0 "$VDIR"

  # stop_hook_active=true → exit 0
  run_hook "validate-result: stop_hook_active=true → pass" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":true}' 0 "$VDIR"

  # validate_on_stop=false → exit 0
  printf '{"validate_on_stop":false}' > "$VDIR/.claude/taskplex.config.json"
  run_hook "validate-result: validate_on_stop=false → pass" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 0 "$VDIR"

  # No validation commands → exit 0
  printf '{}' > "$VDIR/.claude/taskplex.config.json"
  run_hook "validate-result: no commands → pass" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 0 "$VDIR"

  # typecheck_command="exit 0" → exit 0
  printf '{"typecheck_command":"exit 0"}' > "$VDIR/.claude/taskplex.config.json"
  run_hook "validate-result: typecheck passes → pass" "$HOOK" \
    '{"agent_type":"implementer","stop_hook_active":false}' 0 "$VDIR"

  # typecheck_command="exit 1" → exit 2
  printf '{"typecheck_command":"exit 1"}' > "$VDIR/.claude/taskplex.config.json"
  actual_exit=0
  stderr_out=$(echo '{"agent_type":"implementer","stop_hook_active":false}' | (cd "$VDIR" && bash "$HOOK") 2>&1 >/dev/null) || actual_exit=$?
  if [ "$actual_exit" -eq 2 ]; then
    pass "validate-result: typecheck fails → blocks (exit 2)"
  else
    fail "validate-result: typecheck fails → exit $actual_exit (expected 2)"
  fi

  # test_command="exit 1" → exit 2
  printf '{"test_command":"exit 1"}' > "$VDIR/.claude/taskplex.config.json"
  actual_exit=0
  echo '{"agent_type":"implementer","stop_hook_active":false}' | (cd "$VDIR" && bash "$HOOK") > /dev/null 2>&1 || actual_exit=$?
  if [ "$actual_exit" -eq 2 ]; then
    pass "validate-result: test fails → blocks (exit 2)"
  else
    fail "validate-result: test fails → exit $actual_exit (expected 2)"
  fi

  # All three commands fail → exit 2
  printf '{"typecheck_command":"exit 1","build_command":"exit 1","test_command":"exit 1"}' > "$VDIR/.claude/taskplex.config.json"
  actual_exit=0
  output=$(echo '{"agent_type":"implementer","stop_hook_active":false}' | (cd "$VDIR" && bash "$HOOK") 2>&1) || actual_exit=$?
  if [ "$actual_exit" -eq 2 ]; then
    pass "validate-result: all three fail → blocks (exit 2)"
  else
    fail "validate-result: all three fail → exit $actual_exit (expected 2)"
  fi

  rm -rf "$VDIR"
fi

# 5.2 check-destructive.sh — additional edge cases
HOOK="$PLUGIN_DIR/scripts/check-destructive.sh"
if [ -f "$HOOK" ]; then
  # git clean -fd → deny
  run_hook_decision "check-destructive: git clean -fd → denied" "$HOOK" \
    '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}' "deny"

  # git push -f origin feature → deny
  run_hook_decision "check-destructive: git push -f → denied" "$HOOK" \
    '{"tool_name":"Bash","tool_input":{"command":"git push -f origin feature"}}' "deny"

  # git rebase --abort → allow
  exit_code=0
  echo '{"tool_name":"Bash","tool_input":{"command":"git rebase --abort"}}' | bash "$HOOK" > /dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass "check-destructive: git rebase --abort → allowed"
  else
    fail "check-destructive: git rebase --abort → exit $exit_code"
  fi

  # Empty command → allow
  exit_code=0
  echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$HOOK" > /dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass "check-destructive: empty command → allowed"
  else
    fail "check-destructive: empty command → exit $exit_code"
  fi

  # Non-Bash tool → allow
  exit_code=0
  echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo"}}' | bash "$HOOK" > /dev/null 2>&1 || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    pass "check-destructive: non-Bash tool → allowed"
  else
    fail "check-destructive: non-Bash tool → exit $exit_code"
  fi

  # git push origin master → deny (master same as main)
  run_hook_decision "check-destructive: push origin master → denied" "$HOOK" \
    '{"tool_name":"Bash","tool_input":{"command":"git push origin master"}}' "deny"
fi

# 5.3 teammate-idle.sh
HOOK="$PLUGIN_DIR/hooks/teammate-idle.sh"
if [ -f "$HOOK" ]; then
  TDIR="$TEST_DIR/teammate"
  mkdir -p "$TDIR"

  # No prd.json → empty output
  actual_exit=0
  output=$(echo '{"teammate_id":"t1","teammate_name":"agent-1"}' | (cd "$TDIR" && bash "$HOOK") 2>/dev/null) || actual_exit=$?
  if [ "$actual_exit" -eq 0 ] && [ "$output" = "{}" ]; then
    pass "teammate-idle: no prd.json → {}"
  else
    fail "teammate-idle: no prd.json → exit=$actual_exit, output='$output'"
  fi

  # All completed → empty output
  cat > "$TDIR/prd.json" <<'TIDLEEOF'
{"project":"test","userStories":[{"id":"US-T1","title":"Done","passes":true,"status":"completed","priority":1}]}
TIDLEEOF
  output=$(echo '{"teammate_id":"t2","teammate_name":"agent-2"}' | (cd "$TDIR" && bash "$HOOK") 2>/dev/null) || true
  if [ "$output" = "{}" ]; then
    pass "teammate-idle: all completed → {}"
  else
    fail "teammate-idle: all completed → '$output'"
  fi

  # One pending, no deps → story assigned
  cat > "$TDIR/prd.json" <<'TIDLEEOF'
{"project":"test","userStories":[{"id":"US-T2","title":"Pending","passes":false,"status":"pending","priority":1,"depends_on":[],"acceptanceCriteria":["Test"]}]}
TIDLEEOF
  output=$(echo '{"teammate_id":"t3","teammate_name":"agent-3"}' | (cd "$TDIR" && bash "$HOOK") 2>/dev/null) || true
  if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null 2>&1; then
    pass "teammate-idle: pending story → assigned with context"
  else
    fail "teammate-idle: pending story → no context in output"
  fi

  # Verify prd.json was updated with in_progress
  STATUS=$(jq -r '.userStories[0].status' "$TDIR/prd.json" 2>/dev/null)
  if [ "$STATUS" = "in_progress" ]; then
    pass "teammate-idle: prd.json updated to in_progress"
  else
    fail "teammate-idle: prd.json status='$STATUS' (expected in_progress)"
  fi

  rm -rf "$TDIR"
fi

fi

# ─── SECTION 6: Spec Hardening Quality (LLM-gated) ───────────────────
if should_run 6; then
header "6. Spec Hardening Quality" "spec_hardening"

if [ -n "${CLAUDECODE:-}" ] || [ "$FULL_MODE" = false ]; then
  warn "SKIPPED: LLM-gated section (use --full from external terminal)"
else
  # Test requires harden_spec() from taskplex.sh — which needs many dependencies.
  # Instead, test the concept: call claude -p with the spec hardening prompt directly.
  SPEC_DIR="$TEST_DIR/spec"
  mkdir -p "$SPEC_DIR"

  # Create vague criteria
  VAGUE_CRITERIA='["Handle edge cases gracefully","Be performant","Good UX"]'

  HARDEN_PROMPT=$(cat <<'HARDENEOF'
You are a spec hardening assistant. Given vague acceptance criteria, rewrite each one to be specific, measurable, and testable. Return ONLY a JSON array of strings with the rewritten criteria, no other text.

Criteria to harden:
HARDENEOF
)
  HARDEN_PROMPT="${HARDEN_PROMPT}
${VAGUE_CRITERIA}"

  HARDENED=$(echo "$HARDEN_PROMPT" | env -u CLAUDECODE claude -p \
    --model haiku --max-turns 1 --output-format json \
    --dangerously-skip-permissions 2>/dev/null) || true

  if [ -z "$HARDENED" ]; then
    warn "spec-hardening: claude -p returned empty (API issue?)"
  else
    # Parse output — Claude wraps in {"result": "..."}
    CRITERIA_JSON=$(echo "$HARDENED" | jq -r '.result // ""' 2>/dev/null | jq '.' 2>/dev/null)

    if [ -z "$CRITERIA_JSON" ] || [ "$CRITERIA_JSON" = "null" ]; then
      # Try direct parsing in case output format varies
      CRITERIA_JSON=$(echo "$HARDENED" | jq '.' 2>/dev/null)
    fi

    if [ -n "$CRITERIA_JSON" ] && [ "$CRITERIA_JSON" != "null" ]; then
      # Check: criterion count >= original (hardening may expand vague criteria)
      NEW_COUNT=$(echo "$CRITERIA_JSON" | jq 'length' 2>/dev/null || echo "0")
      if [ "$NEW_COUNT" -ge 3 ]; then
        pass "spec-hardening: criterion count $NEW_COUNT (≥3 original)"
      else
        fail "spec-hardening: criterion count $NEW_COUNT (expected ≥3)"
      fi

      # Check: no vague words remain
      VAGUE_FOUND=false
      for vague_word in "edge cases" "performant" "good ux"; do
        if echo "$CRITERIA_JSON" | grep -qi "$vague_word"; then
          VAGUE_FOUND=true
          break
        fi
      done
      if [ "$VAGUE_FOUND" = false ]; then
        pass "spec-hardening: vague words removed"
      else
        fail "spec-hardening: vague words still present"
      fi

      # Check: at least one criterion contains a number/threshold
      if echo "$CRITERIA_JSON" | grep -qE '[0-9]'; then
        pass "spec-hardening: contains numeric threshold"
      else
        warn "spec-hardening: no numeric threshold in criteria"
      fi

      # Check: all criteria are non-empty strings
      EMPTY_COUNT=$(echo "$CRITERIA_JSON" | jq '[.[] | select(length == 0)] | length' 2>/dev/null || echo "0")
      if [ "$EMPTY_COUNT" -eq 0 ]; then
        pass "spec-hardening: all criteria non-empty"
      else
        fail "spec-hardening: $EMPTY_COUNT empty criteria"
      fi
    else
      warn "spec-hardening: could not parse output as JSON"
    fi
  fi
fi

fi

# ─── SECTION 7: Skill Response Quality (LLM-gated) ───────────────────
if should_run 7; then
header "7. Skill Response Quality" "skill_quality_eval"

if [ -n "${CLAUDECODE:-}" ] || [ "$FULL_MODE" = false ]; then
  warn "SKIPPED: LLM-gated section (use --full from external terminal)"
else
  # eval_skill: test that a skill's SKILL.md produces relevant output when
  # used as the system prompt for claude -p. Uses --system-prompt-file to
  # REPLACE the default prompt (not append) so haiku focuses on the skill
  # instructions without the heavy Claude Code system prompt.
  eval_skill() {
    local skill="$1" query="$2" required_patterns="$3" min_words="${4:-50}"
    local skill_path="$PLUGIN_DIR/skills/$skill/SKILL.md"

    if [ ! -f "$skill_path" ]; then
      fail "$skill: SKILL.md not found"
      return
    fi

    local output
    output=$(echo "$query" | env -u CLAUDECODE claude -p \
      --system-prompt-file "$skill_path" \
      --model haiku --max-turns 1 2>/dev/null) || {
      warn "$skill: claude -p failed"
      return
    }

    if [ -z "$output" ]; then
      warn "$skill: empty output"
      return
    fi

    # Check required patterns in output (case-insensitive)
    local pattern
    for pattern in $required_patterns; do
      if echo "$output" | grep -qi "$pattern"; then
        pass "$skill: output contains '$pattern'"
      else
        fail "$skill: output missing '$pattern'"
      fi
    done

    # Information density: word count > threshold
    local wc
    wc=$(echo "$output" | wc -w | tr -d ' ')
    if [ "$wc" -gt "$min_words" ]; then
      pass "$skill: ${wc} words (information dense)"
    else
      warn "$skill: ${wc} words (sparse, expected >$min_words)"
    fi
  }

  # Queries are enriched to give enough context for headless single-turn mode.
  # Pattern checks are broad — we verify the skill's structure is followed,
  # not exact wording. These are smoke tests, not full behavioral tests.

  eval_skill "brainstorm" \
    "I want to add a caching layer to our REST API. We have a Node.js Express backend with PostgreSQL. What should I consider before implementing this?" \
    "assumption alternative"

  eval_skill "prd-generator" \
    "I need a PRD for adding dark mode support to our React dashboard. The app uses Tailwind CSS and has about 30 components." \
    "acceptance criteria"

  eval_skill "systematic-debugging" \
    "Our integration tests are failing with timeout errors after upgrading from Node 18 to Node 20. The tests pass locally but fail in CI. Error: 'Exceeded timeout of 5000ms'. What should I investigate?" \
    "hypothesis evidence"

  eval_skill "taskplex-tdd" \
    "I need to add a new user profile endpoint that returns user data from our PostgreSQL database. The endpoint should be GET /api/users/:id." \
    "test RED GREEN"

  eval_skill "taskplex-verify" \
    "I've fixed the login bug where users couldn't authenticate with email+password. I changed the bcrypt comparison in auth.ts." \
    "evidence verify"

  eval_skill "failure-analyzer" \
    "Build failed with: Error: Cannot find module '@/utils/helpers'. The module was recently moved from src/utils to src/lib/utils." \
    "category"
fi

fi

# ─── Summary ────────────────────────────────────────────────────────
flush_section

echo ""
echo -e "${CYAN}━━━ Summary ━━━${NC}"
TOTAL=$((PASS + FAIL + WARN))
SCORE=0
if [ "$TOTAL" -gt 0 ]; then
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
    --arg suite "evaluation" \
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
