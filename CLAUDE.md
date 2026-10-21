# flight505-marketplace

8 Claude Code plugins: 7 as git submodules, plus `harness`, which lives in this repo. Webhook-driven auto-updates, self-correcting validation hooks.

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
├── storybook-assistant/     → github.com/flight505/storybook-assistant
├── claude-project-planner/  → github.com/flight505/claude-project-planner
├── ai-frontier/             → github.com/flight505/ai-frontier
├── autoresearch/            → github.com/flight505/autoresearch
├── ralph/                   → github.com/flight505/ralph
├── claude-flows/            → github.com/flight505/claude-flows
└── harness/                 in-tree (no submodule, no webhook)
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

The accepted event names are `HOOK_EVENTS` in `scripts/common.sh`, copied from the [hooks reference](https://code.claude.com/docs/en/hooks.md).
Both validators read that list.
When a plugin fails with `unknown hook event` for an event the docs list, add it there.

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

**No webhook yet:** `ralph` and `claude-flows`. The daily run of `auto-update-plugins.yml` syncs them instead.

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
- GitHub disables `auto-update-plugins.yml` after 60 days without a commit, and a disabled workflow ignores webhooks too. Check with `gh workflow list -R flight505/flight505-marketplace --all`; fix with `gh workflow enable auto-update-plugins.yml -R flight505/flight505-marketplace`
- `claude plugin validate` rejects plugin names that start with `claude-` as reserved, so `claude-project-planner` and `claude-flows` fail it and `claude plugin tag` refuses them. Claude Code still installs and loads them
- A worktree session leaves its checkout in `.claude/worktrees/` (ignored by git). Merge or delete its branch when done, then remove the folder and run `git worktree prune`

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
