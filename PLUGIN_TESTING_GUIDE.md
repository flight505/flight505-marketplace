# Plugin Testing Guide for flight505-marketplace

## Overview

This guide provides comprehensive testing workflows for developing and testing Claude Code plugins without the install/restart/uninstall cycle. It's based on official Claude Code documentation and best practices.

---

## Quick Reference: Developing vs Testing

### **Developing a Plugin** (Active Coding)

#### For Most Plugins (storybook-assistant, nano-banana, claude-project-planner)
**Path:** `/Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace/<plugin-name>`
**Command:** `claude --plugin-dir . --dangerously-skip-permissions`

```bash
# Example: storybook-assistant
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace/storybook-assistant
claude --plugin-dir . --dangerously-skip-permissions
```

#### For sdk-bridge (Now Flattened)
**✅ UPDATE:** sdk-bridge has been flattened and now uses the same structure as other plugins.

```bash
# Example: sdk-bridge
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace/sdk-bridge
claude --plugin-dir . --dangerously-skip-permissions
```

**Plugin manifest location:**
```
sdk-bridge/.claude-plugin/plugin.json  ← plugin root (CURRENT)
```

**In Claude Code, verify the plugin loaded:**
```
/help
# Should show /sdk-bridge:start, /sdk-bridge:status, etc.
```

**Note:** There's a worktree at `.worktrees/ralph-transformation/` with the old nested structure, but that's not the main plugin.

---

### **Testing Marketplace** (Verify Integration)
**Where:** Marketplace root
**Path:** `/Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace`
**Commands:**
- `./scripts/dev-test.sh sdk-bridge` - Validate one plugin structure
- `./scripts/test-marketplace-integration.sh` - Test all plugins work together
- `./scripts/validate-plugin-manifests.sh` - Validate all plugin.json files

**Purpose:** Verify plugins work together without conflicts

---

### **Development Workflow**

#### For Most Plugins
```bash
# 1. DEVELOP (in plugin folder)
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace/storybook-assistant
# make changes, test locally
claude --plugin-dir . --dangerously-skip-permissions

# 2. TEST (back to marketplace root)
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace
./scripts/dev-test.sh storybook-assistant
./scripts/test-marketplace-integration.sh
./scripts/validate-plugin-manifests.sh
```

#### For sdk-bridge (Same as Other Plugins)
```bash
# 1. DEVELOP (in plugin root folder)
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace/sdk-bridge
# make changes, test locally
claude --plugin-dir . --dangerously-skip-permissions

# 2. TEST (back to marketplace root)
cd ~/Projects/Dev_projects/Claude_SDK/flight505-marketplace
./scripts/dev-test.sh sdk-bridge
./scripts/test-marketplace-integration.sh
```

**TL;DR:**
- Most plugins: Develop in submodule folder
- sdk-bridge: Develop in `sdk-bridge/plugins/sdk-bridge/`
- All plugins: Test from marketplace root

---

## Command Reference

| Task | Command | Run From |
|------|---------|----------|
| **Develop single plugin** | `claude --plugin-dir . --dangerously-skip-permissions` | Plugin folder |
| **Test plugin structure** | `./scripts/dev-test.sh <plugin>` | Marketplace root |
| **Test all plugins integration** | `./scripts/test-marketplace-integration.sh` | Marketplace root |
| **Validate manifests** | `./scripts/validate-plugin-manifests.sh` | Marketplace root |
| **Auto-fix manifest issues** | `./scripts/validate-plugin-manifests.sh --fix` | Marketplace root |
| **Bump plugin version** | `./scripts/bump-plugin-version.sh <plugin> <version>` | Marketplace root |

---

**Note:** Throughout this guide, you can add `--dangerously-skip-permissions` to any `claude` command to bypass permission prompts during testing:
```bash
claude --plugin-dir ./sdk-bridge --dangerously-skip-permissions
```

This is recommended for development and testing workflows to avoid repeated permission prompts.

---

## Method 1: Development Testing with `--plugin-dir` (Recommended)

### What It Does

The `--plugin-dir` flag loads your plugin directly without requiring installation. This is the **official recommended approach** for plugin development.

### Basic Usage

```bash
# Test single plugin
cd flight505-marketplace

# Most plugins (normal structure):
claude --plugin-dir ./storybook-assistant
claude --plugin-dir ./nano-banana
claude --plugin-dir ./claude-project-planner

# SDK Bridge (special nested structure):
claude --plugin-dir ./sdk-bridge/plugins/sdk-bridge

# In Claude Code session, try the commands:
/sdk-bridge:start
/sdk-bridge:status
# etc.
```

