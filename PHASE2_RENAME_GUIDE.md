# Phase 2: Repository Rename Guide

**Status:** Ready to execute
**Breaking Change:** Yes - existing users will need to update their installations

## Overview

Simplify repository naming by removing redundant suffixes:
- `sdk-bridge-marketplace` → `sdk-bridge`
- `storybook-assistant-plugin` → `storybook-assistant`

This makes the namespace cleaner since plugins are already in a marketplace context.

---

## Step 1: Rename GitHub Repositories

**IMPORTANT:** Do these renames on GitHub FIRST, before making local changes.

### Rename sdk-bridge-marketplace

1. Go to https://github.com/flight505/sdk-bridge-marketplace
2. Click **Settings** tab
3. Scroll to **Repository name** section
4. Change name from `sdk-bridge-marketplace` to `sdk-bridge`
5. Click **Rename** button
6. GitHub will automatically set up redirects from old URL to new URL

### Rename storybook-assistant-plugin

1. Go to https://github.com/flight505/storybook-assistant-plugin
2. Click **Settings** tab
3. Scroll to **Repository name** section
4. Change name from `storybook-assistant-plugin` to `storybook-assistant`
5. Click **Rename** button
6. GitHub will automatically set up redirects from old URL to new URL

**Note:** GitHub's redirects will continue working, but we'll update submodule URLs to use the new canonical names.

---

## Step 2: Update Local Configuration (Automated)

After GitHub renames are complete, run the following script to update local configuration:

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace

# This will:
# - Update .gitmodules with new URLs
# - Sync submodule remote URLs
# - Update README documentation
# - Commit changes
```

The script is prepared and ready to execute once GitHub renames are complete.

---

## Step 3: Verify Changes

After updates:

```bash
# Check submodules point to new URLs
git submodule status
cat .gitmodules

# Verify submodules can fetch
git submodule update --remote --recursive
```

---

## Step 4: Push Changes

```bash
git push origin main
```

---

## Migration for Existing Users

Users who already installed plugins will need to update:

### Option A: Clean Reinstall (Recommended)

```bash
# Uninstall old versions
/plugin uninstall sdk-bridge@flight505-plugins
/plugin uninstall storybook-assistant@flight505-plugins

# Update marketplace
/plugin marketplace remove flight505/flight505-marketplace
/plugin marketplace add flight505/flight505-marketplace

# Reinstall with new names
/plugin install sdk-bridge@flight505-plugins
/plugin install storybook-assistant@flight505-plugins
```

### Option B: Update in Place

The marketplace metadata already uses the correct plugin names (`sdk-bridge`, `storybook-assistant`), so the change is mostly transparent to end users. The submodule URL changes only affect marketplace maintainers.

---

## Rollback Plan

If issues arise:

1. Rename repos back on GitHub (or wait for redirects to work)
2. Revert local changes: `git revert HEAD`
3. Push: `git push origin main`

GitHub's automatic redirects mean old URLs will continue working even after rename.

---

## Checklist

- [ ] Rename `sdk-bridge-marketplace` → `sdk-bridge` on GitHub
- [ ] Rename `storybook-assistant-plugin` → `storybook-assistant` on GitHub
- [ ] Update `.gitmodules` with new URLs
- [ ] Sync submodule remote URLs
- [ ] Update README documentation
- [ ] Test submodule updates
- [ ] Commit and push changes
- [ ] Notify users of breaking change (if needed)

---

## Timeline

**Estimated time:** 10 minutes
- GitHub renames: 2 minutes
- Local updates: 5 minutes
- Testing: 3 minutes

**When to execute:** Anytime - GitHub redirects minimize disruption
