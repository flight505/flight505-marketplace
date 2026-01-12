# Migration Guide: Repository Rename

**Effective Date:** Phase 2 Complete
**Impact:** Low (GitHub redirects handle most cases)

## What Changed

We've simplified repository names by removing redundant suffixes:

| Old Name | New Name |
|----------|----------|
| `sdk-bridge-marketplace` | `sdk-bridge` |
| `storybook-assistant-plugin` | `storybook-assistant` |

## For Plugin Users

**Good news:** GitHub automatically redirects old URLs to new ones, so most installations will continue working without changes.

### If You Want to Update (Optional)

For a clean installation with new names:

```bash
# Update marketplace
/plugin marketplace remove flight505/flight505-marketplace
/plugin marketplace add flight505/flight505-marketplace

# Your plugins will automatically use new URLs on next update
/plugin update sdk-bridge@flight505-plugins
/plugin update storybook-assistant@flight505-plugins
```

### New Installation Commands

For fresh installations:

```bash
# Add marketplace
/plugin marketplace add flight505/flight505-marketplace

# Install plugins
/plugin install sdk-bridge@flight505-plugins
/plugin install storybook-assistant@flight505-plugins
/plugin install claude-project-planner@flight505-plugins
/plugin install nano-banana@flight505-plugins
```

## For Marketplace Maintainers

If you have a local clone of the marketplace:

```bash
cd flight505-marketplace

# Pull latest changes
git pull origin main

# Update submodules to use new URLs
git submodule sync --recursive
git submodule update --init --recursive
```

## For Contributors

If you contribute to the individual plugins:

### SDK Bridge

```bash
# Update remote URL
git remote set-url origin https://github.com/flight505/sdk-bridge.git

# Verify
git remote -v
```

### Storybook Assistant

```bash
# Update remote URL
git remote set-url origin https://github.com/flight505/storybook-assistant.git

# Verify
git remote -v
```

## GitHub Redirects

GitHub automatically redirects:
- `https://github.com/flight505/sdk-bridge-marketplace` → `https://github.com/flight505/sdk-bridge`
- `https://github.com/flight505/storybook-assistant-plugin` → `https://github.com/flight505/storybook-assistant`

This means:
- ✅ Old URLs in bookmarks still work
- ✅ Old clone URLs still work
- ✅ Old documentation links still work
- ✅ No breaking changes for end users

## Rationale

The old names were redundant:
- `-marketplace` suffix: Already clear from context (it's in flight505-marketplace)
- `-plugin` suffix: Already clear from context (it's a Claude Code plugin)

New names are cleaner and match the plugin names users actually use:
- Users install `sdk-bridge`, not `sdk-bridge-marketplace`
- Users install `storybook-assistant`, not `storybook-assistant-plugin`

## Support

If you encounter any issues:
- GitHub Issues: https://github.com/flight505/flight505-marketplace/issues
- Check that you're using the latest marketplace version

## Timeline

- **Phase 1:** Completed - Fixed sdk-bridge submodule
- **Phase 2:** In Progress - Repository renames and local updates
- **Phase 3:** Planned - Event-based webhook triggers

---

**Note:** This is a non-breaking change. Old URLs continue to work via GitHub redirects.
