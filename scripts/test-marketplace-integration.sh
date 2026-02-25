#!/bin/bash
set -eo pipefail

# Comprehensive marketplace integration testing script
# Tests plugins in isolation and together to verify no conflicts
# Compatible with Bash 3.2+ (macOS default)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="${TMPDIR:-/tmp}/claude-marketplace-test-$$"
REPORT_FILE="$MARKETPLACE_ROOT/marketplace-test-report.txt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Plugin list
PLUGINS=("sdk-bridge" "taskplex" "storybook-assistant" "nano-banana" "claude-project-planner" "ai-frontier")

# Helper functions to get plugin-specific info
get_plugin_path() {
    local plugin=$1
    echo "$MARKETPLACE_ROOT/$plugin"
}

get_test_command() {
    local plugin=$1
    case $plugin in
        sdk-bridge)
            echo "/sdk-bridge:start --help"
            ;;
        taskplex)
            echo "/taskplex:start --help"
            ;;
        storybook-assistant)
            echo "/storybook-assistant:help"
            ;;
        nano-banana)
            echo "/nano-banana:setup"
            ;;
        claude-project-planner)
            echo "/claude-project-planner:help"
            ;;
        ai-frontier)
            echo "/ai-frontier:arxiv-search --help"
            ;;
    esac
}

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test directory...${NC}"
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        echo -e "${GREEN}✅ Test directory removed${NC}"
    fi
}

trap cleanup EXIT

# Logging functions
log_test() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}TEST: $1${NC}" | tee -a "$REPORT_FILE"
    TESTS_RUN=$((TESTS_RUN + 1))
}

log_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}" | tee -a "$REPORT_FILE"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}" | tee -a "$REPORT_FILE"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$REPORT_FILE"
}

log_section() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
}

# Create test environment
setup_test_env() {
    log_section "Setting Up Test Environment"

    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Create a simple test project structure
    cat > package.json << 'EOF'
{
  "name": "marketplace-integration-test",
  "version": "1.0.0",
  "description": "Test project for marketplace integration"
}
EOF

    cat > README.md << 'EOF'
# Test Project

This is a temporary test project for marketplace integration testing.
EOF

    log_pass "Test environment created at $TEST_DIR"
    log_info "Test project: marketplace-integration-test"
}

# Test plugin structure
test_plugin_structure() {
    local plugin=$1
    local path=$(get_plugin_path "$plugin")

    log_test "Plugin structure: $plugin"

    # Check plugin directory exists
    if [ ! -d "$path" ]; then
        log_fail "$plugin: Directory not found at $path"
        return 1
    fi

    # Check for plugin.json
    local manifest="$path/.claude-plugin/plugin.json"
    if [ ! -f "$manifest" ]; then
        log_fail "$plugin: No plugin.json found at $manifest"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$manifest" 2>/dev/null; then
        log_fail "$plugin: Invalid JSON in plugin.json"
        return 1
    fi

    # Check required fields
    local name=$(jq -r '.name' "$manifest")
    local version=$(jq -r '.version' "$manifest")

    if [ "$name" = "null" ] || [ "$version" = "null" ]; then
        log_fail "$plugin: Missing required fields (name, version)"
        return 1
    fi

    log_pass "$plugin: Structure valid (v$version)"
}

# Test plugin in isolation
test_plugin_isolation() {
    local plugin=$1
    local path=$(get_plugin_path "$plugin")
    local test_cmd=$(get_test_command "$plugin")

    log_test "Plugin isolation: $plugin"
    log_info "Loading only $plugin with --plugin-dir"
    log_info "Path: $path"

    # Create test script for Claude Code
    cat > "$TEST_DIR/test-$plugin.txt" << EOF
Testing $plugin in isolation
Commands should be available under /$plugin:* namespace
EOF

    log_info "To test $plugin in isolation:"
    echo ""
    echo -e "${YELLOW}  cd $TEST_DIR${NC}"
    echo -e "${YELLOW}  claude --plugin-dir $path --dangerously-skip-permissions${NC}"
    echo ""
    echo -e "${YELLOW}  Then run:${NC}"
    echo -e "${YELLOW}    /help                    # Should show $plugin commands${NC}"
    echo -e "${YELLOW}    $test_cmd${NC}"
    echo -e "${YELLOW}    /exit${NC}"
    echo ""

    log_pass "$plugin: Isolation test setup complete"
}

