# Senior Engineer

A Claude Code plugin that forces the "stop, read everything, research, evaluate, then implement" workflow that senior engineers follow but Claude usually skips.

## The Problem

Claude's default behavior is to immediately produce a fix. When the fix should be a rewrite, Claude patches instead — using HTML workarounds when it should use native APIs, bolting on Node.js when it should use Rust, or applying band-aids to structural problems. The code works but the architecture degrades with every patch.

## The Solution

Two commands that enforce a disciplined workflow:

### `/senior-engineer:review` — Deep Code Review

Reads all files in the target area, maps dependencies, and identifies structural issues ranked by criticality. Classifies each issue as PATCH, REFACTOR, REWRITE, or RETHINK.

When agent teams are available, spawns adversarial reviewers who debate findings — countering the anchoring bias that makes solo reviewers stop at the first plausible issue.

### `/senior-engineer:rewrite` — Researched Rewrite

1. **Read** — systematically reads all files connected to the problem
2. **Research** — looks up framework documentation for the correct approach (context7, web search, doc skills)
3. **Evaluate** — presents up to 3 options with pros/cons/effort/risk
4. **Approve** — stops and waits for user approval before writing any code
5. **Implement** — creates an isolated worktree, implements the approved approach
6. **Present** — shows the diff for final review

## Installation

```bash
# From the flight505-marketplace
claude plugins install senior-engineer@flight505-plugins
```

## Agents

| Agent | Role | Model | Isolation |
|-------|------|-------|-----------|
| `code-mapper` | Maps files, dependencies, state flow | Sonnet | None (read-only) |
| `doc-researcher` | Researches framework docs and best practices | Sonnet | None (read-only) |
| `implementer` | Implements approved rewrites | Inherited | Worktree |

## Requirements

- Claude Code 2.1.72+ (for EnterWorktree/ExitWorktree tools)
- Git repository (for worktree isolation)
- Optional: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for adversarial review mode
- Optional: context7 MCP server for framework documentation lookup

## Author

Jesper Vang (@flight505)
