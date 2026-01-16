# Webhook System Troubleshooting

## Overview

The flight505-marketplace uses a webhook system to automatically sync plugin versions. When a plugin's version is bumped, it should automatically update the marketplace within 19-30 seconds.

## How It Works

```
Plugin Repo (version bump in plugin.json)
    ↓ push to main
notify-marketplace.yml workflow
    ↓ repository_dispatch event + MARKETPLACE_UPDATE_TOKEN
flight505-marketplace
    ↓ auto-update-plugins.yml workflow
Updates marketplace.json + submodule pointer
    ↓ ~30 seconds total
Users get updated plugin via /plugin update
```

## Common Issues

### Issue: Webhook Shows Success But Marketplace Doesn't Update

**Symptoms:**
- Plugin version bumped successfully
- `notify-marketplace.yml` workflow shows "✅ Marketplace notification sent successfully"
- BUT marketplace.json still shows old version
- No `repository_dispatch` events in marketplace Actions tab

**Root Cause:**
The `MARKETPLACE_UPDATE_TOKEN` secret is invalid, expired, or missing required permissions.

**Diagnosis:**
```bash
# Check plugin webhook workflow log
gh run list --repo flight505/<plugin-name> --workflow notify-marketplace.yml --limit 1
gh run view <run-id> --repo flight505/<plugin-name> --log | grep -A 5 "Bad credentials\|Marketplace notification"

# Look for:
# "message": "Bad credentials"
# "status": "401"
```

**Fix:**
1. Generate new Personal Access Token (see below)
2. Update secret in ALL plugin repos
3. Test with a version bump
4. Verify webhook works

### Issue: Webhook Doesn't Trigger at All

**Symptoms:**
- Version bump committed
- No workflow run in Actions tab
- `notify-marketplace.yml` workflow not triggered

**Diagnosis:**
```bash
# Check if workflow file exists
ls -la .github/workflows/notify-marketplace.yml

# Check workflow triggers
cat .github/workflows/notify-marketplace.yml | grep -A 5 "on:"

# Check if version actually changed in commit
git show HEAD:.claude-plugin/plugin.json | jq -r '.version'
git show HEAD^:.claude-plugin/plugin.json | jq -r '.version'
```

**Fix:**
1. Ensure `notify-marketplace.yml` exists in `.github/workflows/`
2. Verify the file was modified: `git diff HEAD^ HEAD .claude-plugin/plugin.json`
3. Check workflow path matches: `paths: ['.claude-plugin/plugin.json']`

## Regenerating MARKETPLACE_UPDATE_TOKEN

### When to Regenerate

- Webhook returns 401 "Bad credentials"
- Token expired (GitHub tokens can expire)
- After changing GitHub account passwords
- After revoking access

### Step-by-Step Guide

#### 1. Generate New GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - URL: https://github.com/settings/tokens

2. Click "Generate new token" → "Generate new token (classic)"

3. Configure the token:
   - **Note:** `flight505-marketplace-webhook`
   - **Expiration:** No expiration (or 1 year if you prefer rotation)
   - **Scopes:**
     - ✅ `repo` (Full control of private repositories)
       - This includes: `repo:status`, `repo_deployment`, `public_repo`, `repo:invite`

4. Click "Generate token"