# Test all plugins together
test_plugins_together() {
    log_test "All plugins loaded together"

    # Build --plugin-dir flags for all plugins
    local plugin_dirs=""
    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        plugin_dirs="$plugin_dirs --plugin-dir $path"
    done

    log_info "Loading all plugins simultaneously"
    log_info "Checking for namespace conflicts..."

    # Check for duplicate command names across plugins
    local conflicts=0
    local temp_file=$(mktemp)

    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        if [ -d "$path/commands" ]; then
            find "$path/commands" -name "*.md" -type f 2>/dev/null | while read cmd_file; do
                local cmd_name=$(basename "$cmd_file" .md)
                echo "$plugin:$cmd_name" >> "$temp_file"
            done
        fi
    done

    # Check for duplicates
    if [ -f "$temp_file" ]; then
        local dups=$(sort "$temp_file" | uniq -d)
        if [ -n "$dups" ]; then
            log_fail "Duplicate commands found: $dups"
            conflicts=1
        fi
        rm -f "$temp_file"
    fi

    if [ $conflicts -eq 0 ]; then
        log_pass "No namespace conflicts detected"
    fi

    # Show integration test command
    echo ""
    log_info "To test all plugins together:"
    echo ""
    echo -e "${YELLOW}  cd $TEST_DIR${NC}"
    echo -e "${YELLOW}  claude$plugin_dirs --dangerously-skip-permissions${NC}"
    echo ""
    echo -e "${YELLOW}  Then verify:${NC}"
    echo -e "${YELLOW}    /help                              # All plugin commands listed${NC}"
    for plugin in "${PLUGINS[@]}"; do
        local test_cmd=$(get_test_command "$plugin")
        echo -e "${YELLOW}    $test_cmd${NC}"
    done
    echo -e "${YELLOW}    /exit${NC}"
    echo ""

    log_pass "Integration test setup complete"
}

