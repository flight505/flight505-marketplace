---
name: explaining-why
description: "Explains the reasoning behind the last non-trivial decision with alternatives considered and concepts worth knowing. Use when curious about a choice Claude made, when you want to understand a tradeoff, after any architecture or library decision, or when you'd describe something as 'that thing Claude just did.'"
---

# Explaining Why

## Overview

This skill surfaces the reasoning behind decisions that might otherwise go unexplained. It produces a structured explanation that names the road not taken and teaches the underlying concept. When invoked, it reviews the conversation history to find the most recent non-trivial choice and breaks it down into what was chosen, what was rejected, and the principle that guided the decision.

## When to Invoke

- User types `/why`
- User asks "why did you do that?" or "what was the reasoning?"
- After any non-trivial decision that wasn't already explained

## Output Format

For each decision, output this block:

### Decision: <one-line label>
**Chose:** <what you did and the core reason>
**Rejected:** <1-2 alternatives and why they lost>
**Concept:** <the underlying principle or pattern worth knowing — one sentence>

If the decision involves a Claude Code concept (hooks, skills, plugins, agents, worktrees, MCP, tools):
- Check if `claude-docs-skill` is installed (look for it in the skills list)
- If available, read the relevant documentation to give an accurate, current answer
- If not available, explain from general knowledge but note that `claude-docs-skill` would give a more detailed answer

## Vocabulary Note

If the user described the concept casually (e.g., "that parallel thing" instead of "worktree isolation"), add:

> **Term:** <proper name>
> **You said:** <how you described it>
> **Next time:** <shorter, more precise way to ask>

Only add this if there's a genuine vocabulary gap. Skip if the user already used correct terminology.

## Edge Cases

- **No recent non-trivial decision:** Say so honestly. Don't fabricate a decision to explain. Suggest the user ask after Claude makes a meaningful choice.
- **Multiple recent decisions:** Explain the most recent one. If the user wants a different one, they can specify.
- **Trivial decisions (formatting, variable names):** These don't need /why. Politely note that and offer to explain if they're genuinely curious.

## What Makes a Good Explanation

- **Name the road not taken.** The rejected alternative is often more informative than the choice itself.
- **One concept per decision.** Don't lecture — identify the single most important principle.
- **Be honest about uncertainty.** If the choice was arbitrary or there was no strong reason, say so.
- **Connect to the user's context.** Explain why this matters for THEIR project, not in the abstract.
