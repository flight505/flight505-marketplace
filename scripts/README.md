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

## Workflow Integration

### Before Committing

```bash
# Validate manifests
./scripts/validate-plugin-manifests.sh

# Fix issues
./scripts/validate-plugin-manifests.sh --fix
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
| Check all manifests | `./scripts/validate-plugin-manifests.sh` |
| Fix manifest issues | `./scripts/validate-plugin-manifests.sh --fix` |
| Bump version | `./scripts/bump-plugin-version.sh <plugin> <version>` |
| Test version bump | `./scripts/bump-plugin-version.sh <plugin> <version> --dry-run` |
| Check specific plugin | Edit script to only check one plugin |

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

- [Plugin Manifest Validation](../docs/PLUGIN-MANIFEST-VALIDATION.md) - Complete validation guide
- [CLAUDE.md](../CLAUDE.md) - Marketplace development guide
- [README.md](../README.md) - Marketplace overview