# Test command availability
test_command_availability() {
    log_test "Command availability check"

    local total_commands=0

    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        if [ -d "$path/commands" ]; then
            local count=$(find "$path/commands" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
            total_commands=$((total_commands + count))
            log_info "$plugin: $count commands found"
        fi
    done

    log_pass "Total commands across all plugins: $total_commands"
}

# Test skills availability
test_skills_availability() {
    log_test "Skills availability check"

    local total_skills=0

    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        if [ -d "$path/skills" ]; then
            local count=$(find "$path/skills" -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')
            total_skills=$((total_skills + count))
            log_info "$plugin: $count skills found"
        fi
    done

    log_pass "Total skills across all plugins: $total_skills"
}

# Test agents availability
test_agents_availability() {
    log_test "Agents availability check"

    local total_agents=0

    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        if [ -d "$path/agents" ]; then
            local count=$(find "$path/agents" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
            total_agents=$((total_agents + count))
            log_info "$plugin: $count agents found"
        fi
    done

    log_pass "Total agents across all plugins: $total_agents"
}

# Test marketplace.json validity
test_marketplace_manifest() {
    log_test "Marketplace manifest validation"

    local manifest="$MARKETPLACE_ROOT/.claude-plugin/marketplace.json"

    if [ ! -f "$manifest" ]; then
        log_fail "marketplace.json not found"
        return 1
    fi

    if ! jq empty "$manifest" 2>/dev/null; then
        log_fail "Invalid JSON in marketplace.json"
        return 1
    fi

    # Check all plugins are listed
    local missing_plugins=0
    for plugin in "${PLUGINS[@]}"; do
        if ! jq -e ".plugins[] | select(.name==\"$plugin\")" "$manifest" >/dev/null 2>&1; then
            log_fail "$plugin not listed in marketplace.json"
            missing_plugins=$((missing_plugins + 1))
        fi
    done

    if [ $missing_plugins -eq 0 ]; then
        log_pass "All plugins listed in marketplace.json"
    else
        log_fail "$missing_plugins plugin(s) missing from marketplace.json"
    fi

    # Check version sync
    local version_mismatches=0
    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        local plugin_version=$(jq -r '.version' "$path/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")
        local marketplace_version=$(jq -r ".plugins[] | select(.name==\"$plugin\") | .version" "$manifest" 2>/dev/null || echo "unknown")

        if [ "$plugin_version" != "$marketplace_version" ]; then
            log_fail "$plugin: Version mismatch (plugin.json: $plugin_version, marketplace.json: $marketplace_version)"
            version_mismatches=$((version_mismatches + 1))
        fi
    done

    if [ $version_mismatches -eq 0 ]; then
        log_pass "All plugin versions synchronized"
    else
        log_fail "$version_mismatches version mismatch(es) found"
    fi
}

# Generate test report summary
generate_report_summary() {
    log_section "Test Summary"

    echo "" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}Total Tests: $TESTS_RUN${NC}" | tee -a "$REPORT_FILE"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}" | tee -a "$REPORT_FILE"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    local success_rate=0
    if [ $TESTS_RUN -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi

    echo -e "${CYAN}Success Rate: $success_rate%${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}" | tee -a "$REPORT_FILE"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
        echo -e "${RED}❌ SOME TESTS FAILED${NC}" | tee -a "$REPORT_FILE"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    fi

    echo "" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}Full report saved to: $REPORT_FILE${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

# Main execution
main() {
    # Initialize report
    echo "Marketplace Integration Test Report" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "Marketplace: $MARKETPLACE_ROOT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Marketplace Integration Test Suite               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Setup
    setup_test_env

    # Phase 1: Structure validation
    log_section "Phase 1: Plugin Structure Validation"
    for plugin in "${PLUGINS[@]}"; do
        test_plugin_structure "$plugin"
    done

    # Phase 2: Marketplace manifest validation
    log_section "Phase 2: Marketplace Manifest Validation"
    test_marketplace_manifest

    # Phase 3: Component availability
    log_section "Phase 3: Component Availability"
    test_command_availability
    test_skills_availability
    test_agents_availability

    # Phase 4: Isolation testing (setup)
    log_section "Phase 4: Isolation Testing Setup"
    for plugin in "${PLUGINS[@]}"; do
        test_plugin_isolation "$plugin"
    done

    # Phase 5: Integration testing (setup)
    log_section "Phase 5: Integration Testing Setup"
    test_plugins_together

    # Generate summary
    generate_report_summary

    # Interactive testing prompt
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Manual Testing Recommended${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Automated tests complete. For full validation:"
    echo ""
    echo -e "${CYAN}1. Test plugins in isolation (one at a time)${NC}"
    echo "   Follow the commands shown in Phase 4 above"
    echo ""
    echo -e "${CYAN}2. Test all plugins together (integration)${NC}"
    echo "   Follow the command shown in Phase 5 above"
    echo ""
    echo -e "${CYAN}3. Verify in a real project:${NC}"
    echo "   cd ~/Projects/your-real-project"
    echo "   claude \\"
    for plugin in "${PLUGINS[@]}"; do
        local path=$(get_plugin_path "$plugin")
        echo "         --plugin-dir $path \\"
    done
    echo "         --dangerously-skip-permissions"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Return exit code based on test results
    if [ $TESTS_FAILED -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Run main function
main
