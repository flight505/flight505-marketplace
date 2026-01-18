# Plugin Manifest Validation System - Summary

## What We Built

A comprehensive validation system to prevent plugin installation errors caused by invalid manifest files.

---

## Files Created

### 1. **Validation Script** ✅
**Location:** `scripts/validate-plugin-manifests.sh`

**Features:**
- ✅ Validates all 4 plugins (sdk-bridge, storybook-assistant, claude-project-planner, nano-banana)
- ✅ Checks JSON syntax, required fields, version format
- ✅ Validates skills format: `./skills/name`
- ✅ Validates agents format: `./agents/name.md`
- ✅ Validates commands format and file existence
- ✅ Checks version sync with marketplace.json
- ✅ Auto-fix mode for common issues (`--fix` flag)
- ✅ Color-coded output (errors, warnings, success)
- ✅ Detailed error messages with solutions

**Usage:**
```bash
# Check all plugins
./scripts/validate-plugin-manifests.sh

# Auto-fix issues
./scripts/validate-plugin-manifests.sh --fix
```

---

### 2. **GitHub Actions Workflow** ✅
**Location:** `.github/workflows/validate-plugin-manifests.yml`

**Triggers:**
- Push to any branch modifying `**/.claude-plugin/plugin.json`
- Push modifying `.claude-plugin/marketplace.json`
- Pull requests with manifest changes
- Manual trigger via workflow_dispatch

**Actions:**
- ✅ Runs validation script on every commit
- ✅ Automatically comments on PRs if validation fails
- ✅ Provides helpful instructions and common fixes
- ✅ Prevents merging invalid manifests

---

### 3. **Comprehensive Documentation** ✅
**Location:** `docs/PLUGIN-MANIFEST-VALIDATION.md`

**Contents:**
- Problem description and common errors
- Script usage guide with examples
- Auto-fix mode explanation
- GitHub Actions CI integration
- Development workflow integration
- Common validation errors and fixes
- Plugin manifest schema reference
- Troubleshooting guide
- Best practices

---

### 4. **Scripts README** ✅
**Location:** `scripts/README.md`

**Contents:**
- Quick reference for all marketplace scripts
- Usage examples
- Workflow integration guide
- Requirements and troubleshooting
- Links to detailed documentation

---

## Problem Solved

### Before ❌
```
Error: Failed to install: Plugin has an invalid manifest file at
/Users/user/.claude/plugins/cache/temp_xyz/.claude-plugin/plugin.json.
Validation errors: agents: Invalid input, skills: Invalid input
```

**Causes:**
- Invalid skill paths: `"storybook-config"` instead of `"./skills/storybook-config"`
- Invalid agent paths: `"accessibility-auditor"` instead of `"./agents/accessibility-auditor.md"`
- Version mismatches between plugin.json and marketplace.json
- No automated checking - errors discovered only during installation

### After ✅

**Automated Prevention:**
```bash
$ ./scripts/validate-plugin-manifests.sh

═══════════════════════════════════════════════════
  Plugin Manifest Validation
═══════════════════════════════════════════════════

Validating: storybook-assistant
✗ storybook-assistant: Skill 'storybook-config' must be a relative path...
✗ storybook-assistant: Agent 'accessibility-auditor' must be a relative path...

Tip: Run with --fix to automatically fix common issues
```

**One-Command Fix:**
```bash
$ ./scripts/validate-plugin-manifests.sh --fix

Attempting to fix storybook-assistant...
  → Fixed skill: storybook-config → ./skills/storybook-config
  → Fixed agent: accessibility-auditor → ./agents/accessibility-auditor.md
✓ Fixed storybook-assistant/.claude-plugin/plugin.json
✓ All plugins validated successfully!
```

---

## Current Status

### All Plugins Validated ✅

```bash
$ ./scripts/validate-plugin-manifests.sh

═══════════════════════════════════════════════════
  Plugin Manifest Validation
═══════════════════════════════════════════════════

Validating: sdk-bridge
  Path: sdk-bridge/plugins/sdk-bridge/.claude-plugin/plugin.json
✓ sdk-bridge validation passed

Validating: storybook-assistant
  Path: storybook-assistant/.claude-plugin/plugin.json
✓ storybook-assistant validation passed

Validating: claude-project-planner
  Path: claude-project-planner/.claude-plugin/plugin.json
✓ claude-project-planner validation passed

Validating: nano-banana
  Path: nano-banana/.claude-plugin/plugin.json
✓ nano-banana validation passed

═══════════════════════════════════════════════════
✅ All plugins validated successfully!
═══════════════════════════════════════════════════
```

---

## How to Use

### Daily Development

```bash
# Before committing any plugin.json changes
./scripts/validate-plugin-manifests.sh

# If issues found, auto-fix them
./scripts/validate-plugin-manifests.sh --fix

# Then commit
git add .
git commit -m "fix: update plugin manifest"
```

### Version Bumping

