---
description: "Initialize project for SDK bridge (creates state files, validates harness)"
argument-hint: "[project-dir]"
allowed-tools: ["Bash", "Read", "Write"]
---

# Initialize Project for SDK Bridge

I'll set up this project for SDK bridge workflows.

## Step 1: Validate Prerequisites

Let me check that the required tools are installed:

```bash
# Check harness exists
if [ ! -f ~/.claude/skills/long-running-agent/harness/autonomous_agent.py ]; then
  echo "❌ ERROR: Harness not found"
  echo ""
  echo "The long-running-agent harness is required but not installed."
  echo ""
  echo "To install, run: /sdk-bridge:lra-setup"
  echo ""
  echo "This will set up the autonomous agent harness that sdk-bridge uses."
  exit 1
fi

echo "✅ Harness found at ~/.claude/skills/long-running-agent/harness/autonomous_agent.py"

# Check venv exists
VENV_PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"
if [ ! -f "$VENV_PYTHON" ]; then
  echo "❌ ERROR: SDK virtual environment not found"
  echo ""
  echo "Run /sdk-bridge:lra-setup to install the harness and SDK"
  exit 1
fi

# Check SDK installed in venv
if ! "$VENV_PYTHON" -c "import claude_agent_sdk" 2>/dev/null; then
  echo "❌ ERROR: claude-agent-sdk not installed in venv"
  echo ""
  echo "Run /sdk-bridge:lra-setup to reinstall"
  exit 1
fi

echo "✅ Claude Agent SDK installed (in venv)"

# Check git
if ! command -v git &> /dev/null; then
  echo "⚠️  WARNING: git not found (recommended for version control)"
fi

echo ""
```

## Step 2: Create .claude Directory

```bash
mkdir -p .claude
echo "✅ Created .claude directory"
```

## Step 3: Create Configuration File

I'll create `.claude/sdk-bridge.local.md` with sensible defaults:

```bash
cat > .claude/sdk-bridge.local.md << 'EOF'
---
# v1.4.0 Settings
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 20
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: false
log_level: INFO
webhook_url:

# v2.0 Settings (Phases 1-3)
enable_v2_features: true
enable_semantic_memory: true
enable_adaptive_models: true
enable_approval_nodes: true
max_inner_loops: 5

# v2.0 Phase 3: Parallel Execution
enable_parallel_execution: false
max_parallel_workers: 3
---

# SDK Bridge Configuration

This project is configured for SDK bridge workflows.

## v1.4.0 Settings

- **model**: Claude model for SDK sessions
  - `claude-sonnet-4-5-20250929` (default, fast and capable)
  - `claude-opus-4-5-20251101` (most capable, slower and more expensive)

- **max_sessions**: Total sessions before giving up (default: 20)

- **reserve_sessions**: Keep N sessions for manual recovery (default: 2)

- **progress_stall_threshold**: Stop if no progress for N sessions (default: 3)

- **auto_handoff_after_plan**: Automatically handoff after /plan creates feature_list.json (default: false)

- **log_level**: Logging verbosity (DEBUG, INFO, WARNING, ERROR)

- **webhook_url**: Optional webhook for notifications

## Advanced Features

- **enable_v2_features**: Enable all advanced features (default: true)
  - Hybrid loops (same-session + multi-session)
  - Semantic memory (cross-project learning)
  - Adaptive model selection (Sonnet/Opus routing)
  - Approval workflow for high-risk changes

- **enable_semantic_memory**: Cross-project learning (default: true)
  - Learns from past implementations across projects
  - Suggests solutions based on similar features

- **enable_adaptive_models**: Smart model selection (default: true)
  - Routes complex/high-risk features to Opus
  - Uses Sonnet for standard features
  - Escalates to Opus on retry failures

- **enable_approval_nodes**: Human-in-the-loop approvals (default: true)
  - Pauses for high-risk operations
  - Presents alternatives and impact analysis
  - Non-blocking (other features continue)

- **max_inner_loops**: Same-session retries before starting new session (default: 5)
  - Self-healing pattern for quick fixes
  - Reduces API costs and time

- **enable_parallel_execution**: Enable parallel feature implementation (default: false)
  - Requires running `/sdk-bridge:plan` first to analyze dependencies
  - Launches multiple workers for independent features
  - Git-isolated branches per worker
  - Significant speedup for projects with many independent features
  - Enable with: `/sdk-bridge:enable-parallel`

- **max_parallel_workers**: Maximum concurrent workers (default: 3)
  - More workers = faster completion for independent features
  - Each worker uses API tokens and git branches
  - Recommended: 2-4 workers depending on feature independence

## Usage

After initialization:

1. Create feature_list.json (use `/plan` or manually)
2. (Optional) Run `/sdk-bridge:plan` to analyze dependencies for parallel execution
3. (Optional) Run `/sdk-bridge:enable-parallel` if plan recommends it
4. Run `/sdk-bridge:handoff` to start autonomous work
5. Monitor with `/sdk-bridge:status` or `/sdk-bridge:observe` (for parallel)
6. Resume with `/sdk-bridge:resume` when complete

## Parallel Execution Workflow

If you have many independent features:

1. `/sdk-bridge:plan` - Analyzes dependencies, creates execution plan
2. Review the dependency graph and estimated speedup
3. `/sdk-bridge:enable-parallel` - Enables parallel mode if beneficial
4. `/sdk-bridge:handoff` - Launches multiple workers automatically
5. `/sdk-bridge:observe` - Monitor all workers in real-time

## Configuration

After initialization:

1. Create feature_list.json (use `/plan` or manually)
2. Run `/sdk-bridge:handoff` to start autonomous work
3. Monitor with `/sdk-bridge:status`
4. Resume with `/sdk-bridge:resume` when complete

## Configuration

You can edit this file to customize settings for this project.
EOF

echo "✅ Created .claude/sdk-bridge.local.md"
```

## Step 4: Check for Existing Files

```bash
echo ""
echo "Checking for existing project files..."

if [ -f "feature_list.json" ]; then
  FEATURES_TOTAL=$(jq 'length' feature_list.json 2>/dev/null || echo "?")
  echo "  ✅ feature_list.json exists ($FEATURES_TOTAL features)"
else
  echo "  ⚠️  feature_list.json not found (create with /plan)"
fi

if [ -f "CLAUDE.md" ] || [ -f ".claude/CLAUDE.md" ]; then
  echo "  ✅ CLAUDE.md exists (session protocol)"
else
  echo "  ℹ️  CLAUDE.md not found (optional but recommended)"
fi

if [ -d ".git" ]; then
  echo "  ✅ Git repository initialized"
else
  echo "  ⚠️  Not a git repository (recommended: git init)"
fi

echo ""
```

## Summary

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SDK Bridge Initialized"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  • Model: claude-sonnet-4-5-20250929"
echo "  • Max sessions: 20"
echo "  • Config file: .claude/sdk-bridge.local.md"
echo ""
echo "Next Steps:"
echo ""
echo "1. Create a plan:"
echo "   /plan"
echo "   (This creates feature_list.json with implementation tasks)"
echo ""
echo "2. Hand off to SDK:"
echo "   /sdk-bridge:handoff"
echo "   (Launches autonomous agent to work on features)"
echo ""
echo "3. Monitor progress:"
echo "   /sdk-bridge:status"
echo "   (Check feature completion and session progress)"
echo ""
echo "4. Resume when complete:"
echo "   /sdk-bridge:resume"
echo "   (Review SDK work and continue in CLI)"
echo ""
```