**Note:** SDK Bridge has a nested repository structure with the actual plugin at `sdk-bridge/plugins/sdk-bridge/`. The dev-test.sh script handles this automatically, but if you're using `--plugin-dir` manually, use the nested path shown above.

### Test Multiple Plugins Simultaneously

```bash
# Load all marketplace plugins at once
claude --plugin-dir ./sdk-bridge \
       --plugin-dir ./storybook-assistant \
       --plugin-dir ./claude-project-planner \
       --plugin-dir ./nano-banana
```

### Development Workflow

```bash
# 1. Start Claude Code with plugin loaded
claude --plugin-dir ./sdk-bridge

# 2. Test your commands
/sdk-bridge:start

# 3. Make changes to plugin files
# (edit commands, skills, hooks, etc.)

# 4. Exit Claude Code (Ctrl+D or /exit)

# 5. Restart with same flag
claude --plugin-dir ./sdk-bridge

# 6. Test again - changes are now loaded
```

**Key Points:**
- Changes require Claude Code restart to take effect
- No installation/uninstall needed
- Fast iteration cycle
- Test exactly what users will get

---

## Method 2: Local Development Marketplace

For testing the complete installation flow (recommended before releasing updates):

### Setup

Each plugin already has `.claude-plugin/plugin.json`. To test installation flow, create a marketplace entry:

```bash
# Already exists in this repo - marketplace.json includes all plugins
cat .claude-plugin/marketplace.json
```

### Install for Testing

```bash
# Add marketplace (one-time setup)
claude
/plugin marketplace add /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace

# Install specific plugin
/plugin install sdk-bridge@flight505-marketplace

# Test installation
/sdk-bridge:start

# Uninstall when done testing
/plugin uninstall sdk-bridge@flight505-marketplace
```

**Use this approach when:**
- Testing the installation experience
- Verifying plugin discovery works
- Checking marketplace metadata displays correctly
- Testing updates (version bumps)

---

## Method 3: Automated Testing with Hooks

### PostToolUse Hook for Validation

Create `.claude/settings.local.json` in your development environment:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/validate-plugin-manifests.sh"
          }
        ]
      }
    ]
  }
}
```

**What this does:**
- After every file write/edit, runs validation script
- Catches manifest errors immediately
- Provides feedback in real-time
- Prevents broken plugin.json from being committed

### Example: Auto-test Plugin Commands

Create a testing hook in `.claude/settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/test-plugins.sh"
          }
        ]
      }
    ]
  }
}
```

Then create `scripts/test-plugins.sh`:

```bash
#!/bin/bash
# Test all plugins for basic integrity

echo "=== Plugin Health Check ==="

# Validate all manifests
./scripts/validate-plugin-manifests.sh || exit 1

# Check for executable hook scripts
find . -name "*.sh" -path "*/hooks/*" ! -executable -print | while read script; do
    echo "⚠️  Warning: $script is not executable"
done

# Verify required files exist
for plugin in sdk-bridge storybook-assistant claude-project-planner nano-banana; do
    if [ ! -f "$plugin/.claude-plugin/plugin.json" ]; then
        echo "❌ Missing plugin.json in $plugin"
        exit 1
    fi
    echo "✅ $plugin structure valid"
done

echo "=== All plugins healthy ==="
```

Make it executable:

```bash
chmod +x scripts/test-plugins.sh
```

---

## Method 4: Interactive Testing Workflow

### Recommended Development Cycle

**For rapid iteration on a single plugin:**

```bash
# Terminal 1: Keep this running
watch -n 2 './scripts/validate-plugin-manifests.sh'

# Terminal 2: Edit plugin files
# (your editor)

# Terminal 3: Test interactively
while true; do
    echo "Starting Claude Code with sdk-bridge..."
    claude --plugin-dir ./sdk-bridge
    echo "Session ended. Press Enter to restart or Ctrl+C to exit."
    read
done
```

**For testing slash commands interactively:**

1. Start Claude Code: `claude --plugin-dir ./your-plugin`
2. Run `/help` to verify commands loaded
3. Test each command manually:
   ```
   /your-plugin:command-name arg1 arg2
   ```
4. Verify behavior matches documentation
5. Exit and modify if needed
6. Repeat

### Testing Checklist

For each plugin before release:

- [ ] **Manifest validation**: `claude plugin validate .`
- [ ] **Load with --plugin-dir**: Verify no errors
- [ ] **Check /help output**: Commands appear with descriptions
- [ ] **Test each slash command**: Try with various arguments
- [ ] **Verify skills trigger**: Ask questions matching skill descriptions
- [ ] **Test hooks fire**: Trigger relevant events (if plugin has hooks)
- [ ] **Check agents appear**: Run `/agents` (if plugin has agents)
- [ ] **Test MCP tools**: Verify tools available (if plugin has MCP servers)
- [ ] **Installation flow**: Install via marketplace, verify works
- [ ] **Uninstall cleanly**: No leftover files

---

## Debugging Tools

### Validation Commands

```bash
# From command line
claude plugin validate .

