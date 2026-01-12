# Testing Webhook Triggers

Quick guide for testing Phase 3 webhook integration.

## Prerequisites

- ✅ PAT created and added to all 4 plugin repos
- ✅ Workflow files added to all 4 plugin repos
- ✅ Workflows pushed to plugin repos

## Test 1: Version Bump Webhook

Test that version bumps trigger immediate marketplace updates.

### Test with sdk-bridge

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace/sdk-bridge

# Navigate to nested plugin structure
cd plugins/sdk-bridge

# Get current version
CURRENT_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
echo "Current version: $CURRENT_VERSION"

# Bump patch version (e.g., 2.0.0 → 2.0.1)
NEW_VERSION=$(echo $CURRENT_VERSION | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
echo "New version: $NEW_VERSION"

# Update version in plugin.json
jq --arg v "$NEW_VERSION" '.version = $v' .claude-plugin/plugin.json > tmp.json
mv tmp.json .claude-plugin/plugin.json

# Commit and push
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to $NEW_VERSION (test webhook)"
git push origin main

cd ../..
```

### Expected Results

**1. Plugin Workflow Triggers (1-2 minutes)**
- Go to: https://github.com/flight505/sdk-bridge/actions
- Look for: "Notify Marketplace on Version Bump"
- Status should be: ✅ Success
- Log should show: "Version changed: X.X.X → X.X.X+1"
- Log should show: "Marketplace notification sent successfully"

**2. Marketplace Workflow Triggers (2-3 minutes)**
- Go to: https://github.com/flight505/flight505-marketplace/actions
- Look for: "Auto-update Plugin Submodules"
- Status should be: ✅ Success
- Log should show:
  ```
  Trigger: repository_dispatch
  Plugin: sdk-bridge
  Version: X.X.X+1
  Previous: X.X.X
  ```

**3. Marketplace Updated (3-5 minutes)**
```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace

# Pull latest changes
git pull origin main

# Verify version updated
jq '.plugins[] | select(.name == "sdk-bridge") | .version' .claude-plugin/marketplace.json

# Should show new version
```

## Test 2: Non-Version Commit (Should NOT Trigger)

Test that regular commits don't trigger webhooks.

```bash
cd sdk-bridge/plugins/sdk-bridge

# Make a non-version change
echo "# Test" >> README.md

git add README.md
git commit -m "docs: add test line to README"
git push origin main

cd ../..
```

### Expected Results

**Plugin Workflow:**
- Go to: https://github.com/flight505/sdk-bridge/actions
- Look for: "Notify Marketplace on Version Bump"
- Status: ✅ Success (but with "Skipping marketplace notification - version unchanged")

**Marketplace Workflow:**
- Should NOT trigger (no new workflow run)

## Test 3: Manual Workflow Dispatch

Test that manual triggering still works.

### Trigger Manually

1. Go to: https://github.com/flight505/flight505-marketplace/actions
2. Click "Auto-update Plugin Submodules"
3. Click "Run workflow" dropdown
4. Click "Run workflow" button
5. Wait for completion (~30-60 seconds)

### Expected Results

- Status: ✅ Success
- Log shows: "Trigger: workflow_dispatch"
- Log shows: "Type: Manual trigger"
- All submodules checked for updates
- Marketplace.json updated if any changes found

## Test 4: Multiple Plugin Updates

Test that multiple plugins can trigger in sequence.

```bash
# Bump version in multiple plugins
for plugin in sdk-bridge storybook-assistant; do
  echo "Bumping $plugin..."
  # Add version bump logic here
done

# Watch Actions tab - should see multiple marketplace updates
```

## Test 5: Daily Cron (Safety Net)

The daily cron continues working as a fallback.

### Verify Cron Schedule

```bash
cat .github/workflows/auto-update-plugins.yml | grep -A 2 "schedule:"
# Should show: cron: '0 0 * * *'
```

### Manual Cron Test

Since cron runs at midnight UTC, trigger manually to test:

1. Go to: https://github.com/flight505/flight505-marketplace/actions
2. Click "Auto-update Plugin Submodules"
3. Click "Run workflow"
4. Verify it works same as webhook triggers

## Troubleshooting

### Webhook Not Triggering

**Check plugin workflow logs:**
```bash
# Look for errors in:
# https://github.com/flight505/PLUGIN_NAME/actions

# Common issues:
# - PAT not set or expired (401 Unauthorized)
# - Wrong secret name (should be MARKETPLACE_UPDATE_TOKEN)
# - Version didn't actually change
```

**Check marketplace workflow:**
```bash
# Look for webhook in:
# https://github.com/flight505/flight505-marketplace/actions

# If not triggering:
# - Verify repository_dispatch is in workflow triggers
# - Check PAT has correct permissions (repo scope)
```

### Version Detection Failed

**Check plugin structure:**
```bash
cd sdk-bridge

# Find plugin.json
find . -name "plugin.json" -path "*/.claude-plugin/*"

# Should match one of:
# - .claude-plugin/plugin.json
# - plugins/*/\.claude-plugin/plugin.json
```

### Multiple Triggers

If webhook triggers multiple times:

- Check that plugin.json is only changed once per commit
- Verify workflow only triggers on main branch
- Check for accidental force pushes

## Success Criteria

✅ **Phase 3 is working if:**

1. Version bump in plugin triggers marketplace update within 2-3 minutes
2. Non-version commits don't trigger marketplace
3. Marketplace.json reflects new version after update
4. Manual workflow_dispatch still works
5. All 4 plugins can trigger independently
6. Daily cron continues as safety net

## Monitoring

### Check Recent Triggers

```bash
# View recent marketplace updates
gh run list --repo flight505/flight505-marketplace --limit 10

# View recent plugin triggers
gh run list --repo flight505/sdk-bridge --limit 5
```

### View Workflow Logs

```bash
# View specific run
gh run view RUN_ID --repo flight505/flight505-marketplace --log

# View latest run
gh run view --repo flight505/flight505-marketplace --log
```

## Performance Comparison

| Metric | Phase 2 (Cron Only) | Phase 3 (Webhooks) |
|--------|--------------------|--------------------|
| Update Latency | Up to 24 hours | 1-3 minutes |
| Manual Work | None | None |
| Reliability | Good | Excellent (dual triggers) |
| Visibility | Daily logs | Real-time logs |
| Development Speed | Slow iteration | Fast iteration |

## Next Steps After Testing

Once all tests pass:

1. ✅ Phase 3 is complete and operational
2. Document webhook behavior in main README
3. Set calendar reminder for PAT rotation (90 days)
4. Consider adding status badges to plugin READMEs
5. Monitor GitHub Actions usage (free tier: 2000 min/month)

## Rollback

If issues arise, disable webhooks:

```bash
# Option 1: Disable in GitHub UI
# Go to each plugin repo → Actions → Disable workflow

# Option 2: Delete workflow files
cd sdk-bridge
git rm .github/workflows/notify-marketplace.yml
git commit -m "chore: disable webhook notifications"
git push origin main

# Marketplace continues working with daily cron
```

---

**See PHASE3_WEBHOOKS_GUIDE.md for complete setup instructions.**
