# Plugin Manifest Validation

This document explains the plugin manifest validation system and how to use it to prevent installation errors.

## The Problem

Claude Code plugins require properly formatted `plugin.json` manifests. Common issues include:

1. **Invalid skill paths** - Must be relative paths to directories: `./skills/skill-name`
2. **Invalid agent paths** - Must be relative paths to .md files: `./agents/agent-name.md`
3. **Version mismatches** - plugin.json and marketplace.json must have matching versions
4. **Invalid version formats** - Must use semantic versioning (X.Y.Z)
5. **Missing required fields** - name, version, description, author

These issues cause installation errors like:
```
Error: Failed to install: Plugin has an invalid manifest file at
/Users/user/.claude/plugins/cache/temp_xyz/.claude-plugin/plugin.json.
Validation errors: agents: Invalid input, skills: Invalid input
```

## Validation Script

### Location
```
scripts/validate-plugin-manifests.sh
```

### Usage

**Check all plugins:**
```bash
./scripts/validate-plugin-manifests.sh
```

**Auto-fix common issues:**
```bash
./scripts/validate-plugin-manifests.sh --fix
```

### What It Checks

| Check | Description | Auto-Fix |
|-------|-------------|----------|
| **JSON syntax** | Valid JSON format | ❌ No |
| **Required fields** | name, version, description, author | ❌ No |
| **Version format** | Semantic versioning (X.Y.Z) | ❌ No |
| **Skills format** | Paths start with `./` | ✅ Yes |
| **Agents format** | Paths start with `./` and end with `.md` | ✅ Yes |
| **Commands format** | Valid paths or directory | ⚠️ Warns only |
| **Marketplace sync** | Versions match marketplace.json | ❌ No |
| **File existence** | Referenced files exist | ⚠️ Warns only |

### Example Output

```bash
$ ./scripts/validate-plugin-manifests.sh

═══════════════════════════════════════════════════
  Plugin Manifest Validation
═══════════════════════════════════════════════════

Validating: storybook-assistant
  Path: storybook-assistant/.claude-plugin/plugin.json
✗ storybook-assistant: Skill 'storybook-config' must be a relative path starting with './' (e.g., './skills/storybook-config')
✗ storybook-assistant: Agent 'accessibility-auditor' must be a relative path starting with './' (e.g., './agents/accessibility-auditor.md')

Validating: sdk-bridge
  Path: sdk-bridge/plugins/sdk-bridge/.claude-plugin/plugin.json
✓ sdk-bridge validation passed

═══════════════════════════════════════════════════
❌ Validation failed with 2 error(s)
═══════════════════════════════════════════════════

Tip: Run with --fix to automatically fix common issues:
  ./scripts/validate-plugin-manifests.sh --fix
```

### Auto-Fix Mode

The `--fix` flag automatically corrects:

**Skills:**
- `"storybook-config"` → `"./skills/storybook-config"`
- Adds `./skills/` prefix if missing

**Agents:**
- `"accessibility-auditor"` → `"./agents/accessibility-auditor.md"`
- Adds `./agents/` prefix if missing
- Adds `.md` extension if missing

**Example:**
```bash
$ ./scripts/validate-plugin-manifests.sh --fix

═══════════════════════════════════════════════════
  Plugin Manifest Validation
═══════════════════════════════════════════════════
🔧 FIX MODE ENABLED - Will attempt to auto-fix issues

Validating: storybook-assistant
  Path: storybook-assistant/.claude-plugin/plugin.json
Attempting to fix storybook-assistant...
  → Fixed skill: storybook-config → ./skills/storybook-config
  → Fixed skill: story-generation → ./skills/story-generation
  → Fixed agent: accessibility-auditor → ./agents/accessibility-auditor.md
  → Fixed agent: component-generator → ./agents/component-generator.md
✓ Fixed storybook-assistant/.claude-plugin/plugin.json
✓ Re-validating after fixes...
✓ storybook-assistant validation passed

═══════════════════════════════════════════════════
✅ All plugins validated successfully!
═══════════════════════════════════════════════════
```

## GitHub Actions CI

### Workflow
```
.github/workflows/validate-plugin-manifests.yml
```

### When It Runs

Automatically runs on:
- Push to any branch that modifies `**/.claude-plugin/plugin.json`
- Push that modifies `.claude-plugin/marketplace.json`
- Pull requests with manifest changes
- Manual trigger via workflow_dispatch

### What It Does

1. Checks out repository with submodules
2. Installs jq (JSON processor)
3. Runs validation script
4. Comments on PR if validation fails (with helpful instructions)

### Example PR Comment

When validation fails, the workflow automatically comments:

```markdown
## ❌ Plugin Manifest Validation Failed

The plugin manifest validation detected issues. Please run:

./scripts/validate-plugin-manifests.sh

To automatically fix common issues, run:

./scripts/validate-plugin-manifests.sh --fix

### Common Issues:
- **Skills** must be relative paths: `./skills/skill-name`
- **Agents** must be relative paths with .md extension: `./agents/agent-name.md`
- **Versions** must be synchronized between plugin.json and marketplace.json
- **Version format** must be semantic versioning (X.Y.Z)
```

## Integration with Development Workflow

### Before Committing Plugin Changes

```bash
# 1. Validate manifests
./scripts/validate-plugin-manifests.sh

# 2. Fix issues if found
./scripts/validate-plugin-manifests.sh --fix

# 3. Commit changes
git add .
git commit -m "fix: update plugin manifest"
```

### When Bumping Plugin Versions

The existing `bump-plugin-version.sh` script handles version updates correctly. After running it:

```bash
# Bump version (handles marketplace.json sync)
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# Validate everything is correct
./scripts/validate-plugin-manifests.sh
```

