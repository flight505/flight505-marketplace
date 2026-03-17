# Claude Code Feature Catalog

> Organized by what you want to accomplish, not by feature name.
> For detailed docs, use claude-docs-skill.

## I want to run something repeatedly

- **`/loop [interval] <command>`** — Run a command on a recurring interval (default 10m). Great for: test watching, deploy monitoring, status polling. Example: `/loop 30s pnpm test`

## I want to parallelize independent work

- **`/batch <plan>`** — Spawns 5-30 parallel worktree agents, each implementing + testing + creating PRs. Use when: 5+ independent files/modules need the same type of change. Each agent works in isolation.
- **`isolation: worktree`** on Agent tool — Run a single sub-agent in an isolated git worktree copy.

## I want to plan before coding

- **`/plan`** — Enter plan mode for design-before-code. Claude explores the codebase, designs an approach, and presents it for approval before writing any code.
- **`EnterPlanMode` tool** — Programmatic entry into plan mode.

## I want to automate checks and validations

- **Hooks** — Shell commands, LLM prompts, or agent-based verifiers that fire on events:
  - `SessionStart` — Inject context at session start/resume/clear/compact
  - `PreToolUse` / `PostToolUse` — Before/after any tool executes (e.g., run linter after every Edit)
  - `UserPromptSubmit` — Process user input before Claude sees it
  - `Stop` — Run checks when Claude finishes a response
  - `PreCompact` / `PostCompact` — Before/after context compaction
  - `Notification` — Intercept notifications
- **Hook types:** `command` (shell), `prompt` (LLM-evaluated), `agent` (agentic verifier)
- **Config:** `hooks/hooks.json` in plugin directory or `.claude/hooks.json` in project

## I want to persist knowledge across sessions

- **Auto-memory** — Claude automatically saves and retrieves preferences, project context, and references across sessions. Stored in `~/.claude/projects/<path>/memory/`.
- **CLAUDE.md files** — Project instructions loaded every session:
  - `~/.claude/CLAUDE.md` — Global (all projects)
  - `./CLAUDE.md` — Project root (checked into git)
  - `./.claude/CLAUDE.md` — Project local (gitignored)
- **`.claude/rules/*.md`** — Modular instruction files, all auto-loaded

## I want isolated workspaces

- **Git worktrees** — `git worktree add ../feature-branch feature-branch` creates a separate working directory for a branch without switching. Claude Code has `EnterWorktree` / `ExitWorktree` tools.
- **`claude --worktree`** — Start a Claude session in an isolated worktree automatically.
- **`worktree.sparsePaths`** setting — For monorepos, only checkout specific directories in worktrees.

## I want to create reusable patterns

- **Skills** — Markdown files in `.claude/skills/` or plugin `skills/` directories. Loaded on demand via the Skill tool. Frontmatter: `name`, `description`, optional `context: fork`, `agent:`, `model:`, `hooks:`.
- **Commands** — Thin wrappers in plugin `commands/` that invoke skills with specific arguments. User types `/plugin-name:command-name`.
- **Agents** — Markdown files in `.claude/agents/` or plugin `agents/` with YAML frontmatter. Used via `agent:` field in skill frontmatter or directly with Agent tool.

## I want to extend Claude with external services

- **MCP servers** — Model Context Protocol servers connect Claude to external APIs, databases, browsers, etc. Configured in `.mcp.json` (project) or `~/.claude/mcp.json` (global).
- **Available built-in:** Playwright (browser automation), GitHub, etc.
- **Custom:** Any MCP-compatible server.

## I want to review and simplify code

- **`/simplify`** — Launches 3 parallel review agents on recent changes. Checks for: reuse opportunities, code quality, efficiency improvements.
- **`/debug [description]`** — Troubleshoot current session via debug log analysis.

## I want to work with sub-agents

- **Agent tool** — Launch sub-agents with optional `subagent_type`:
  - `Explore` — Fast codebase exploration (glob, grep, read)
  - `Plan` — Design and architecture planning
  - `general-purpose` — Full capability agent
- **`model:` parameter** — Override the model for a specific agent invocation
- **`context: fork`** in skill frontmatter — Run the skill in an isolated sub-agent session

## I want to configure Claude's behavior

- **Settings:** `~/.claude/settings.json` (global) or `.claude/settings.json` (project)
- **Permissions:** `allowedTools`, `denyTools` — control which tools Claude can use
- **Model selection:** `/model` to switch models mid-session
- **Reasoning effort:** `--reasoning-effort` flag, or type "ultrathink" for maximum reasoning

## I want to build a plugin

- **Plugin structure:** `.claude-plugin/plugin.json` manifest + skills/ + commands/ + hooks/ + agents/
- **Marketplace:** `.claude-plugin/marketplace.json` for distributing multiple plugins
- **Testing:** `claude plugin validate <path>` to validate manifest
- **Distribution:** Users install via `claude plugin install <name>@<marketplace>`
