# Marketplace Scripts

Utility scripts for maintaining the flight505-marketplace.

## Available Scripts

### `validate-plugin-manifests.sh`

Validates all plugin.json manifests for correct format and synchronization.

**Usage:**
```bash
# Check all plugins
./scripts/validate-plugin-manifests.sh

# Auto-fix common issues
./scripts/validate-plugin-manifests.sh --fix
```

**What it validates:**
- JSON syntax
- Required fields (name, version, description, author)
- Semantic versioning format
- Skills paths (must be `./skills/name`)
- Agents paths (must be `./agents/name.md`)
- Commands paths and format
- Version sync with marketplace.json
- File existence

**See:** [Plugin Manifest Validation Guide](../docs/PLUGIN-MANIFEST-VALIDATION.md)

---

### `bump-plugin-version.sh`

Automates version bumping across plugin and marketplace files.

**Usage:**
```bash
./scripts/bump-plugin-version.sh <plugin-name> <new-version> [--dry-run]
```

**Examples:**
```bash
# Bump storybook-assistant to 2.2.0
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# Test without making changes
./scripts/bump-plugin-version.sh sdk-bridge 3.1.0 --dry-run
```

**What it does:**
1. Updates plugin.json version in submodule
2. Commits change in plugin repo
3. Updates marketplace.json plugin entry
4. Bumps marketplace version (patch)
5. Commits marketplace changes
6. Pushes to both repos
7. Creates git tag
8. Triggers webhook (30 sec delay)

**Supported plugins:**
- sdk-bridge
- storybook-assistant
- claude-project-planner
- nano-banana

---

### `dev-test.sh`

Quick development testing for individual or all plugins without installation.

**Usage:**
```bash
# Test single plugin
./scripts/dev-test.sh sdk-bridge

# Test all plugins
./scripts/dev-test.sh
```

**What it does:**
1. Validates plugin manifest (JSON syntax, required fields)
2. Checks plugin structure (commands, skills, agents, hooks, MCP)
3. Verifies executable permissions on scripts
4. Loads plugin with `--plugin-dir` for interactive testing
5. Provides detailed pass/fail report

**When to use:**
- During active plugin development
- Before releasing updates
- Testing plugin without installation
- Verifying plugin structure is correct

---

### `setup-dev-hooks.sh`

Configures development hooks for automatic validation after file edits.

**Usage:**
```bash
./scripts/setup-dev-hooks.sh
```

**What it does:**
- Creates `.claude/settings.local.json` with PostToolUse hooks
- Automatically runs validation after Write/Edit operations
- Displays confirmation on SessionStart
- Provides real-time feedback during development

**Result:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/scripts/validate-plugin-manifests.sh"
      }]
    }]
  }
}
```

**Note:** Creates `.local.json` file which is gitignored and only affects your local environment.

---

### `setup-webhooks.sh`

Deploys webhook notification workflows to all plugin repositories.

**Usage:**
```bash
./scripts/setup-webhooks.sh
```

**What it does:**
- Copies `templates/notify-marketplace.yml` to each plugin's `.github/workflows/`
- Creates `.github/workflows` directories if needed
- Skips plugins that already have the workflow
- Reports success/skip/error status for each plugin

**Next steps after running:**
1. Review changes in each plugin directory
2. Commit and push to each plugin repo
3. Verify `MARKETPLACE_UPDATE_TOKEN` secret exists in each repo
4. Test with a version bump

---

### `test-marketplace-integration.sh`

Comprehensive marketplace integration testing - verifies plugins work together without conflicts.

**Usage:**
```bash
./scripts/test-marketplace-integration.sh
```

**What it does:**
1. **Phase 1**: Validates plugin structure (manifests, required fields)
2. **Phase 2**: Validates marketplace.json (all plugins listed, versions synced)
3. **Phase 3**: Counts components (commands, skills, agents across all plugins)
4. **Phase 4**: Sets up isolation tests (test each plugin independently)
5. **Phase 5**: Sets up integration tests (test all plugins together)
6. **Generates report**: Saves detailed results to `marketplace-test-report.txt`

**Tests performed:**
- ✅ Plugin structure validation (manifests, JSON syntax)
- ✅ Namespace conflict detection (ensures no command name collisions)
- ✅ Version synchronization (plugin.json ↔ marketplace.json)
- ✅ Component availability (commands, skills, agents)
- ✅ Marketplace manifest completeness

**Output:**
- Console output with colored pass/fail indicators
- Detailed report file: `marketplace-test-report.txt`
- Instructions for manual testing (plugins in isolation and together)
- Success rate percentage

**When to use:**
- Before releasing marketplace updates
- After adding/updating plugins
- To verify plugins don't conflict
- Before distributing to users

**Example output:**
```
Phase 1: Plugin Structure Validation
✅ PASS: sdk-bridge: Structure valid (v3.0.0)
✅ PASS: storybook-assistant: Structure valid (v2.1.6)