### During Plugin Development

**Adding a new skill:**
```bash
# 1. Create skill directory and SKILL.md
mkdir -p my-plugin/skills/new-skill
touch my-plugin/skills/new-skill/SKILL.md

# 2. Add to plugin.json (CORRECT format)
jq '.skills += ["./skills/new-skill"]' my-plugin/.claude-plugin/plugin.json > tmp && mv tmp my-plugin/.claude-plugin/plugin.json

# 3. Validate
./scripts/validate-plugin-manifests.sh
```

**Adding a new agent:**
```bash
# 1. Create agent file
touch my-plugin/agents/new-agent.md

# 2. Add to plugin.json (CORRECT format)
jq '.agents += ["./agents/new-agent.md"]' my-plugin/.claude-plugin/plugin.json > tmp && mv tmp my-plugin/.claude-plugin/plugin.json

# 3. Validate
./scripts/validate-plugin-manifests.sh
```

## Common Validation Errors and Fixes

### Error: "Skill must be a relative path"

**Problem:**
```json
{
  "skills": ["storybook-config"]
}
```

**Fix:**
```json
{
  "skills": ["./skills/storybook-config"]
}
```

**Or use auto-fix:**
```bash
./scripts/validate-plugin-manifests.sh --fix
```

### Error: "Agent must be a relative path"

**Problem:**
```json
{
  "agents": ["accessibility-auditor"]
}
```

**Fix:**
```json
{
  "agents": ["./agents/accessibility-auditor.md"]
}
```

### Error: "Version mismatch"

**Problem:**
- plugin.json: `"version": "2.1.0"`
- marketplace.json: `"version": "2.0.9"`

**Fix:**
```bash
# Use the version bump script (recommended)
./scripts/bump-plugin-version.sh my-plugin 2.1.0

# Or manually update marketplace.json
jq '.plugins[] |= if .name == "my-plugin" then .version = "2.1.0" else . end' \
  .claude-plugin/marketplace.json > tmp && mv tmp .claude-plugin/marketplace.json
```

### Error: "Invalid version format"

**Problem:**
```json
{
  "version": "2.1"
}
```

**Fix:**
```json
{
  "version": "2.1.0"
}
```

Use semantic versioning: `MAJOR.MINOR.PATCH`

### Warning: "Skill directory not found"

**Problem:**
```json
{
  "skills": ["./skills/missing-skill"]
}
```

**Fix:**
```bash
# Create the missing directory and SKILL.md
mkdir -p my-plugin/skills/missing-skill
touch my-plugin/skills/missing-skill/SKILL.md

# Or remove from plugin.json if not needed
jq '.skills = (.skills | map(select(. != "./skills/missing-skill")))' \
  my-plugin/.claude-plugin/plugin.json > tmp && mv tmp my-plugin/.claude-plugin/plugin.json
```

## Plugin Manifest Schema Reference

### Correct Format

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "My awesome plugin",
  "author": {
    "name": "Your Name",
    "url": "https://github.com/username"
  },
  "license": "MIT",
  "repository": "https://github.com/username/my-plugin",
  "homepage": "https://github.com/username/my-plugin",
  "keywords": ["tag1", "tag2"],
  "skills": [
    "./skills/skill-one",
    "./skills/skill-two"
  ],
  "agents": [
    "./agents/agent-one.md",
    "./agents/agent-two.md"
  ],
  "commands": [
    "./commands/command-one.md",
    "./commands/command-two.md"
  ],
  "hooks": "./.claude-plugin/hooks.json"
}
```

### Path Rules

| Component | Format | Example |
|-----------|--------|---------|
| **Skills** | `./skills/<name>` | `./skills/storybook-config` |
| **Agents** | `./agents/<name>.md` | `./agents/component-generator.md` |
| **Commands** | `./commands/<name>.md` | `./commands/help.md` |
| **Commands (dir)** | `./commands` | `./commands` |
| **Hooks** | `./.claude-plugin/hooks.json` | `./.claude-plugin/hooks.json` |

### Required Fields

- `name` (string) - Plugin name (kebab-case)
- `version` (string) - Semantic version (X.Y.Z)
- `description` (string) - Brief description
- `author` (object) - Author name and URL

### Optional Fields

- `license` (string) - License identifier
- `repository` (string) - Git repository URL
- `homepage` (string) - Homepage URL
- `keywords` (array) - Search tags
- `skills` (array) - Skill paths
- `agents` (array) - Agent file paths
- `commands` (array or string) - Command files or directory
- `hooks` (string) - Hooks configuration path

## Troubleshooting

### Script Not Executable

```bash
chmod +x scripts/validate-plugin-manifests.sh
```

### jq Not Installed

**macOS:**
```bash
brew install jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq
```

### Validation Passes But Installation Still Fails

1. Check Claude Code version compatibility
2. Verify all referenced files exist
3. Check for syntax errors in markdown files
4. Validate hooks.json format if present
5. Clear Claude Code plugin cache:
   ```bash
   rm -rf ~/.claude/plugins/cache/temp_*
   ```

## Best Practices

1. **Run validation before every commit** that touches plugin.json
2. **Use auto-fix for format issues** - it's safe and fast
3. **Use bump-plugin-version.sh** for version updates
4. **Keep versions synchronized** between plugin.json and marketplace.json
5. **Commit validation script changes** along with manifest updates
6. **Check CI results** before merging PRs

## Related Documentation

- [Plugin Development Guide](../CLAUDE.md)
- [Marketplace Structure](../README.md)
- [Version Bump Script](../scripts/bump-plugin-version.sh)
- [Webhook System](./WEBHOOK-TROUBLESHOOTING.md)
