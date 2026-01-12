# Phase 3: Event-Based Webhook Triggers

**Status:** Ready to implement
**Impact:** Real-time marketplace updates (seconds vs 24 hours)

## Overview

Add webhook triggers so the marketplace auto-updates immediately when you push version bumps to plugin repos, instead of waiting up to 24 hours for the daily cron.

**Architecture:**
- Plugin repos trigger marketplace via `repository_dispatch` webhook
- Marketplace updates within seconds of plugin version bump
- Daily cron remains as safety net

---

## Step 1: Create Personal Access Token (PAT)

You need a GitHub PAT with `repo` scope to trigger workflows across repositories.

### Create Token

1. Go to GitHub Settings: https://github.com/settings/tokens/new
2. Configure token:
   - **Note:** `Marketplace Update Token (flight505-plugins)`
   - **Expiration:** 90 days (or No expiration if you prefer)
   - **Scopes:** Check `repo` (full control of private repositories)
     - This grants: `repo:status`, `repo_deployment`, `public_repo`, `repo:invite`, `security_events`
3. Click **Generate token**
4. **IMPORTANT:** Copy the token immediately (you won't see it again)
   - Format: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Store Token Securely

**Locally (for reference):**
```bash
# Optional: Store in password manager or secure note
# Example format:
# MARKETPLACE_UPDATE_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Step 2: Add Token to Plugin Repositories

Add the PAT as a secret to each plugin repo so they can trigger marketplace updates.

### For Each Plugin Repository

Repeat for all 4 repos:
1. **sdk-bridge**: https://github.com/flight505/sdk-bridge
2. **storybook-assistant**: https://github.com/flight505/storybook-assistant
3. **claude-project-planner**: https://github.com/flight505/claude-project-planner
4. **nano-banana**: https://github.com/flight505/nano-banana

**Steps for each:**

1. Go to repository **Settings** tab
2. Navigate to **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Configure secret:
   - **Name:** `MARKETPLACE_UPDATE_TOKEN`
   - **Secret:** Paste your PAT from Step 1
5. Click **Add secret**

### Verification

After adding to all 4 repos, verify:
```bash
# Check each repo's settings page shows:
# ✅ MARKETPLACE_UPDATE_TOKEN (Updated X seconds ago)
```

---

## Step 3: Add Webhook Workflows to Plugin Repos

Add the notification workflow to each plugin repo's `.github/workflows/` directory.

### Automated Setup (Recommended)

Use the provided script to add workflows to all plugin submodules:

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace

# Run setup script (creates workflow files in each submodule)
bash scripts/setup-webhooks.sh

# The script will:
# 1. Create .github/workflows/ in each plugin submodule
# 2. Copy notify-marketplace.yml template
# 3. Show git status for each plugin
```

### Manual Setup (Alternative)

If you prefer manual control, add to each plugin individually:

**For sdk-bridge:**
```bash
cd sdk-bridge
mkdir -p .github/workflows
cp ../templates/notify-marketplace.yml .github/workflows/
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main
cd ..
```

**For storybook-assistant:**
```bash
cd storybook-assistant
mkdir -p .github/workflows
cp ../templates/notify-marketplace.yml .github/workflows/
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main
cd ..
```

**For claude-project-planner:**
```bash
cd claude-project-planner
mkdir -p .github/workflows
cp ../templates/notify-marketplace.yml .github/workflows/
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main
cd ..
```

**For nano-banana:**
```bash
cd nano-banana
mkdir -p .github/workflows
cp ../templates/notify-marketplace.yml .github/workflows/
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main
cd ..
```

---

## Step 4: Update Marketplace Workflow (Optional)

Enhance the marketplace workflow to log webhook trigger details.

```bash
# Already configured in auto-update-plugins.yml:
# - on.repository_dispatch.types: [plugin-updated]
#
# Optionally add logging to see which plugin triggered:
# - Log ${{ github.event.client_payload.plugin }}
# - Log ${{ github.event.client_payload.version }}
```

This is **optional** since the current workflow already handles `repository_dispatch`.

---

## Step 5: Test the Integration

### Test Webhook Trigger

1. **Make a test version bump in any plugin:**
   ```bash
   cd sdk-bridge/plugins/sdk-bridge

   # Bump version in plugin.json
   jq '.version = "2.0.1"' .claude-plugin/plugin.json > tmp.json
   mv tmp.json .claude-plugin/plugin.json

   git add .claude-plugin/plugin.json
   git commit -m "chore: bump version to 2.0.1 (test webhook)"
   git push origin main
   ```

2. **Watch GitHub Actions:**
   - Plugin repo: Check Actions tab for "Notify Marketplace on Version Bump"
   - Marketplace repo: Check Actions tab for "Auto-update Plugin Submodules"
   - Expected: Marketplace update within 1-2 minutes

3. **Verify marketplace.json updated:**
   ```bash
   cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
   git pull origin main
   cat .claude-plugin/marketplace.json | jq '.plugins[] | select(.name == "sdk-bridge") | .version'
   # Should show "2.0.1"
   ```

### Test Daily Cron (Fallback)

The daily cron at midnight UTC continues working as a safety net:

```bash
# Manually trigger via workflow_dispatch:
# 1. Go to: https://github.com/flight505/flight505-marketplace/actions
# 2. Select "Auto-update Plugin Submodules"
# 3. Click "Run workflow" → "Run workflow"
# 4. Wait for completion (~30 seconds)
```

---

## Architecture Diagram

```
Plugin Repo (e.g., sdk-bridge)
│
├─ .claude-plugin/plugin.json (version bump)
│     │
│     └─ triggers on push
│
├─ .github/workflows/notify-marketplace.yml
│     │
│     ├─ Detects version change
│     ├─ Calls GitHub API with PAT
│     └─ Sends repository_dispatch to marketplace
│
▼
Marketplace Repo (flight505-marketplace)
│
├─ .github/workflows/auto-update-plugins.yml
│     │
│     ├─ Triggered by repository_dispatch
│     ├─ Updates submodules
│     ├─ Updates marketplace.json versions
│     └─ Commits + pushes changes
│
└─ .claude-plugin/marketplace.json (updated)
```

---

## Trigger Conditions

**Webhook triggers on:**
- ✅ Version bump in `plugin.json` pushed to main branch
- ✅ Only when version actually changes (not every commit)

**Cron triggers on:**
- ⏰ Daily at midnight UTC (safety net)
- 🔧 Manual workflow_dispatch

---

## Benefits

| Feature | Before (Phase 2) | After (Phase 3) |
|---------|-----------------|-----------------|
| **Update Speed** | Up to 24 hours | Seconds |
| **Manual Work** | None | None |
| **Reliability** | Cron only | Webhook + Cron fallback |
| **Development** | Slow iteration | Fast iteration |
| **Visibility** | Daily logs | Real-time logs |

---

## Rollback Plan

If webhooks cause issues:

1. **Disable plugin workflows:**
   ```bash
   # In each plugin repo, disable the workflow in GitHub UI
   # Or delete: .github/workflows/notify-marketplace.yml
   ```

2. **Marketplace continues working:**
   - Daily cron still updates everything at midnight
   - No impact on end users

---

## Security Notes

- **PAT Security:** Token has `repo` scope (necessary for triggering workflows)
- **Token Storage:** Stored as encrypted secret in GitHub Actions
- **Token Rotation:** Recommended every 90 days
- **Principle of Least Privilege:** Token only used for triggering marketplace updates

---

## Troubleshooting

### Webhook Not Triggering

**Check plugin workflow:**
```bash
# 1. Verify workflow file exists
ls -la .github/workflows/notify-marketplace.yml

# 2. Check GitHub Actions logs for errors
# Go to: https://github.com/flight505/PLUGIN_NAME/actions

# 3. Verify PAT secret exists
# Go to: https://github.com/flight505/PLUGIN_NAME/settings/secrets/actions
```

**Check marketplace workflow:**
```bash
# 1. Verify marketplace workflow includes repository_dispatch
grep "repository_dispatch" .github/workflows/auto-update-plugins.yml

# 2. Check GitHub Actions logs
# Go to: https://github.com/flight505/flight505-marketplace/actions
```

### Version Detection Not Working

**Verify plugin.json path:**
```bash
# Workflow expects one of:
# - .claude-plugin/plugin.json
# - plugins/*/\.claude-plugin/plugin.json

# Check your plugin structure:
find . -name "plugin.json" -path "*/.claude-plugin/*"
```

### PAT Expired or Invalid

**Symptoms:**
- Workflow fails with 401 Unauthorized
- Marketplace not receiving webhooks

**Solution:**
1. Generate new PAT (Step 1)
2. Update secret in all 4 plugin repos (Step 2)

---

## Maintenance

### Token Expiration

If you set 90-day expiration:

```bash
# ~80 days from now, you'll need to:
# 1. Create new PAT (same process as Step 1)
# 2. Update secret in all 4 plugin repos
# 3. Test with version bump
```

### Adding New Plugins

When adding new plugins to marketplace:

```bash
# 1. Add workflow to new plugin
cd new-plugin
mkdir -p .github/workflows
cp ../templates/notify-marketplace.yml .github/workflows/
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main

# 2. Add MARKETPLACE_UPDATE_TOKEN secret
# Go to: https://github.com/flight505/new-plugin/settings/secrets/actions

# 3. Test with version bump
```

---

## Checklist

### Prerequisites
- [ ] GitHub PAT created with `repo` scope
- [ ] PAT stored securely

### Configuration (per plugin repo)
- [ ] sdk-bridge: PAT added as secret `MARKETPLACE_UPDATE_TOKEN`
- [ ] storybook-assistant: PAT added as secret `MARKETPLACE_UPDATE_TOKEN`
- [ ] claude-project-planner: PAT added as secret `MARKETPLACE_UPDATE_TOKEN`
- [ ] nano-banana: PAT added as secret `MARKETPLACE_UPDATE_TOKEN`

### Workflow Installation (per plugin repo)
- [ ] sdk-bridge: notify-marketplace.yml added
- [ ] storybook-assistant: notify-marketplace.yml added
- [ ] claude-project-planner: notify-marketplace.yml added
- [ ] nano-banana: notify-marketplace.yml added

### Testing
- [ ] Test webhook trigger with version bump
- [ ] Verify marketplace updates automatically
- [ ] Verify marketplace.json reflects new version
- [ ] Test manual workflow_dispatch still works

### Documentation
- [ ] Update main README with webhook info
- [ ] Document PAT rotation schedule
- [ ] Add troubleshooting section to docs

---

## Timeline

**Estimated time:** 30 minutes
- PAT creation: 2 minutes
- Add secrets (4 repos): 8 minutes
- Add workflows (4 repos): 10 minutes
- Testing: 10 minutes

**When to execute:** Anytime - daily cron continues as fallback
