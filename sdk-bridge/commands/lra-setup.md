---
description: "Install the long-running-agent harness required by SDK bridge"
allowed-tools: ["Bash", "Read", "Write"]
---

# Setup Long-Running Agent Harness

I'll set up the SDK Bridge harness scripts in your `~/.claude` directory. This includes the v1.4.0 core harness and all v2.0 components (hybrid loops, semantic memory, adaptive intelligence, parallel execution).

## Step 1: Create Directories

```bash
mkdir -p ~/.claude/skills/long-running-agent/harness
echo "✅ Created directory: ~/.claude/skills/long-running-agent/harness"
```

## Step 2: Install Harness Scripts

```bash
echo "Installing SDK Bridge harness scripts..."
echo ""

# All harness scripts (v1.4.0 + v2.0 complete set)
SCRIPTS=(
  "autonomous_agent.py"      # v1.4.0 core harness
  "hybrid_loop_agent.py"     # v2.0 Phase 1: Hybrid loops
  "semantic_memory.py"       # v2.0 Phase 1: Cross-project learning
  "model_selector.py"        # v2.0 Phase 2: Adaptive model selection
  "approval_system.py"       # v2.0 Phase 2: Risk assessment & approvals
  "dependency_graph.py"      # v2.0 Phase 3: Parallel execution planning
  "parallel_coordinator.py"  # v2.0 Phase 3: Multi-worker orchestration
)

INSTALLED=0
MISSING=0

for script in "${SCRIPTS[@]}"; do
  # Extract just the filename (remove comments)
  script_name=$(echo "$script" | awk '{print $1}')
  src="${CLAUDE_PLUGIN_ROOT}/scripts/$script_name"
  dst="$HOME/.claude/skills/long-running-agent/harness/$script_name"

  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  ✅ $script_name"
    INSTALLED=$((INSTALLED + 1))
  else
    echo "  ⚠️  $script_name (not found in plugin)"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
echo "Installation Summary:"
echo "  • Installed: $INSTALLED scripts"
if [ $MISSING -gt 0 ]; then
  echo "  • Missing: $MISSING scripts (plugin may need update)"
fi
echo ""
```

## Step 3: Create Virtual Environment and Install SDK

```bash
VENV_DIR="$HOME/.claude/skills/long-running-agent/.venv"

if [ ! -d "$VENV_DIR" ]; then
  echo "Creating virtual environment..."

  # Try uv first (faster), fall back to python3 -m venv
  if command -v uv &> /dev/null; then
    uv venv "$VENV_DIR"
    echo "✅ Created venv using uv"
  else
    python3 -m venv "$VENV_DIR"
    echo "✅ Created venv using python3 -m venv"
  fi
else
  echo "✅ Virtual environment already exists"
fi
```

```bash
VENV_DIR="$HOME/.claude/skills/long-running-agent/.venv"
echo "Installing Claude Agent SDK..."

# Activate venv using portable syntax
. "$VENV_DIR/bin/activate"

# Try uv pip first, fall back to pip
if command -v uv &> /dev/null; then
  uv pip install claude-agent-sdk
  echo "✅ Installed using uv pip"
else
  pip install claude-agent-sdk
  echo "✅ Installed using pip"
fi

deactivate
echo "✅ Claude Agent SDK installed"
```

## Step 4: Verify Installation

```bash
~/.claude/skills/long-running-agent/.venv/bin/python -c "import claude_agent_sdk; print(f'✅ Claude Agent SDK v{claude_agent_sdk.__version__} ready')"
```

## Step 5: Validate Python Module Imports

```bash
echo ""
echo "Validating Python module imports..."

VENV_PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"

# Test v2.0 module imports
$VENV_PYTHON -c "
import sys
import os
sys.path.insert(0, os.path.expanduser('~/.claude/skills/long-running-agent/harness'))

modules_tested = 0
modules_passed = 0
modules_failed = []

# Test each v2.0 module
test_modules = [
    ('semantic_memory', 'SemanticMemory, Feature, Solution'),
    ('model_selector', 'AdaptiveModelSelector, ModelPerformanceTracker'),
    ('approval_system', 'ApprovalQueue, RiskAssessor, RiskLevel'),
    ('dependency_graph', 'DependencyGraph'),
    ('parallel_coordinator', 'ParallelCoordinator'),
    ('hybrid_loop_agent', 'HybridLoopAgent'),
]

for module_name, classes in test_modules:
    modules_tested += 1
    try:
        exec(f'from {module_name} import {classes}')
        modules_passed += 1
        print(f'  ✅ {module_name}')
    except ImportError as e:
        modules_failed.append((module_name, str(e)))
        print(f'  ⚠️  {module_name} (import failed)')

print()
print(f'Module Validation: {modules_passed}/{modules_tested} passed')

if modules_failed:
    print()
    print('Failed modules (v2.0 features may be limited):')
    for module, error in modules_failed:
        print(f'  • {module}: {error}')
    print()
    print('Note: v1.4.0 features will work. Run /plugin update to get latest scripts.')
else:
    print('✅ All v2.0 modules loaded successfully')
" 2>&1
```

## Summary

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SDK Bridge Harness Installation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Installed Components:"
echo "  📂 Location: ~/.claude/skills/long-running-agent/"
echo ""
echo "  Harness Scripts (7):"
echo "    • autonomous_agent.py      (v1.4.0 core)"
echo "    • hybrid_loop_agent.py     (v2.0 hybrid loops)"
echo "    • semantic_memory.py       (v2.0 cross-project learning)"
echo "    • model_selector.py        (v2.0 adaptive models)"
echo "    • approval_system.py       (v2.0 risk assessment)"
echo "    • dependency_graph.py      (v2.0 parallel planning)"
echo "    • parallel_coordinator.py  (v2.0 orchestration)"
echo ""
echo "  Python Environment:"
echo "    • Virtual environment: .venv/"
echo "    • Claude Agent SDK: $(~/.claude/skills/long-running-agent/.venv/bin/python -c 'import claude_agent_sdk; print(claude_agent_sdk.__version__)')"
echo ""
echo "Next Steps:"
echo "  1. Initialize your project:"
echo "     /sdk-bridge:init"
echo ""
echo "  2. Create a feature plan (or use existing feature_list.json)"
echo ""
echo "  3. Hand off to autonomous agent:"
echo "     /sdk-bridge:handoff"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```