```bash
# Use the existing bump script (already handles marketplace sync)
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# Validate everything is correct
./scripts/validate-plugin-manifests.sh

# Push and wait for webhook
git push origin main
```

### Adding New Components

**New Skill:**
```bash
# 1. Create skill directory
mkdir -p my-plugin/skills/new-skill
touch my-plugin/skills/new-skill/SKILL.md

# 2. Add to plugin.json (CORRECT format)
jq '.skills += ["./skills/new-skill"]' \
  my-plugin/.claude-plugin/plugin.json > tmp && mv tmp my-plugin/.claude-plugin/plugin.json

# 3. Validate
./scripts/validate-plugin-manifests.sh
```

**New Agent:**
```bash
# 1. Create agent file
touch my-plugin/agents/new-agent.md

# 2. Add to plugin.json (CORRECT format)
jq '.agents += ["./agents/new-agent.md"]' \
  my-plugin/.claude-plugin/plugin.json > tmp && mv tmp my-plugin/.claude-plugin/plugin.json

# 3. Validate
./scripts/validate-plugin-manifests.sh
```

---

## Validation Rules

### Skills Format ✅
```json
{
  "skills": [
    "./skills/skill-one",      // ✅ Correct
    "./skills/skill-two"       // ✅ Correct
  ]
}
```

```json
{
  "skills": [
    "skill-one",               // ❌ Wrong - missing ./skills/ prefix
    "skills/skill-two"         // ❌ Wrong - missing ./ prefix
  ]
}
```

### Agents Format ✅
```json
{
  "agents": [
    "./agents/agent-one.md",   // ✅ Correct
    "./agents/agent-two.md"    // ✅ Correct
  ]
}
```

```json
{
  "agents": [
    "agent-one",               // ❌ Wrong - missing ./agents/ and .md
    "./agents/agent-two",      // ❌ Wrong - missing .md extension
    "agent-three.md"           // ❌ Wrong - missing ./agents/ prefix
  ]
}
```

### Version Sync ✅
**plugin.json:**
```json
{
  "name": "my-plugin",
  "version": "2.1.0"
}
```

**marketplace.json:**
```json
{
  "plugins": [
    {
      "name": "my-plugin",
      "version": "2.1.0"        // ✅ Must match plugin.json
    }
  ]
}
```

---

## CI/CD Integration

### Automatic Checks

1. **Every commit** that modifies manifests triggers validation
2. **Pull requests** get validation status and helpful comments
3. **Failed validations** block merge (until fixed)
4. **Automated comments** provide fix instructions

### PR Comment Example

When validation fails, GitHub automatically comments:

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
```

---

## Benefits

### 1. **Prevent Installation Errors** ✅
No more cryptic "Invalid input" errors during plugin installation

### 2. **Catch Issues Early** ✅
Validation runs on every commit - issues caught before users encounter them

### 3. **One-Command Fix** ✅
Auto-fix mode corrects common issues automatically

### 4. **Clear Error Messages** ✅
Detailed, actionable error messages with examples

### 5. **Automated CI** ✅
GitHub Actions validates every change automatically

### 6. **Developer Friendly** ✅
Color-coded output, helpful tips, comprehensive docs

---

## Next Steps

### Immediate
- ✅ Validation system created
- ✅ All current plugins validated
- ✅ CI/CD workflow configured
- ✅ Comprehensive documentation written

### Recommended
1. **Run validation before every commit:**
   ```bash
   ./scripts/validate-plugin-manifests.sh
   ```

2. **Use auto-fix for format issues:**
   ```bash
   ./scripts/validate-plugin-manifests.sh --fix
   ```

3. **Review validation in PRs:**
   - Check GitHub Actions status
   - Read automated comments
   - Fix issues before merging

### Optional Enhancements
- **Pre-commit hook** - Auto-validate on every commit
- **VSCode integration** - Lint plugin.json in editor
- **Schema validation** - JSON Schema for stricter validation
- **Dry-run mode** - Preview fixes without applying

---

## Documentation Links

- **Main Guide:** [Plugin Manifest Validation](docs/PLUGIN-MANIFEST-VALIDATION.md)
- **Scripts README:** [scripts/README.md](scripts/README.md)
- **Validation Script:** [scripts/validate-plugin-manifests.sh](scripts/validate-plugin-manifests.sh)
- **CI Workflow:** [.github/workflows/validate-plugin-manifests.yml](.github/workflows/validate-plugin-manifests.yml)

---

## Quick Reference

| Task | Command |
|------|---------|
| **Validate all plugins** | `./scripts/validate-plugin-manifests.sh` |
| **Auto-fix issues** | `./scripts/validate-plugin-manifests.sh --fix` |
| **Bump version** | `./scripts/bump-plugin-version.sh <plugin> <version>` |
| **Check CI status** | Visit GitHub Actions tab |
| **Read full guide** | `docs/PLUGIN-MANIFEST-VALIDATION.md` |

---

**Created:** 2026-01-18
**Status:** ✅ Production Ready
**Tested:** All 4 plugins validated successfully