# From within Claude Code
/plugin validate .
```

**What it checks:**
- JSON syntax validity
- Required fields present
- Semantic versioning format
- Component paths exist

### Debug Mode

```bash
claude --debug --plugin-dir ./your-plugin
```

**Shows:**
- Which plugins are being loaded
- Any errors in plugin manifests
- Command, agent, and hook registration
- MCP server initialization
- Detailed error messages

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Plugin not loading | Invalid `plugin.json` | Run `claude plugin validate .` |
| Commands not appearing | Wrong directory structure | Ensure `commands/` at root, not in `.claude-plugin/` |
| Hooks not firing | Script not executable | Run `chmod +x script.sh` |
| MCP server fails | Missing `${CLAUDE_PLUGIN_ROOT}` | Use variable for all plugin paths |
| Path errors | Absolute paths used | All paths must be relative and start with `./` |

---

## Testing Best Practices

### 1. Start with --plugin-dir During Development

**Benefits:**
- Fast iteration (no install/uninstall)
- Test exactly what will be distributed
- See loading errors immediately
- No cache/settings conflicts

**Workflow:**
```bash
# Edit code
vim sdk-bridge/commands/start.md

# Test immediately
claude --plugin-dir ./sdk-bridge
/sdk-bridge:start
/exit

# Repeat
```

### 2. Use Validation Hooks During Development

**Setup once:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/validate-plugin-manifests.sh"
          }
        ]
      }
    ]
  }
}
```

**Get automatic feedback:**
- Every file edit triggers validation
- Catch errors before commit
- Maintain plugin integrity

### 3. Test Installation Flow Before Release

**Before bumping version:**
```bash
# 1. Validate
./scripts/validate-plugin-manifests.sh

# 2. Test with --plugin-dir
claude --plugin-dir ./sdk-bridge

# 3. Test marketplace installation
claude
/plugin marketplace add /path/to/flight505-marketplace
/plugin install sdk-bridge@flight505-marketplace
/sdk-bridge:start

# 4. Clean up
/plugin uninstall sdk-bridge@flight505-marketplace
/exit

# 5. Bump version if all tests pass
./scripts/bump-plugin-version.sh sdk-bridge 2.0.1
```

### 4. Use Debug Mode for Troubleshooting

```bash
# See exactly what's happening
claude --debug --plugin-dir ./problematic-plugin 2>&1 | tee debug.log

# Review loading sequence
less debug.log
```

### 5. Test Cross-Platform (If Distributing Widely)

**Hooks especially need cross-platform testing:**

```bash
# Use polyglot wrapper for hooks
# See examples/full-featured-plugin/hooks/run-hook.cmd

# Test on macOS
claude --plugin-dir ./your-plugin

# Test on Linux (if possible)
docker run -it --rm -v $(pwd):/workspace ubuntu:latest
# Install Claude Code, test plugin

# Test on Windows (if possible)
# Use WSL or native Windows
```

---

## Example: Complete Testing Session

```bash
# Start in marketplace root
cd flight505-marketplace

# 1. Validate all plugins
./scripts/validate-plugin-manifests.sh

# 2. Test sdk-bridge in isolation
claude --plugin-dir ./sdk-bridge

# Inside Claude Code:
/help  # Verify commands appear
/sdk-bridge:start  # Test main command
/sdk-bridge:status  # Test secondary commands
/exit

# 3. Test multiple plugins together
claude --plugin-dir ./sdk-bridge --plugin-dir ./nano-banana

# Inside Claude Code:
/sdk-bridge:start
/nano-banana:diagram "Create flowchart"
/exit

# 4. Test installation flow
claude
/plugin marketplace add $PWD
/plugin install sdk-bridge@flight505-marketplace
/sdk-bridge:start
/plugin uninstall sdk-bridge@flight505-marketplace
/exit

# 5. If all tests pass, bump version
./scripts/bump-plugin-version.sh sdk-bridge 2.0.1
```

---

## Integration with Your Workflow

### Recommended Setup

1. **Development**: Use `--plugin-dir` for all active work
2. **Validation**: Add PostToolUse hook for automatic checks
3. **Pre-release**: Test installation flow via local marketplace
4. **Release**: Use `bump-plugin-version.sh` script (triggers webhooks)
5. **Verification**: Wait 30 seconds, pull marketplace, verify update

