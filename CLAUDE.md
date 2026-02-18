# flight505-marketplace - Critical Instructions

## Overview

This is the **flight505-marketplace** repository containing 5 Claude Code plugins as git submodules. This CLAUDE.md contains critical instructions for maintaining the marketplace infrastructure.

**Repository:** https://github.com/flight505/flight505-marketplace
**Current Version:** 1.4.2
**Plugins:** sdk-bridge, taskplex, storybook-assistant, claude-project-planner, nano-banana

---

## 🤖 Automatic Validation System

**Status:** ✅ ACTIVE - Self-correcting hooks enabled

This marketplace uses **intelligent PostToolUse hooks** that automatically validate manifests and enforce quality standards. No manual validation scripts needed!

### How It Works

**1. Real-Time Validation**
- Edit any `plugin.json` → validator runs automatically
- Edit `marketplace.json` → sync validator runs automatically
- Issues found → Claude sees errors and **fixes them immediately**
- No manual intervention needed

**2. What Gets Validated**

`.claude/hooks/validators/plugin-manifest-validator.py`:
- ✅ JSON syntax correctness
- ✅ Required fields (name, version, description, author)
- ✅ Semantic versioning format (X.Y.Z)
- ✅ Skills paths (must start with `./`)
- ✅ Agents paths (must start with `./` and end with `.md`)
- ✅ Commands format and paths
- ✅ File/directory existence

`.claude/hooks/validators/marketplace-sync-validator.py`:
- ✅ Plugin exists in marketplace.json
- ✅ Version synchronization between plugin.json and marketplace.json
- ✅ Prevents version drift

**3. Self-Correcting Workflow**

```
Edit plugin.json
    ↓
Validator runs automatically (PostToolUse hook)
    ↓
Error found? → Claude sees error message
    ↓
Claude fixes the issue
    ↓
Validator runs again
    ↓
✅ Pass → Changes saved
```

**4. Benefits**

- ❌ **No more manual** `./scripts/validate-plugin-manifests.sh`
- ✅ **Immediate feedback** - catch issues as you work
- ✅ **Self-correcting** - Claude fixes issues automatically
- ✅ **Always valid** - impossible to save invalid manifests
- ✅ **Faster development** - no manual validation step

### For Developers

**The hooks are transparent:**
- They run automatically after Edit/Write
- You see helpful error messages if validation fails
- Claude fixes issues and validators re-run
- Everything just works

**Manual validation still available:**
```bash
# If you want to manually validate (not needed with hooks active)
./scripts/validate-plugin-manifests.sh

# Or test validators directly
echo '{"tool_name":"Edit","tool_input":{"file_path":"sdk-bridge/.claude-plugin/plugin.json"}}' | \
    .claude/hooks/validators/plugin-manifest-validator.py
```

**Validator logs for debugging:**
```bash
tail -f .claude/hooks/validators/*.log
```

---

## Plugin Structure

Each plugin is a **git submodule** pointing to its own repository:

```
flight505-marketplace/
├── sdk-bridge/                    → github.com/flight505/sdk-bridge
├── taskplex/                      → github.com/flight505/taskplex
├── storybook-assistant/           → github.com/flight505/storybook-assistant
├── claude-project-planner/        → github.com/flight505/claude-project-planner
└── nano-banana/                   → github.com/flight505/nano-banana
```

**Critical files in each plugin:**
- `CLAUDE.md` - Developer instructions
- `README.md` - Public documentation
- `CONTEXT_<plugin-name>.md` - Architecture and consolidated context
- `.claude-plugin/plugin.json` - Plugin manifest

---

## marketplace.json Management

**Location:** `.claude-plugin/marketplace.json`

**Official Schema:** https://github.com/anthropics/claude-code/blob/main/docs/plugin-marketplace.md

### Critical Rules (DOS & DON'TS)

✅ **DO:**
- Bump marketplace `version` when plugin versions change
- Keep `source` paths relative (e.g., `"./sdk-bridge"`)
- Match plugin `name` to submodule directory name
- Update `version` field to match plugin's plugin.json version
- Keep `description` concise (1-2 sentences)
- Use semantic versioning (MAJOR.MINOR.PATCH)

❌ **DON'T:**
- Use absolute paths in `source` field
- Forget to update marketplace version after plugin updates
- Change plugin names without updating submodule directory
- Skip version bumps (breaks auto-update detection)
- Use underscores in plugin names (use hyphens)

### Example Entry

