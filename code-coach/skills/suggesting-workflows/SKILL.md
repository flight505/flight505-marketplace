---
name: suggesting-workflows
description: "Suggests Claude Code features and workflows that would improve how you're working right now, with exact commands to use. Use when something feels inefficient, when doing repetitive manual work, when starting a new project, or when you want to discover features you didn't know existed."
---

# Suggesting Workflows

## Overview

Most Claude Code users utilize about 20% of its capabilities. This skill observes what you're doing and suggests specific features that would help — with exact commands, not vague pointers.

## When to Invoke

- User types `/suggest`
- User says "is there a better way to do this?"
- When the user is clearly doing something manually that Claude Code can automate
- When starting a new type of project or workflow

## How It Works

### Step 1: Observe Current Workflow

Analyze the conversation context for patterns:
- What task is the user working on?
- What tools and commands have been used?
- What's being done manually that could be automated?
- What scale is the work (single file? multi-file? cross-repo?)

### Step 2: Cross-Reference Features

Read the feature catalog at `${CLAUDE_SKILL_DIR}/feature-catalog.md` for a comprehensive map of Claude Code capabilities organized by user intent.

If `claude-docs-skill` is installed, read relevant documentation sections for detailed feature information and current syntax.

### Step 3: Output 1-3 Suggestions

For each suggestion:

### Suggestion: <short label>

**What you're doing:** <describe the current manual/suboptimal approach>
**Better approach:** <the Claude Code feature that addresses it>
**How to use it:**
```
<exact command, config, or setup — copy-pasteable>
```
**Why it's better:** <one sentence on the concrete benefit>

### Step 4: Skip What's Already Working

Don't suggest features the user is already using effectively. If they're already using /batch for parallel work, don't suggest /batch.

## Common Suggestion Patterns

| What You're Doing | Suggest |
|-------------------|---------|
| Running tests manually after each change | `/loop 30s pnpm test` — auto-reruns on interval |
| Implementing 5+ independent files sequentially | `/batch <plan>` — parallel worktree agents |
| Manually checking if work is done | `verification-before-completion` skill (if TaskPlex installed) |
| Repeating the same instructions every session | Create a CLAUDE.md or project-level `.claude/rules/*.md` |
| Copy-pasting between sessions | Auto-memory system — Claude remembers across sessions |
| Not sure what approach to take | `/plan` — enter plan mode for design-first thinking |
| Debugging by trial and error | `systematic-debugging` skill (if TaskPlex installed) |
| Writing code before tests | `test-driven-development` skill (if TaskPlex installed) |
| Want to automate a recurring check | Hooks — `PostToolUse`, `UserPromptSubmit`, `Stop` events |
| Working on multiple features | Git worktrees — isolated branches without switching |
| Need external service data | MCP servers — connect to APIs, databases, services |
| Large codebase, slow navigation | `Explore` agent type — fast codebase exploration |
| Repetitive prompt patterns | Skills — create reusable `.claude/skills/` markdown files |

## What Makes a Good Suggestion

- **Specific, not vague.** Not "you could use hooks" but "add a PostToolUse hook that runs `pnpm typecheck` after every Edit — here's the hooks.json entry."
- **Copy-pasteable.** The "How to use it" section should be something the user can run immediately.
- **Relevant to NOW.** Suggest features for the current task, not hypothetical future needs.
- **Honest about tradeoffs.** If a feature has setup cost, say so. "This takes 5 minutes to set up but saves you from manually running tests every time."

## Edge Cases

- **User is already optimal:** Say so. "Your current workflow is solid — no suggestions this time."
- **claude-docs-skill not installed:** Fall back to feature-catalog.md. Mention that installing claude-docs-skill would give more detailed, current feature information.
- **Multiple equally good suggestions:** Prioritize by impact — which one saves the most time or prevents the most errors?