### Automation Script

Create `scripts/dev-test.sh`:

```bash
#!/bin/bash
# Quick development testing for a single plugin

PLUGIN=${1:-sdk-bridge}

echo "=== Testing $PLUGIN ==="

# Validate
echo "1. Validating plugin..."
./scripts/validate-plugin-manifests.sh || exit 1

# Test loading
echo "2. Testing plugin loading..."
claude --plugin-dir ./$PLUGIN <<EOF
/help
/exit
EOF

echo "=== $PLUGIN tests passed ==="
```

Usage:

```bash
# Test specific plugin
./scripts/dev-test.sh sdk-bridge

# Test all plugins
for plugin in sdk-bridge storybook-assistant claude-project-planner nano-banana; do
    ./scripts/dev-test.sh $plugin
done
```

---

## FAQ

### Q: Do I need to restart Claude Code after every change?

**A:** Yes, when using `--plugin-dir`. Claude Code loads plugin files at startup. However, this is still much faster than the install/uninstall cycle.

### Q: Can Claude Code call slash commands programmatically during testing?

**A:** No, Claude Code cannot invoke its own slash commands from within a session. Use:
- Hooks for automated validation
- Manual testing with `--plugin-dir`
- External test scripts that parse plugin files

### Q: How do I test Skills without asking questions?

**A:** Skills are triggered by matching descriptions. To test:
1. Load plugin with `--plugin-dir`
2. Ask questions that should trigger the skill
3. Verify Claude loads the skill content
4. Check skill instructions are followed

Or examine skill files directly with `cat plugin/skills/*/SKILL.md`

### Q: Can I use pytest/jest for plugin testing?

**A:** Yes, for structural testing:

```python
# tests/test_plugin_structure.py
import json
import pathlib

def test_plugin_manifest_valid():
    manifest = pathlib.Path("sdk-bridge/.claude-plugin/plugin.json")
    assert manifest.exists()

    with open(manifest) as f:
        data = json.load(f)

    assert "name" in data
    assert "version" in data
    assert "description" in data

def test_commands_exist():
    commands_dir = pathlib.Path("sdk-bridge/commands")
    assert commands_dir.exists()

    command_files = list(commands_dir.glob("*.md"))
    assert len(command_files) > 0
```

But **behavioral testing** (slash commands, Skills) requires interactive Claude Code usage.

---

## Plugin Manifest Validation

The marketplace includes automated validation scripts to prevent plugin installation errors caused by invalid manifest files.

### Validation Scripts

**validate-plugin-manifests.sh** - Validates all plugin.json files
```bash
# Check all plugins
./scripts/validate-plugin-manifests.sh

# Auto-fix common issues (paths, formatting)
./scripts/validate-plugin-manifests.sh --fix
```

**What it validates:**
- ✅ JSON syntax correctness
- ✅ Required fields (name, version, description, author)
- ✅ Semantic versioning format (X.Y.Z)
- ✅ Skills paths must be `./skills/name`
- ✅ Agents paths must be `./agents/name.md`
- ✅ Commands paths and format
- ✅ Version synchronization with marketplace.json
- ✅ File existence for all referenced paths

**When to use:**
- Before committing any manifest changes
- After updating plugin versions
- Before releasing updates
- When debugging installation issues

**Example:**
```bash
# Before committing
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
./scripts/validate-plugin-manifests.sh

# If issues found
./scripts/validate-plugin-manifests.sh --fix

# Then commit
git add .
git commit -m "fix: update plugin manifest"
```

### CI/CD Integration

The marketplace automatically validates manifests on every commit via GitHub Actions:
- **Trigger:** Any change to `**/.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json`
- **Action:** Runs validation script and comments on PRs if validation fails
- **Benefit:** Prevents merging invalid manifests

See [docs/PLUGIN-MANIFEST-VALIDATION.md](docs/PLUGIN-MANIFEST-VALIDATION.md) for detailed validation rules and troubleshooting.

---

## Summary

**Best Workflow:**

1. ✅ **Develop with `--plugin-dir`** - fast iteration
2. ✅ **Auto-validate with hooks** - catch errors early
3. ✅ **Test interactively** - verify behavior matches intent
4. ✅ **Test installation flow** - before release
5. ✅ **Use validation scripts** - maintain quality

**Avoid:**
- ❌ Installing/uninstalling during development
- ❌ Editing installed plugin cache files
- ❌ Skipping validation before release
- ❌ Testing only one component in isolation

This approach gives you the fast feedback loop you need while maintaining confidence that your plugins work correctly for end users.