```json
{
  "name": "sdk-bridge",
  "description": "SOTA autonomous development with generative UI...",
  "version": "2.0.0",
  "author": {
    "name": "Jesper Vang",
    "url": "https://github.com/flight505"
  },
  "source": "./sdk-bridge",
  "category": "workflows",
  "keywords": ["autonomous", "agent-sdk", "long-running"]
}
```

---

## Webhook System (Real-Time Updates)

**Status:** ✅ Operational (19-30 second latency)

### Architecture

```
Plugin Repo (version bump)
    ↓ push to main
notify-marketplace.yml workflow
    ↓ repository_dispatch event
flight505-marketplace
    ↓ auto-update-plugins.yml workflow
Updates marketplace.json + submodule pointer
    ↓ ~30 seconds total
Users get updated plugin
```

### How It Works

1. **Plugin repo** - Developer bumps version in `.claude-plugin/plugin.json`
2. **Webhook trigger** - `.github/workflows/notify-marketplace.yml` detects version change
3. **Marketplace update** - Sends `repository_dispatch` to marketplace repo
4. **Auto-update** - `.github/workflows/auto-update-plugins.yml` updates submodule and marketplace.json
5. **Commit & push** - Changes committed with "chore: auto-update <plugin> to vX.Y.Z"

### Critical Requirements

**Each plugin repo needs:**
- `.github/workflows/notify-marketplace.yml` workflow
- `MARKETPLACE_UPDATE_TOKEN` secret (GitHub PAT with `repo` scope)

**Marketplace repo needs:**
- Webhook-ready workflow with `repository_dispatch` trigger
- Automated submodule update logic

### Trigger Conditions

**Webhooks ONLY trigger on:**
- Version changes in `.claude-plugin/plugin.json`
- Push to main branch

**Webhooks DO NOT trigger on:**
- Documentation changes (README, CLAUDE.md, etc.)
- Code changes without version bump
- Other branches

**Rationale:** Reduces noise, follows semantic versioning, indicates intentional releases

### Testing Webhooks

```bash
# 1. Bump version in plugin
cd nano-banana
jq '.version = "1.0.6"' .claude-plugin/plugin.json > tmp && mv tmp .claude-plugin/plugin.json
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 1.0.6"
git push origin main

# 2. Monitor webhook
gh run list --repo flight505/nano-banana --workflow notify-marketplace.yml --limit 1
gh run list --repo flight505/flight505-marketplace --workflow auto-update-plugins.yml --limit 1

# 3. Verify update (~30 seconds)
cd ../
git pull origin main
cat .claude-plugin/marketplace.json | jq '.plugins[] | select(.name=="nano-banana")'
```

---

## Plugin Tracking

### Current Plugins (5)

