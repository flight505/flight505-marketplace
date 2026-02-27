# flight505-marketplace

6 Claude Code plugins as git submodules. Webhook-driven auto-updates, self-correcting validation hooks.

**Repository:** https://github.com/flight505/flight505-marketplace

---

## Validation Hooks (Always Active)

Edit `plugin.json` → manifest validator runs automatically → blocks on errors → Claude fixes → re-validates.
Edit `marketplace.json` → sync validator runs → checks versions match plugin.json files.

Webhook chain handles plugin→marketplace version sync on push. Don't manually update marketplace.json after version bumps.

**Validators:** `.claude/hooks/validators/plugin-manifest-validator.py`, `marketplace-sync-validator.py`

---

## Plugin Structure

```
flight505-marketplace/
├── sdk-bridge/              → github.com/flight505/sdk-bridge
├── taskplex/                → github.com/flight505/taskplex
├── storybook-assistant/     → github.com/flight505/storybook-assistant
├── claude-project-planner/  → github.com/flight505/claude-project-planner
├── nano-banana/             → github.com/flight505/nano-banana
└── ai-frontier/             → github.com/flight505/ai-frontier
```

**Each plugin has:** `CLAUDE.md`, `README.md`, `.claude-plugin/plugin.json`

### Component Types

| Component | Location | Notes |
|-----------|----------|-------|
| Skills | `skills/` or `commands/` | `SKILL.md` files |
| Agents | `agents/` | `.md` with YAML frontmatter |
| Hooks | `hooks/hooks.json` | Auto-discovered — **never** add `"hooks"` to plugin.json |
| MCP servers | `.mcp.json` | External service integrations |

### Hook Events

`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `UserPromptSubmit`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop`, `SessionStart`, `SessionEnd`, `TeammateIdle`, `TaskCompleted`, `PreCompact`

**Hook types:** `command` (shell), `prompt` (LLM-evaluated), `agent` (agentic verifier)

---

## marketplace.json

**Location:** `.claude-plugin/marketplace.json`
**Schema:** https://code.claude.com/docs/en/plugin-marketplaces.md

**Rules:**
- `source` paths must be relative (`"./sdk-bridge"`)
- Plugin `name` must match submodule directory name
- Semantic versioning (X.Y.Z), hyphens not underscores
- Don't manually update after version bumps — webhook handles it
- Only edit directly when adding/removing plugins

---

## Webhook System

Version bump in plugin → push to main → `notify-marketplace.yml` → `repository_dispatch` → `auto-update-plugins.yml` → marketplace.json + submodule updated (~30 seconds).

**Each plugin repo needs:** `.github/workflows/notify-marketplace.yml` + `MARKETPLACE_UPDATE_TOKEN` secret.

**Only triggers on:** version changes in plugin.json pushed to main.

---

## Scripts

All scripts derive plugin lists from `marketplace.json` via `scripts/common.sh`. Adding/removing a plugin only requires updating `marketplace.json`.

| Script | Purpose |
|--------|---------|
| `./scripts/bump-plugin-version.sh <plugin> <version>` | Full version bump workflow (plugin + marketplace + tag + push) |
| `./scripts/validate-plugin-manifests.sh` | Validate all manifests, hooks, frontmatter, cross-refs |
| `./scripts/validate-plugin-manifests.sh --fix` | Auto-fix common issues |
| `./scripts/plugin-doctor.sh` | CLI validation + cache drift + offline sanity |
| `./scripts/dev-test.sh <plugin>` | Single-plugin validation |
| `./scripts/test-marketplace-integration.sh` | Multi-plugin conflict testing |
| `./scripts/setup-webhooks.sh` | Deploy notify-marketplace.yml to all plugins |

**Requirements:** `jq`, `git`, `bash`

---

## Common Operations

```bash
# Version bump (handles everything)
./scripts/bump-plugin-version.sh storybook-assistant 2.2.0

# Validate before commit
./scripts/validate-plugin-manifests.sh

# Sync submodules
git submodule update --remote --merge

# Fix detached HEAD
cd <plugin> && git checkout main && git pull && cd .. && git add <plugin>

# Add new plugin
git submodule add https://github.com/flight505/<plugin>.git <plugin>
# Then add entry to .claude-plugin/marketplace.json
# Then: ./scripts/setup-webhooks.sh
# Then: gh secret set MARKETPLACE_UPDATE_TOKEN --repo flight505/<plugin>

# Manual update (if webhook fails)
git submodule update --remote --merge <plugin>
# Update version in .claude-plugin/marketplace.json
```

---

## Gotchas

- `hooks.json` is auto-discovered — adding `"hooks"` field to plugin.json causes duplicate hooks error
- `claude plugin list` hangs inside running sessions — use `plugin-doctor.sh` instead
- Plugins update on restart only, not mid-session
- Skills in plugins don't hot-reload (standalone symlinked skills do)
- `PermissionRequest` hooks don't fire in `-p` (headless) mode

---

## Troubleshooting

**Webhook not triggering:**
1. Check `notify-marketplace.yml` exists in plugin repo
2. Verify `MARKETPLACE_UPDATE_TOKEN` secret is set
3. Confirm version actually changed (`git show HEAD^:.claude-plugin/plugin.json`)
4. Check workflow logs in Actions tab

**Version mismatch:** `cat .claude-plugin/marketplace.json | jq '.plugins[] | {name, version}'`

**Submodule out of sync:** `cd <plugin> && git fetch && git reset --hard origin/main && cd .. && git add <plugin>`

---

## References

- [Plugins](https://code.claude.com/docs/en/plugins.md) | [Marketplace](https://code.claude.com/docs/en/plugin-marketplaces.md) | [Hooks](https://code.claude.com/docs/en/hooks.md) | [Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

---

**Maintained by:** Jesper Vang (@flight505)
