#!/bin/bash
# ai-frontier plugin test suite
# Usage: ./run-tests.sh [--save]
# --save flag appends results to test-history.jsonl

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../../ai-frontier" && pwd)"
RESULTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PASS=0
FAIL=0
WARN=0
NOTES=()

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
pass()   { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1"; NOTES+=("FAIL: $1"); }
warn()   { WARN=$((WARN + 1)); echo -e "  ${YELLOW}⚠${NC} $1"; NOTES+=("WARN: $1"); }

# ─── SECTION 1: File Structure ──────────────────────────────────────
header "1. Plugin File Structure"

required_files=(
    ".claude-plugin/plugin.json"
    "CLAUDE.md"
    "README.md"
    "hooks/hooks.json"
    "hooks/validate-research-output.py"
    "hooks/validate-synthesis-output.py"
    "skills/using-ai-frontier/SKILL.md"
    "skills/arxiv-search/SKILL.md"
    "skills/arxiv-search/scripts/search.mjs"
    "skills/arxiv-search/scripts/search"
    "skills/semantic-scholar-search/SKILL.md"
    "skills/semantic-scholar-search/scripts/search.mjs"
    "skills/semantic-scholar-search/scripts/search"
    "skills/hf-papers-search/SKILL.md"
    "skills/hf-papers-search/scripts/search.mjs"
    "skills/hf-papers-search/scripts/search"
    "skills/perplexity-search/SKILL.md"
    "skills/perplexity-search/scripts/search.mjs"
    "skills/perplexity-search/scripts/search"
    "agents/literature-reviewer.md"
    "agents/method-analyst.md"
    "agents/implementation-guide.md"
    "agents/architecture-evaluator.md"
)

for f in "${required_files[@]}"; do
    if [[ -f "$PLUGIN_DIR/$f" ]]; then
        pass "$f exists"
    else
        fail "$f missing"
    fi
done

# Check scripts are executable
for script in arxiv-search semantic-scholar-search hf-papers-search perplexity-search; do
    if [[ -x "$PLUGIN_DIR/skills/$script/scripts/search" ]]; then
        pass "$script/scripts/search is executable"
    else
        fail "$script/scripts/search is NOT executable"
    fi
done

# ─── SECTION 2: Plugin Manifest ─────────────────────────────────────
header "2. Plugin Manifest Validation"

manifest="$PLUGIN_DIR/.claude-plugin/plugin.json"
if jq empty "$manifest" 2>/dev/null; then
    pass "plugin.json is valid JSON"
else
    fail "plugin.json is INVALID JSON"
fi

# Required fields
for field in name version description author license repository skills agents; do
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

# No hooks field (auto-discovered)
if jq -e '.hooks' "$manifest" >/dev/null 2>&1; then
    fail "plugin.json should NOT have 'hooks' field (auto-discovered)"
else
    pass "No 'hooks' field (correctly auto-discovered)"
fi

# Skills paths start with ./
skills_ok=true
while IFS= read -r skill; do
    if [[ "$skill" != ./* ]]; then
        fail "Skill path '$skill' doesn't start with ./"
        skills_ok=false
    fi
done < <(jq -r '.skills[]' "$manifest" 2>/dev/null)
$skills_ok && pass "All skill paths start with ./"

# Agent paths start with ./ and end with .md
agents_ok=true
while IFS= read -r agent; do
    if [[ "$agent" != ./* || "$agent" != *.md ]]; then
        fail "Agent path '$agent' doesn't match ./agents/*.md pattern"
        agents_ok=false
    fi
done < <(jq -r '.agents[]' "$manifest" 2>/dev/null)
$agents_ok && pass "All agent paths match ./agents/*.md"

# Semver check
version=$(jq -r '.version' "$manifest")
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "Version '$version' is valid semver"
else
    fail "Version '$version' is not valid semver"
fi

# ─── SECTION 3: Hooks Configuration ─────────────────────────────────
header "3. Hooks Configuration"

hooks_file="$PLUGIN_DIR/hooks/hooks.json"
if jq empty "$hooks_file" 2>/dev/null; then
    pass "hooks.json is valid JSON"
else
    fail "hooks.json is INVALID JSON"
fi

# Check hook events are valid
valid_events="PreToolUse PostToolUse PostToolUseFailure PermissionRequest UserPromptSubmit Notification Stop SubagentStart SubagentStop SessionStart SessionEnd TeammateIdle TaskCompleted PreCompact"
while IFS= read -r event; do
    if echo "$valid_events" | grep -qw "$event"; then
        pass "Hook event '$event' is valid"
    else
        fail "Hook event '$event' is NOT a valid Claude Code event"
    fi
done < <(jq -r '.hooks | keys[]' "$hooks_file" 2>/dev/null)

# Check PostToolUse matcher
post_matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$hooks_file" 2>/dev/null)
if [[ "$post_matcher" == "Bash" ]]; then
    pass "PostToolUse matcher is 'Bash'"
else
    warn "PostToolUse matcher is '$post_matcher' (expected 'Bash')"
fi

# Check SubagentStop matcher covers all agents
sub_matcher=$(jq -r '.hooks.SubagentStop[0].matcher' "$hooks_file" 2>/dev/null)
for agent in literature-reviewer method-analyst implementation-guide architecture-evaluator; do
    if echo "$sub_matcher" | grep -q "$agent"; then
        pass "SubagentStop matcher includes '$agent'"
    else
        fail "SubagentStop matcher missing '$agent'"
    fi
done

# ─── SECTION 4: API Retrieval Scripts ────────────────────────────────
header "4. API Retrieval Scripts"

test_query="retrieval augmented generation"

# arXiv
echo -e "  Testing arXiv API..."
arxiv_out=$(timeout 30 node "$PLUGIN_DIR/skills/arxiv-search/scripts/search.mjs" "$test_query" 2 2>&1) || true
arxiv_success=$(echo "$arxiv_out" | jq -r '.success' 2>/dev/null)
arxiv_source=$(echo "$arxiv_out" | jq -r '.source' 2>/dev/null)
arxiv_count=$(echo "$arxiv_out" | jq -r '.result_count' 2>/dev/null)

if [[ "$arxiv_success" == "true" ]]; then
    pass "arXiv API: success=true, source=$arxiv_source, results=$arxiv_count"
else
    fail "arXiv API: success=$arxiv_success"
fi

# Semantic Scholar
echo -e "  Testing Semantic Scholar API..."
s2_out=$(timeout 30 node "$PLUGIN_DIR/skills/semantic-scholar-search/scripts/search.mjs" "$test_query" 2 2>&1) || true
s2_success=$(echo "$s2_out" | jq -r '.success' 2>/dev/null)
s2_source=$(echo "$s2_out" | jq -r '.source' 2>/dev/null)
s2_count=$(echo "$s2_out" | jq -r '.result_count' 2>/dev/null)

if [[ "$s2_success" == "true" ]]; then
    pass "Semantic Scholar API: success=true, source=$s2_source, results=$s2_count"
elif echo "$s2_out" | jq -r '.error' 2>/dev/null | grep -qi "429"; then
    warn "Semantic Scholar API: rate limited (429) - retry later"
else
    fail "Semantic Scholar API: $(echo "$s2_out" | jq -r '.error' 2>/dev/null)"
fi

# HF Papers
echo -e "  Testing HF Papers API..."
hf_out=$(timeout 30 node "$PLUGIN_DIR/skills/hf-papers-search/scripts/search.mjs" "$test_query" 2 2>&1) || true
hf_success=$(echo "$hf_out" | jq -r '.success' 2>/dev/null)
hf_source=$(echo "$hf_out" | jq -r '.source' 2>/dev/null)
hf_count=$(echo "$hf_out" | jq -r '.result_count' 2>/dev/null)

if [[ "$hf_success" == "true" ]]; then
    pass "HF Papers API: success=true, source=$hf_source, results=$hf_count"
else
    fail "HF Papers API: $(echo "$hf_out" | jq -r '.error' 2>/dev/null)"
fi

# Perplexity (optional — requires OPENROUTER_API_KEY)
echo -e "  Testing Perplexity API..."
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    warn "Perplexity API: OPENROUTER_API_KEY not set (optional)"
    ppx_success="skipped"
else
    ppx_out=$(timeout 30 node "$PLUGIN_DIR/skills/perplexity-search/scripts/search.mjs" "test query" 2>&1) || true
    ppx_success=$(echo "$ppx_out" | jq -r '.success' 2>/dev/null)
    ppx_source=$(echo "$ppx_out" | jq -r '.source' 2>/dev/null)

    if [[ "$ppx_success" == "true" ]]; then
        pass "Perplexity API: success=true, source=$ppx_source"
    else
        fail "Perplexity API: $(echo "$ppx_out" | jq -r '.error' 2>/dev/null)"
    fi
fi

# ─── SECTION 5: JSON Envelope Schema ────────────────────────────────
header "5. JSON Envelope Schema Validation"

# Test each successful output for required envelope fields
for label_out in "arxiv:$arxiv_out" "hf_papers:$hf_out"; do
    label="${label_out%%:*}"
    out="${label_out#*:}"
    success=$(echo "$out" | jq -r '.success' 2>/dev/null)
    [[ "$success" != "true" ]] && continue

    # Top-level fields
    for field in success query source result_count results meta; do
        if echo "$out" | jq -e ".$field" >/dev/null 2>&1; then
            pass "$label envelope: '$field' present"
        else
            fail "$label envelope: '$field' missing"
        fi
    done

    # Result item fields
    first=$(echo "$out" | jq '.results[0]' 2>/dev/null)
    if [[ "$first" != "null" && -n "$first" ]]; then
        for field in title authors year abstract url pdf_url source_specific; do
            if echo "$first" | jq -e ".$field" >/dev/null 2>&1; then
                pass "$label result[0]: '$field' present"
            else
                fail "$label result[0]: '$field' missing"
            fi
        done
    fi
done

# ─── SECTION 6: Hook Validator Logic ────────────────────────────────
header "6. Hook Validator Logic"

run_validator() {
    local desc="$1" input="$2" expected_exit="$3" script="$4"
    actual_exit=$(/bin/bash -c "echo '$input' | python3 '$PLUGIN_DIR/hooks/$script' 2>/dev/null; echo \$?" | tail -1)
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        pass "$desc → exit $actual_exit (expected $expected_exit)"
    else
        fail "$desc → exit $actual_exit (expected $expected_exit)"
    fi
}

# validate-research-output.py tests
run_validator "Valid research output" \
    '{"tool_result": "{\"success\": true, \"source\": \"arxiv\", \"results\": []}"}' \
    0 "validate-research-output.py"

run_validator "Wrong field name (tool_output) — pass-through" \
    '{"tool_output": "{\"success\": true, \"source\": \"arxiv\", \"results\": []}"}' \
    0 "validate-research-output.py"

run_validator "Non-research output — pass-through" \
    '{"tool_result": "just some text"}' \
    0 "validate-research-output.py"

run_validator "Malformed JSON in result" \
    '{"tool_result": "{\"source\": \"arxiv\", broken}"}' \
    2 "validate-research-output.py"

run_validator "Missing success field" \
    '{"tool_result": "{\"source\": \"arxiv\", \"results\": []}"}' \
    2 "validate-research-output.py"

run_validator "Perplexity source accepted" \
    '{"tool_result": "{\"success\": true, \"source\": \"perplexity\", \"results\": []}"}' \
    0 "validate-research-output.py"

run_validator "Empty stdin — pass-through" \
    '' \
    0 "validate-research-output.py"

# validate-synthesis-output.py tests
run_validator "Literature reviewer: all sections (### headings)" \
    '{"agent_type": "literature-reviewer", "last_assistant_message": "### DATA SOURCES\nstuff\n### CONSENSUS\nfoo\n### FRONTIER\nbar\n### KEY PAPERS\nbaz"}' \
    0 "validate-synthesis-output.py"

run_validator "Literature reviewer: all sections (## headings)" \
    '{"agent_type": "literature-reviewer", "last_assistant_message": "## DATA SOURCES\nstuff\n## CONSENSUS\nfoo\n## FRONTIER\nbar\n## KEY PAPERS\nbaz"}' \
    0 "validate-synthesis-output.py"

run_validator "Literature reviewer: missing DATA SOURCES" \
    '{"agent_type": "literature-reviewer", "last_assistant_message": "### CONSENSUS\nfoo\n### FRONTIER\nbar\n### KEY PAPERS\nbaz"}' \
    2 "validate-synthesis-output.py"

run_validator "Literature reviewer: missing FRONTIER" \
    '{"agent_type": "literature-reviewer", "last_assistant_message": "### DATA SOURCES\nstuff\n### CONSENSUS\nfoo\n### KEY PAPERS\nbaz"}' \
    2 "validate-synthesis-output.py"

run_validator "Method analyst: all sections" \
    '{"agent_type": "method-analyst", "last_assistant_message": "## DATA SOURCES\nok\n## COMPARISON MATRIX\nfoo\n## RECOMMENDATION\nbar"}' \
    0 "validate-synthesis-output.py"

run_validator "Method analyst: missing DATA SOURCES" \
    '{"agent_type": "method-analyst", "last_assistant_message": "## COMPARISON MATRIX\nfoo\n## RECOMMENDATION\nbar"}' \
    2 "validate-synthesis-output.py"

run_validator "Implementation guide: all sections" \
    '{"agent_type": "implementation-guide", "last_assistant_message": "## DATA SOURCES\nok\n## CORE ALGORITHM\nfoo\n## REFERENCE IMPLEMENTATIONS\nbar"}' \
    0 "validate-synthesis-output.py"

run_validator "Implementation guide: missing DATA SOURCES" \
    '{"agent_type": "implementation-guide", "last_assistant_message": "## CORE ALGORITHM\nfoo\n## REFERENCE IMPLEMENTATIONS\nbar"}' \
    2 "validate-synthesis-output.py"

run_validator "Implementation guide: missing CORE ALGORITHM" \
    '{"agent_type": "implementation-guide", "last_assistant_message": "## DATA SOURCES\nok\n## REFERENCE IMPLEMENTATIONS\nfoo"}' \
    2 "validate-synthesis-output.py"

run_validator "Architecture evaluator: all sections" \
    '{"agent_type": "architecture-evaluator", "last_assistant_message": "## DATA SOURCES\nok\n## CURRENT ARCHITECTURE\n## GAP ANALYSIS\n## RECOMMENDATIONS\n"}' \
    0 "validate-synthesis-output.py"

run_validator "Architecture evaluator: missing DATA SOURCES" \
    '{"agent_type": "architecture-evaluator", "last_assistant_message": "## CURRENT ARCHITECTURE\n## GAP ANALYSIS\n## RECOMMENDATIONS\n"}' \
    2 "validate-synthesis-output.py"

run_validator "Prefixed agent name: catches missing section" \
    '{"agent_type": "ai-frontier:literature-reviewer", "last_assistant_message": "### CONSENSUS\nfoo\n### FRONTIER\nbar\n### KEY PAPERS\nbaz"}' \
    2 "validate-synthesis-output.py"

run_validator "Prefixed agent name: all sections pass" \
    '{"agent_type": "ai-frontier:literature-reviewer", "last_assistant_message": "### DATA SOURCES\nok\n### CONSENSUS\nfoo\n### FRONTIER\nbar\n### KEY PAPERS\nbaz"}' \
    0 "validate-synthesis-output.py"

run_validator "Prefixed architecture-evaluator: all sections" \
    '{"agent_type": "ai-frontier:architecture-evaluator", "last_assistant_message": "## DATA SOURCES\nok\n## CURRENT ARCHITECTURE\n## GAP ANALYSIS\n## RECOMMENDATIONS\n"}' \
    0 "validate-synthesis-output.py"

run_validator "Unknown agent: pass through" \
    '{"agent_type": "some-other-agent", "last_assistant_message": "anything"}' \
    0 "validate-synthesis-output.py"

run_validator "stop_hook_active: bypass" \
    '{"agent_type": "literature-reviewer", "last_assistant_message": "", "stop_hook_active": true}' \
    0 "validate-synthesis-output.py"

# ─── SECTION 7: Agent Spec Quality ──────────────────────────────────
header "7. Agent Spec Quality"

for agent_file in "$PLUGIN_DIR"/agents/*.md; do
    agent_name=$(basename "$agent_file" .md)

    # Check frontmatter
    if head -1 "$agent_file" | grep -q "^---"; then
        pass "$agent_name: has YAML frontmatter"
    else
        fail "$agent_name: missing YAML frontmatter"
    fi

    # Check model specification
    if grep -q "model:" "$agent_file"; then
        pass "$agent_name: specifies model"
    else
        warn "$agent_name: no model specification"
    fi

    # Check tools specification
    if grep -q "tools:" "$agent_file"; then
        pass "$agent_name: specifies tools"
    else
        warn "$agent_name: no tools specification"
    fi

    # Check output format section
    if grep -qi "output format\|output.*required\|required.*output" "$agent_file"; then
        pass "$agent_name: has output format section"
    else
        warn "$agent_name: no explicit output format section"
    fi

    # Check word count (should be substantial)
    wc=$(wc -w < "$agent_file")
    if (( wc > 200 )); then
        pass "$agent_name: ${wc} words (substantial spec)"
    elif (( wc > 100 )); then
        warn "$agent_name: ${wc} words (could be more detailed)"
    else
        fail "$agent_name: ${wc} words (too sparse)"
    fi
done

# ─── SECTION 8: Skill SKILL.md Quality ──────────────────────────────
header "8. Skill Quality"

for skill_dir in "$PLUGIN_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_md="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_md" ]]; then
        fail "$skill_name: missing SKILL.md"
        continue
    fi

    # Check frontmatter
    if head -1 "$skill_md" | grep -q "^---"; then
        pass "$skill_name: has YAML frontmatter"
    else
        fail "$skill_name: missing YAML frontmatter"
    fi

    # Check name field
    if grep -q "^name:" "$skill_md"; then
        pass "$skill_name: has name field"
    else
        fail "$skill_name: missing name field"
    fi

    # Check description field
    if grep -q "^description:" "$skill_md"; then
        pass "$skill_name: has description field"
    else
        fail "$skill_name: missing description field"
    fi

    # Word count
    wc=$(wc -w < "$skill_md")
    if (( wc > 100 )); then
        pass "$skill_name: ${wc} words"
    elif (( wc > 50 )); then
        warn "$skill_name: ${wc} words (brief)"
    else
        fail "$skill_name: ${wc} words (too sparse)"
    fi
done

# ─── SECTION 9: Special Feature Tests ───────────────────────────────
header "9. Special Features"

# arXiv category filter
echo -e "  Testing arXiv category filter..."
arxiv_cat=$(timeout 30 node "$PLUGIN_DIR/skills/arxiv-search/scripts/search.mjs" "neural network" 2 --cats=cs.AI 2>&1) || true
if echo "$arxiv_cat" | jq -e '.success == true' >/dev/null 2>&1; then
    pass "arXiv category filter works"
else
    warn "arXiv category filter: $(echo "$arxiv_cat" | jq -r '.error' 2>/dev/null)"
fi

# arXiv sort by date
echo -e "  Testing arXiv sort by date..."
arxiv_date=$(timeout 30 node "$PLUGIN_DIR/skills/arxiv-search/scripts/search.mjs" "large language model" 2 --sort=date 2>&1) || true
if echo "$arxiv_date" | jq -e '.success == true' >/dev/null 2>&1; then
    pass "arXiv sort by date works"
else
    warn "arXiv sort by date: $(echo "$arxiv_date" | jq -r '.error' 2>/dev/null)"
fi

# HF Papers trending
echo -e "  Testing HF Papers trending..."
hf_trend=$(timeout 30 node "$PLUGIN_DIR/skills/hf-papers-search/scripts/search.mjs" --trending 3 2>&1) || true
if echo "$hf_trend" | jq -e '.success == true' >/dev/null 2>&1; then
    trend_count=$(echo "$hf_trend" | jq -r '.result_count' 2>/dev/null)
    pass "HF Papers trending: $trend_count papers returned"
else
    fail "HF Papers trending: $(echo "$hf_trend" | jq -r '.error' 2>/dev/null)"
fi

# Perplexity SOTA mode (if API key available)
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    echo -e "  Testing Perplexity --sota mode..."
    ppx_sota=$(timeout 30 node "$PLUGIN_DIR/skills/perplexity-search/scripts/search.mjs" --sota "transformer architecture" 2>&1) || true
    if echo "$ppx_sota" | jq -e '.success == true' >/dev/null 2>&1; then
        cit_count=$(echo "$ppx_sota" | jq -r '.results[0].citations | length' 2>/dev/null)
        pass "Perplexity --sota: success, $cit_count citations"
    else
        fail "Perplexity --sota: $(echo "$ppx_sota" | jq -r '.error' 2>/dev/null)"
    fi

    echo -e "  Testing Perplexity --recent mode..."
    ppx_recent=$(timeout 30 node "$PLUGIN_DIR/skills/perplexity-search/scripts/search.mjs" --recent "LLM agents" --days=7 2>&1) || true
    if echo "$ppx_recent" | jq -e '.success == true' >/dev/null 2>&1; then
        pass "Perplexity --recent: success"
    else
        fail "Perplexity --recent: $(echo "$ppx_recent" | jq -r '.error' 2>/dev/null)"
    fi
fi

# ─── SUMMARY ────────────────────────────────────────────────────────
header "SUMMARY"

TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warned:${NC} $WARN"
echo -e "  Total:   $TOTAL"
echo ""

if (( FAIL == 0 )); then
    echo -e "  ${GREEN}OVERALL: PASS${NC}"
    OVERALL="PASS"
elif (( FAIL <= 3 )); then
    echo -e "  ${YELLOW}OVERALL: PASS WITH ISSUES${NC}"
    OVERALL="PASS_WITH_ISSUES"
else
    echo -e "  ${RED}OVERALL: FAIL${NC}"
    OVERALL="FAIL"
fi

# ─── Save results ───────────────────────────────────────────────────
if [[ "${1:-}" == "--save" ]]; then
    result_json=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg overall "$OVERALL" \
        --argjson pass "$PASS" \
        --argjson fail "$FAIL" \
        --argjson warn "$WARN" \
        --argjson total "$TOTAL" \
        --arg arxiv_ok "${arxiv_success:-false}" \
        --arg s2_ok "${s2_success:-false}" \
        --arg hf_ok "${hf_success:-false}" \
        --arg ppx_ok "${ppx_success:-skipped}" \
        --arg version "$version" \
        '{
            timestamp: $ts,
            plugin: "ai-frontier",
            version: $version,
            overall: $overall,
            passed: $pass,
            failed: $fail,
            warned: $warn,
            total: $total,
            apis: {
                arxiv: ($arxiv_ok == "true"),
                semantic_scholar: ($s2_ok == "true"),
                hf_papers: ($hf_ok == "true"),
                perplexity: $ppx_ok
            },
            notes: []
        }')

    # Add notes
    for note in "${NOTES[@]}"; do
        result_json=$(echo "$result_json" | jq --arg n "$note" '.notes += [$n]')
    done

    echo "$result_json" >> "$RESULTS_DIR/test-history.jsonl"
    echo -e "\n  ${CYAN}Results saved to test-history.jsonl${NC}"
fi

echo ""