| Plugin | Version | Repo | Status |
|--------|---------|------|--------|
| **sdk-bridge** | 4.8.1 | [github.com/flight505/sdk-bridge](https://github.com/flight505/sdk-bridge) | ✅ Active |
| **taskplex** | 2.0.1 | [github.com/flight505/taskplex](https://github.com/flight505/taskplex) | ✅ Active |
| **storybook-assistant** | 2.2.0 | [github.com/flight505/storybook-assistant](https://github.com/flight505/storybook-assistant) | ✅ Active |
| **claude-project-planner** | 1.4.6 | [github.com/flight505/claude-project-planner](https://github.com/flight505/claude-project-planner) | ✅ Active |
| **nano-banana** | 1.2.0 | [github.com/flight505/nano-banana](https://github.com/flight505/nano-banana) | ✅ Active |

### Version Update Checklist

**Recommended approach:** Use `./scripts/bump-plugin-version.sh` (see Maintenance Scripts section)

**Manual approach** (if needed):

1. ✅ Plugin repo: Update `.claude-plugin/plugin.json`
2. ✅ Plugin repo: Commit and push to main
3. ✅ Webhook: Auto-triggers (verify in Actions tab)
4. ✅ Marketplace: Auto-updates within 30 seconds
5. ✅ Verify: `git pull` and check marketplace.json
6. ✅ Run `./scripts/validate-plugin-manifests.sh` to verify sync

### Manual Update (if webhook fails)

```bash
# Update submodule
git submodule update --remote --merge <plugin-name>

# Update marketplace.json
cd .claude-plugin
jq '.plugins |= map(if .name == "<plugin-name>" then .version = "<new-version>" else . end)' marketplace.json > tmp && mv tmp marketplace.json
jq '.version = "<new-marketplace-version>"' marketplace.json > tmp && mv tmp marketplace.json

# Commit
cd ..
git add <plugin-name> .claude-plugin/marketplace.json
git commit -m "chore: update <plugin-name> to v<new-version>"
git push origin main
```

---

## Submodule Management

### Clone Marketplace (First Time)

```bash
git clone --recurse-submodules https://github.com/flight505/flight505-marketplace.git
cd flight505-marketplace
```

### Update All Submodules

```bash
git submodule update --remote --merge
git add .
git commit -m "chore: update all submodules"
git push origin main
```

### Work on Plugin

```bash
cd sdk-bridge
# Make changes
git add .
git commit -m "feat: add new feature"
git push origin main

# Return to marketplace and update pointer
cd ..
git add sdk-bridge
git commit -m "chore: update sdk-bridge submodule"
git push origin main
```

### Add New Plugin

```bash
# 1. Add as submodule
git submodule add https://github.com/flight505/<new-plugin>.git <new-plugin>

# 2. Update marketplace.json
cd .claude-plugin
jq '.plugins += [{"name": "<new-plugin>", "version": "1.0.0", ...}]' marketplace.json > tmp && mv tmp marketplace.json
jq '.version = "<bumped-version>"' marketplace.json > tmp && mv tmp marketplace.json

# 3. Deploy webhook workflow
cp ../templates/notify-marketplace.yml ../<new-plugin>/.github/workflows/

# 4. Add MARKETPLACE_UPDATE_TOKEN secret to new plugin repo
gh secret set MARKETPLACE_UPDATE_TOKEN --repo flight505/<new-plugin> --body "$GITHUB_TOKEN"

# 5. Update auto-update-plugins.yml workflow
# Add <new-plugin> to submodule lists

# 6. Commit all changes
git add .
git commit -m "feat: add <new-plugin> to marketplace"
git push origin main
```

---

## Maintenance Scripts

**Location:** `scripts/` directory

The marketplace includes automated scripts for common maintenance tasks. **Always use these scripts instead of manual operations** to ensure consistency and avoid errors.

### validate-plugin-manifests.sh

Validates all plugin.json manifests for correct format and synchronization with marketplace.json.

**Usage:**
```bash
# Validate all plugins
./scripts/validate-plugin-manifests.sh

# Auto-fix common issues (paths, formatting)
./scripts/validate-plugin-manifests.sh --fix
```

**What it validates:**
- JSON syntax correctness
- Required fields (name, version, description, author)
- Semantic versioning format (X.Y.Z)
- Skills paths must be `./skills/name`
- Agents paths must be `./agents/name.md`
- Commands paths and format
- Version synchronization with marketplace.json
- File existence for all referenced paths

**When to use:**
- Before committing any manifest changes
- After updating plugin versions
- In CI/CD pipelines (auto-runs on push)
- When debugging version sync issues

**Example output:**
```bash
✓ sdk-bridge validation passed
✗ storybook-assistant: Skill 'my-skill' must be a relative path starting with './'
⚠ nano-banana: Missing SKILL.md in ./skills/example
```

---

### bump-plugin-version.sh

Automates the complete version bump workflow across plugin and marketplace repos.

**Usage:**
```bash
./scripts/bump-plugin-version.sh <plugin-name> <new-version> [--dry-run]
```

**Examples:**
```bash
# Bump storybook-assistant to version 2.2.0
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# Test what would happen without making changes
./scripts/bump-plugin-version.sh sdk-bridge 3.1.0 --dry-run
```

**What it does (fully automated):**
1. Updates `.claude-plugin/plugin.json` version in plugin submodule
2. Commits version change in plugin repo
3. Updates corresponding entry in `marketplace.json`
4. Bumps marketplace version (patch increment)
5. Commits marketplace changes
6. Pushes to both plugin and marketplace repos
7. Creates and pushes git tag (e.g., `v2.2.0`)
8. Triggers webhook notification (~30 second delay)

**Supported plugins:**
- `sdk-bridge`
- `taskplex`
- `storybook-assistant`
- `claude-project-planner`
- `nano-banana`

**Why use this:**
- Ensures version synchronization between plugin.json and marketplace.json
- Prevents manual errors in multi-step version bump process
- Automatically creates git tags for releases
- Triggers webhook system for real-time updates

---

### setup-webhooks.sh

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

**When to use:**
- Setting up a new plugin in the marketplace
- Updating webhook workflow across all plugins
- Troubleshooting webhook issues

**Next steps after running:**
1. Review changes in each plugin directory
2. Commit and push to each plugin repo
3. Verify `MARKETPLACE_UPDATE_TOKEN` secret exists in each repo
4. Test with a version bump

---

### Script Workflow Examples

**Before any commit:**
```bash
# Always validate before committing
./scripts/validate-plugin-manifests.sh

# Fix issues automatically
./scripts/validate-plugin-manifests.sh --fix
```

**Releasing a new plugin version:**
```bash
# 1. Use bump script (handles everything)
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# 2. Validate everything worked
./scripts/validate-plugin-manifests.sh

# 3. Wait for webhook (~30 seconds)
# 4. Verify in GitHub Actions
gh run list --repo flight505/flight505-marketplace --workflow auto-update-plugins.yml --limit 1
```

**Setting up webhooks for new plugin:**
```bash
# 1. Run setup script
./scripts/setup-webhooks.sh

# 2. Commit webhook to plugin repo
cd <plugin-name>
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main

# 3. Add secret to plugin repo
gh secret set MARKETPLACE_UPDATE_TOKEN --repo flight505/<plugin-name>

# 4. Test with version bump
cd ..
./scripts/bump-plugin-version.sh <plugin-name> 1.0.1
```

---

### Requirements

All scripts require:
- **jq** - JSON processor
  - macOS: `brew install jq`
  - Ubuntu: `apt-get install jq`
- **git** - Already required for marketplace
- **bash** - Already available on all systems

---

## Common Operations

### Check Submodule Status

```bash
git submodule status
# Should show commit hash + name + (tag/version)
```

### Sync After Remote Changes

```bash
git pull origin main
git submodule update --init --recursive
```

### Fix Detached HEAD in Submodule

```bash
cd <plugin>
git checkout main
git pull origin main
cd ..
git add <plugin>
git commit -m "chore: update <plugin> submodule pointer"
```

---

## Documentation Standards

### Root Marketplace Files

```
CLAUDE.md          - This file (critical instructions)
README.md          - Public-facing documentation (installation, features)
```

### Each Plugin Files

```
CLAUDE.md                     - Developer instructions
README.md                     - Public documentation
CONTEXT_<plugin-name>.md      - Consolidated architecture/context
.claude-plugin/plugin.json    - Plugin manifest
```

**Naming Convention:** `CONTEXT_<plugin-name>.md` for ground truth files
- `CONTEXT_sdk-bridge.md`
- `CONTEXT_storybook-assistant.md`
- `CONTEXT_claude-project-planner.md`
- `CONTEXT_nano-banana.md`

**Rationale:** Distinguishable when viewing from marketplace root, clear purpose

---

## Troubleshooting

### Webhook Not Triggering

1. Check `.github/workflows/notify-marketplace.yml` exists in plugin repo
2. Verify `MARKETPLACE_UPDATE_TOKEN` secret is set in plugin repo settings
3. Confirm version actually changed in plugin.json (compare with `git show HEAD^:.claude-plugin/plugin.json`)
4. Check workflow run logs in plugin repo Actions tab

### Marketplace Version Mismatch

```bash
# Check current marketplace version
cat .claude-plugin/marketplace.json | jq -r '.version'

# Check plugin versions
cat .claude-plugin/marketplace.json | jq '.plugins[] | {name, version}'

# Bump marketplace version
cd .claude-plugin
jq '.version = "1.2.8"' marketplace.json > tmp && mv tmp marketplace.json
cd ..
git add .claude-plugin/marketplace.json
git commit -m "chore: bump marketplace version to 1.2.8"
git push origin main
```

### Submodule Out of Sync

```bash
# Reset to latest remote
cd <plugin>
git fetch origin
git reset --hard origin/main
cd ..
git add <plugin>
git commit -m "chore: sync <plugin> submodule"
```

---

## References

- **Official Plugin Marketplace Docs:** https://github.com/anthropics/claude-code/blob/main/docs/plugin-marketplace.md
- **Plugin Development Guide:** https://github.com/anthropics/claude-code/blob/main/docs/plugins.md
- **Git Submodules Reference:** https://git-scm.com/book/en/v2/Git-Tools-Submodules
- **GitHub Actions - repository_dispatch:** https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#repository_dispatch

---

**Maintained by:** Jesper Vang (@flight505)
**Last Updated:** 2026-02-15
