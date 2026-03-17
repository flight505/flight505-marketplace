# CLAUDE.md

**Version 1.0.0** | Last Updated: 2026-03-17

Developer instructions for the Code Coach plugin.

---

## Overview

Code Coach is a **fluency coach for Claude Code** — it teaches effective workflows, explains decisions, builds programming vocabulary, and surfaces features users didn't know existed. Pure markdown skills, zero runtime dependencies.

---

## Architecture

```
code-coach/
├── .claude-plugin/plugin.json        # Plugin manifest
├── commands/                          # 4 shortcut commands
│   ├── why.md                        # → code-coach:explaining-why skill
│   ├── teach.md                      # → code-coach:teaching-terms skill
│   ├── suggest.md                    # → code-coach:suggesting-workflows skill
│   └── explain.md                    # → code-coach:explaining-concepts skill
├── hooks/
│   ├── hooks.json                    # 1 hook (SessionStart)
│   ├── run-hook.cmd                  # Cross-platform hook runner
│   └── session-start                 # Injects using-coach awareness
└── skills/                           # 5 skills
    ├── explaining-why/               # Reasoning behind decisions
    ├── teaching-terms/               # Programming vocabulary coaching
    ├── suggesting-workflows/         # Better Claude Code workflows
    ├── explaining-concepts/          # Concept explanations with project context
    └── using-coach/                  # Command awareness (session injection)
```

### Components

| Type | Count | Notes |
|------|-------|-------|
| Skills | 5 | Coaching patterns (why, teach, suggest, explain, awareness) |
| Commands | 4 | why, teach, suggest, explain (shortcuts to skills) |
| Hooks | 1 | SessionStart (inject command awareness) |
| Agents | 0 | — |
| Config | 0 | — |

---

## Development Guidelines

### Modifying Skills

- Skills are pure markdown — no runtime code, no dependencies
- Frontmatter: `name` + `description` required
- Description: hybrid pattern — what it does + "Use when..." triggers (under 420 chars)
- `${CLAUDE_SKILL_DIR}` for self-references within skill content

### Naming Convention

Commands and skills use **different names** to avoid circular invocation:
- `why.md` (command) invokes `explaining-why` (skill)
- `teach.md` (command) invokes `teaching-terms` (skill)
- `suggest.md` (command) invokes `suggesting-workflows` (skill)
- `explain.md` (command) invokes `explaining-concepts` (skill)

Never create a command with the same name as a skill — both register as `code-coach:<name>`, causing loops.

### Testing Changes

```bash
# From marketplace root
./scripts/validate-plugin-manifests.sh
./scripts/plugin-doctor.sh

# Verify hooks
chmod +x code-coach/hooks/*
bash code-coach/hooks/session-start
```

### File Conventions

| Context | Pattern |
|---------|---------|
| Hook commands | `'${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd' <script>` |
| Hook scripts | Extensionless filenames (e.g. `session-start` not `session-start.sh`) |
| Skills | Relative paths within skill directory |
| Naming | `kebab-case` everywhere |
| Permissions | `chmod +x hooks/*` |

---

## Gotchas

- Never add `"hooks"` field to plugin.json — `hooks/hooks.json` is auto-discovered
- Hook scripts use extensionless filenames to avoid Windows auto-detection issues
- Hook scripts run in non-interactive shells — no aliases, no .zshrc
- Use `python3` not `python` in hook commands (macOS has no `python` binary)
- Skills in plugins don't hot-reload (standalone symlinked skills do)
- Plugins update on restart only, not mid-session
- Use `/reload-plugins` to activate plugin changes without restart (2.1.69+)

---

## References

- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md)
- [Plugin Development](https://code.claude.com/docs/en/plugins.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/code-coach
**License:** MIT