5. **IMPORTANT:** Copy the token immediately (you won't see it again!)
   - Format: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

#### 2. Update Secret in ALL Plugin Repos

You need to add the secret to EACH plugin repo that uses webhooks.

**Using GitHub CLI (Recommended):**

```bash
# Set your token as environment variable (paste the token you copied)
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Update all plugin repos
gh secret set MARKETPLACE_UPDATE_TOKEN \
  --repo flight505/sdk-bridge \
  --body "$GITHUB_TOKEN"

gh secret set MARKETPLACE_UPDATE_TOKEN \
  --repo flight505/claude-project-planner \
  --body "$GITHUB_TOKEN"

gh secret set MARKETPLACE_UPDATE_TOKEN \
  --repo flight505/storybook-assistant \
  --body "$GITHUB_TOKEN"

gh secret set MARKETPLACE_UPDATE_TOKEN \
  --repo flight505/nano-banana \
  --body "$GITHUB_TOKEN"
```

**Using GitHub Web UI:**

For each plugin repo:
1. Go to repo Settings → Secrets and variables → Actions
2. Find `MARKETPLACE_UPDATE_TOKEN` or click "New repository secret"
3. Paste the token value
4. Click "Update secret" or "Add secret"

Repos to update:
- https://github.com/flight505/sdk-bridge/settings/secrets/actions
- https://github.com/flight505/claude-project-planner/settings/secrets/actions
- https://github.com/flight505/storybook-assistant/settings/secrets/actions
- https://github.com/flight505/nano-banana/settings/secrets/actions

#### 3. Test the Webhook

Pick one plugin to test:

```bash
# Navigate to plugin repo
cd sdk-bridge

# Bump version (or make a trivial change to plugin.json)
jq '.version = "2.2.1"' .claude-plugin/plugin.json > tmp && mv tmp .claude-plugin/plugin.json

# Commit and push
git add .claude-plugin/plugin.json
git commit -m "test: webhook verification"
git push origin main

# Watch for workflow run
gh run list --repo flight505/sdk-bridge --workflow notify-marketplace.yml --limit 1

# Check workflow log for success (should see HTTP 204)
gh run view <run-id> --repo flight505/sdk-bridge --log | grep -A 5 "Marketplace notification"

# Verify marketplace received event (wait 30 seconds)
sleep 30
gh run list --repo flight505/flight505-marketplace --workflow auto-update-plugins.yml --limit 1

# Check marketplace was updated
cd ../flight505-marketplace
git pull origin main
cat .claude-plugin/marketplace.json | jq '.plugins[] | select(.name=="sdk-bridge") | .version'
```

**Expected Output:**
- Plugin workflow: "✅ Marketplace notification sent successfully (HTTP 204)"
- Marketplace workflow: New run triggered by `repository_dispatch`
- marketplace.json: Shows new version

## Webhook Workflow Improvements (v2)

### What Changed

The original workflow had a bug where it checked `curl` exit code instead of HTTP response code. This meant 401 errors were reported as success.

**Old (Buggy):**
```bash
curl -X POST ... | ...
if [ $? -eq 0 ]; then
  echo "✅ Success"
fi
```

**New (Fixed):**
```bash
HTTP_CODE=$(curl -X POST -w "%{http_code}" -o /tmp/response.json ...)
if [ "$HTTP_CODE" = "204" ]; then
  echo "✅ Success (HTTP $HTTP_CODE)"
else
  echo "❌ Failed (HTTP $HTTP_CODE)"
  cat /tmp/response.json
  exit 1
fi
```

### Deploying the Fixed Workflow

The fixed template is in `templates/notify-marketplace.yml`. Deploy to all plugins:

```bash
# Update each plugin's workflow
for plugin in sdk-bridge claude-project-planner storybook-assistant nano-banana; do
  cp templates/notify-marketplace.yml "$plugin/.github/workflows/notify-marketplace.yml"
  cd "$plugin"
  git add .github/workflows/notify-marketplace.yml
  git commit -m "fix: properly detect HTTP errors in webhook workflow"
  git push origin main
  cd ..
done
```

## Manual Sync (Emergency Fallback)

If webhooks are completely broken, you can manually sync:

```bash
# Update submodule to latest
git submodule update --remote --recursive <plugin-name>

# Read version from submodule
VERSION=$(jq -r '.version' <plugin-name>/.claude-plugin/plugin.json)

# Update marketplace.json
jq --arg name "<plugin-name>" --arg version "$VERSION" \
  '(.plugins[] | select(.name == $name) | .version) = $version' \
  .claude-plugin/marketplace.json > tmp && mv tmp .claude-plugin/marketplace.json

# Bump marketplace version
CURRENT=$(jq -r '.version' .claude-plugin/marketplace.json)
# Manually increment patch version
NEW_VERSION="1.2.X"  # Replace X with incremented patch
jq --arg version "$NEW_VERSION" '.version = $version' \
  .claude-plugin/marketplace.json > tmp && mv tmp .claude-plugin/marketplace.json

# Commit and push
git add .claude-plugin/marketplace.json <plugin-name>
git commit -m "chore: manual sync $plugin-name to v$VERSION"
git push origin main
```

## Monitoring Webhooks

### Check Workflow Status

```bash
# Plugin webhooks (last 5 runs)
gh run list --repo flight505/sdk-bridge --workflow notify-marketplace.yml --limit 5

# Marketplace auto-updates (last 5 runs)
gh run list --repo flight505/flight505-marketplace --workflow auto-update-plugins.yml --limit 5
```

### Check Last Successful Sync

```bash
# Find last repository_dispatch event in marketplace
gh run list --repo flight505/flight505-marketplace \
  --workflow auto-update-plugins.yml \
  --limit 20 \
  --json databaseId,event,conclusion,createdAt \
  --jq '.[] | select(.event=="repository_dispatch") | [.createdAt, .conclusion] | @tsv'
```

## Best Practices

1. **Always test webhooks after token regeneration**
   - Do a test version bump
   - Verify HTTP 204 response
   - Check marketplace updated

2. **Use the version bump script**
   - Located at `scripts/bump-plugin-version.sh`
   - Handles all steps automatically
   - Includes webhook verification

3. **Monitor workflow runs**
   - Check Actions tab after version bumps
   - Look for 401/403 errors
   - Verify marketplace receives events

4. **Keep tokens secure**
   - Never commit tokens to git
   - Use GitHub secrets only
   - Rotate tokens annually (if using expiration)

5. **Document token updates**
   - Note when regenerated
   - Track which repos have new token
   - Keep backup of token in password manager

## Frequently Asked Questions

### Q: Why does the webhook say success but nothing happens?

**A:** The old workflow had a bug where it reported success even on 401 errors. Update to the fixed workflow in `templates/notify-marketplace.yml`.

### Q: How often do tokens expire?

**A:** Classic tokens with "No expiration" don't expire unless revoked. Fine-grained tokens can have 1-90 day expiration.

### Q: Do I need to update the token in the marketplace repo?

**A:** No! The token is only used by PLUGIN repos to send events TO the marketplace. The marketplace repo doesn't need the secret.

### Q: Can I use fine-grained tokens instead of classic?

**A:** Yes, but ensure it has:
- Repository access: `flight505-marketplace` only
- Permissions: `Contents: Read and write`, `Metadata: Read-only`

### Q: What if I accidentally revoked the token?

**A:** Regenerate immediately using steps above. Old tokens can't be recovered.

### Q: How do I know which token is currently active?

**A:** GitHub doesn't show secret values. Best practice: Name tokens clearly and note their purpose/creation date.

## Support

If you encounter issues not covered here:
1. Check GitHub Actions logs for detailed error messages
2. Verify webhook configuration matches this guide
3. Create an issue at: https://github.com/flight505/flight505-marketplace/issues