Phase 2: Marketplace Manifest Validation
✅ PASS: All plugins listed in marketplace.json
✅ PASS: All plugin versions synchronized

Total Tests: 15
Passed: 15
Failed: 0
Success Rate: 100%

✅ ALL TESTS PASSED
```

---

## Workflow Integration

### Plugin Development Workflow

```bash
# 1. Set up auto-validation (one-time)
./scripts/setup-dev-hooks.sh

# 2. Test plugin interactively
./scripts/dev-test.sh sdk-bridge

# 3. Make changes
# (Edit files - hooks validate automatically)

# 4. Test all components
./scripts/dev-test.sh sdk-bridge

# 5. Before release, validate everything
./scripts/validate-plugin-manifests.sh

# 6. Bump version and release
./scripts/bump-plugin-version.sh sdk-bridge 2.0.1
```

### Before Committing

```bash
# Validate manifests
./scripts/validate-plugin-manifests.sh

# Fix issues
./scripts/validate-plugin-manifests.sh --fix

# Test all plugins
./scripts/dev-test.sh
```

### Version Bump Workflow

```bash
# 1. Bump version (handles all sync)
./scripts/bump-plugin-version.sh my-plugin 2.1.0

# 2. Validate everything
./scripts/validate-plugin-manifests.sh

# 3. Wait for webhook (~30 seconds)
# 4. Verify in GitHub Actions
```

### CI/CD

Both scripts are integrated into GitHub Actions:

- **validate-plugin-manifests.yml** - Runs on manifest changes
- **auto-update-plugins.yml** - Triggered by version bumps via webhook

---

## Quick Reference

| Task | Command |
|------|---------|
| **Testing** | |
| Test single plugin structure | `./scripts/dev-test.sh sdk-bridge` |
| Test all plugin structures | `./scripts/dev-test.sh` |
| Test marketplace integration | `./scripts/test-marketplace-integration.sh` |
| Setup auto-validation | `./scripts/setup-dev-hooks.sh` |
| **Validation** | |
| Check all manifests | `./scripts/validate-plugin-manifests.sh` |
| Fix manifest issues | `./scripts/validate-plugin-manifests.sh --fix` |
| **Release** | |
| Bump version | `./scripts/bump-plugin-version.sh <plugin> <version>` |
| Test version bump | `./scripts/bump-plugin-version.sh <plugin> <version> --dry-run` |
| **Setup** | |
| Deploy webhooks | `./scripts/setup-webhooks.sh` |

---

## Requirements

- **jq** - JSON processor
  - macOS: `brew install jq`
  - Ubuntu: `apt-get install jq`

- **git** - Version control (already required for marketplace)

- **bash** - Shell (already available)

---

## Troubleshooting

### Permission Denied

```bash
chmod +x scripts/*.sh
```

### jq Command Not Found

Install jq using your package manager (see Requirements)

### Version Sync Failed

Run validation to identify the mismatch:
```bash
./scripts/validate-plugin-manifests.sh
```

Then manually sync or use bump-plugin-version.sh.

### Webhook Not Triggering

1. Check GitHub Actions logs
2. Verify MARKETPLACE_UPDATE_TOKEN secret
3. See [Webhook Troubleshooting](../docs/WEBHOOK-TROUBLESHOOTING.md)

---

## Documentation

- **[PLUGIN_TESTING_GUIDE.md](../PLUGIN_TESTING_GUIDE.md)** - Comprehensive plugin testing documentation
- [CLAUDE.md](../CLAUDE.md) - Marketplace development guide
- [README.md](../README.md) - Marketplace overview
