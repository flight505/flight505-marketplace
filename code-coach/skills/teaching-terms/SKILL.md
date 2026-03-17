---
name: teaching-terms
description: "Reviews the session and teaches proper programming terms for concepts described casually, with memory so it never re-teaches. Use when you want to learn the right words for what you just did, build programming vocabulary, or after a session where you described things informally."
---

# Teaching Terms

## Overview

This skill bridges the gap between how developers casually describe what they want and the precise terminology that makes communication faster and search more effective. It reviews what happened in the session and identifies vocabulary opportunities.

## When to Invoke

- User types `/teach`
- After a non-trivial session where the user described things casually
- When the user says "what's the proper term for..." or "what do you call..."

## How It Works

### Step 1: Review the Session

Scan the conversation for places where the user described something casually that has a well-known programming or Claude Code term. Look for:
- Informal descriptions of patterns ("that thing where you split work into separate copies" -> "git worktrees")
- Casual tool references ("the parallel execution thing" -> "/batch")
- Vague architecture descriptions ("the layer that catches errors" -> "error boundary" or "middleware")
- Process descriptions ("checking if it works before saying it's done" -> "verification gate")

### Step 2: Check Memory

Before teaching a term, check auto-memory for previously taught terms. If the user has already been taught a term in a prior session, skip it -- don't re-teach known vocabulary.

### Step 3: Output 2-3 Terms

For each term, output:

> **Term:** <the proper name>
> **You said:** <how you described it, quoted from the session>
> **Next time:** <a shorter, more precise way to ask>
> **In context:** <one sentence showing the term used naturally in the current project's context>

### Step 4: Save to Memory

Save newly taught terms to auto-memory so they won't be re-taught in future sessions. Use the memory system to write a brief entry like:
- Memory type: `user`
- Content: "Jesper has learned: [term1], [term2], [term3]"

## Scope of Terms

Teach both categories:

### Programming Terms

- Design patterns (observer, factory, strategy, decorator, etc.)
- Architecture concepts (middleware, dependency injection, event loop, closure, etc.)
- Data structures and algorithms (trie, hash map, BFS, memoization, etc.)
- Development practices (TDD, CI/CD, trunk-based development, feature flags, etc.)

### Claude Code Terms

- Features: worktrees, skills, hooks, agents, MCP servers, context fork, auto-memory
- Commands: /batch, /loop, /plan, /simplify, /debug
- Concepts: progressive disclosure, skill frontmatter, hook events, plugin manifest
- Patterns: polyglot runner, session injection, tier-based routing

## Edge Cases

- **User used correct terminology throughout:** Positive reinforcement. Say something like "You used precise terminology this session -- no new terms to teach." Don't force vocabulary where none is needed.
- **Too many opportunities:** Pick the 2-3 most impactful terms. Prioritize terms the user will use frequently over obscure ones.
- **User asks about a specific term:** Explain it directly rather than following the full review process.

## What Makes Good Vocabulary Coaching

- **Maximum 2-3 terms per invocation.** This is not a lecture.
- **Quote the user's actual words.** "You said" must come from the session, not be paraphrased.
- **The "Next time" should be genuinely shorter.** If the proper term is longer than what the user said, it's not helpful to suggest.
- **Context matters.** "In context" grounds the term in the user's actual project, not a textbook example.
- **Progressive, not repetitive.** Memory-aware coaching that builds over time.
