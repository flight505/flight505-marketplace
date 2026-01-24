# Marketplace Hooks

## PostToolUse.sh - Session-Aware Cache Manager

**Status:** ✅ Active

### What It Does

Automatically detects plugin version bumps and manages cache clearing intelligently:

1. **Monitors** Edit/Write operations on `plugin.json` files in submodules
2. **Detects** version field changes
3. **Counts** active Claude Code sessions
4. **Decides** whether to clear cache based on session count:
   - **1 session** → ✅ Auto-clear cache (safe)
   - **Multiple sessions** → ⚠️ Warn only (conflict risk)
   - **0 sessions** → ⚠️ Skip (unusual state)

### Why This Matters

**Known Claude Code CLI Bug:**
- [Issue #14061](https://github.com/anthropics/claude-code/issues/14061): `/plugin update` doesn't invalidate cache
- [Issue #15369](https://github.com/anthropics/claude-code/issues/15369): Reinstall reads stale cache

**This hook works around the bug** by clearing cache when you bump versions during development.

### Session Detection Logic

```bash
# Counts active claude processes
pgrep -f "claude" | wc -l
```

**Single session (safe):**
- You're working in this marketplace project only
- No other Claude sessions active
- Hook auto-clears cache for updated plugin
- You get a success message

**Multiple sessions (unsafe):**
- Other Claude projects open using flight505 plugins
- Cache clearing could corrupt `installed_plugins.json`
- Hook warns but doesn't act
- Manual steps provided

### Output Examples

**Single Session (Auto-Clear):**
```
[CACHE-MANAGER] Detected version change in sdk-bridge: v4.5.0
[CACHE-MANAGER] Active Claude Code sessions: 1
[CACHE-MANAGER] ✅ Single session detected - safe to clear cache
[CACHE-MANAGER] Clearing cache for sdk-bridge...
[CACHE-MANAGER] ✅ Cache cleared: /Users/jesper/.claude/plugins/cache/flight505-plugins/sdk-bridge

╔════════════════════════════════════════════════════════════════╗
║  Plugin Cache Cleared                                          ║
╠════════════════════════════════════════════════════════════════╣
║  Plugin: sdk-bridge
║  Version: v4.5.0
║  Cache: Cleared automatically
║
║  Next steps:
║  1. Commit and push: git commit -m 'chore: bump sdk-bridge to v4.5.0'
║  2. Reinstall plugin: /plugin uninstall sdk-bridge@flight505-plugins
║                      /plugin install sdk-bridge@flight505-plugins
╚════════════════════════════════════════════════════════════════╝
```

**Multiple Sessions (Warning):**
```
[CACHE-MANAGER] Detected version change in storybook-assistant: v2.2.0
[CACHE-MANAGER] Active Claude Code sessions: 3
[CACHE-MANAGER] ⚠️  Multiple sessions detected (3)
[CACHE-MANAGER] Cache clearing skipped to avoid conflicts

╔════════════════════════════════════════════════════════════════╗
║  ⚠️  Multiple Claude Code Sessions Detected                    ║
╠════════════════════════════════════════════════════════════════╣
║  Plugin: storybook-assistant
║  Version: v2.2.0
║  Sessions: 3 active
║
║  Cache NOT cleared automatically (conflict risk)
║
║  Manual steps after closing other sessions:
║  1. Exit all other Claude Code sessions
║  2. Clear cache: rm -rf ~/.claude/plugins/cache/flight505-plugins/storybook-assistant
║  3. Reinstall: /plugin uninstall storybook-assistant@flight505-plugins
║               /plugin install storybook-assistant@flight505-plugins
╚════════════════════════════════════════════════════════════════╝
```

### Testing

**Test the hook manually:**
```bash
# Simulate a version bump (creates test input)
echo '{"tool_name":"Edit","tool_input":{"file_path":"sdk-bridge/.claude-plugin/plugin.json"}}' | \
    .claude/hooks/PostToolUse.sh

# Should output session count and decision
```

**Test during development:**
1. Edit `sdk-bridge/.claude-plugin/plugin.json` (bump version)
2. Hook runs automatically
3. Check output for cache clear confirmation

### Maintenance

**Disable hook temporarily:**
```bash
chmod -x .claude/hooks/PostToolUse.sh
```

**Re-enable:**
```bash
chmod +x .claude/hooks/PostToolUse.sh
```

**View hook logs** (if hook redirects to log file):
```bash
tail -f .claude/hooks/cache-manager.log
```

### Integration with Validators

This hook complements the existing validation hooks:
- `validators/plugin-manifest-validator.py` - Validates manifest format
- `validators/marketplace-sync-validator.py` - Validates version sync
- **PostToolUse.sh** - Manages cache after valid version changes

All hooks run automatically on Edit/Write operations.

### Technical Details

**Hook Trigger:** PostToolUse (runs after Edit/Write tool completes)

**Input Format:** JSON via stdin
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "sdk-bridge/.claude-plugin/plugin.json",
    "old_string": "...",
    "new_string": "..."
  }
}
```

**Exit Codes:**
- `0` - Success (always, hook is informational)

**Dependencies:**
- `jq` - JSON parsing
- `pgrep` - Process detection
- Standard Unix tools (grep, wc, rm, etc.)

### Future Enhancements

Potential improvements:
- [ ] Log to file for audit trail
- [ ] Detect version bump vs other plugin.json changes
- [ ] Integration with `bump-plugin-version.sh` script
- [ ] Notification when webhook completes
- [ ] Auto-reinstall plugin if single session

---

**Created:** 2026-01-23
**Last Updated:** 2026-01-23
