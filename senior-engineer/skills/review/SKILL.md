---
name: review
description: >
  Deep architectural code review that reads all files in the target area, maps
  dependencies and state flow, checks framework compliance against current docs,
  and ranks structural issues by criticality. Use when code quality feels off,
  before major features, when patches keep accumulating, or when you suspect the
  architecture is fighting itself.
argument-hint: "[module or directory to review]"
user-invocable: true
effort: high
---

# Senior Engineer Review

You perform a structural code review — not a linter pass. You read everything, map the
system, and identify where the architecture is producing problems that patches can't fix.

**Project root:** !`git rev-parse --show-toplevel 2>/dev/null || pwd`

## Step 1: Scope the Review

- **If the user specified a target** (module, directory, feature) → use it
- **If no target** → ask: "What area should I review? A module path, feature, or 'everything'?"
- **For "everything"** → start at entry points, trace outward

## Step 2: Map the Code

Read systematically. Spawn the `code-mapper` agent for parallel discovery:

```
Spawn the code-mapper agent to map all files, dependencies, and state flow for [target].
```

While it runs, start reading entry points yourself. Track:
- Where state lives and how it flows
- Abstraction boundaries (what's coupled that shouldn't be)
- Framework usage — native APIs or workarounds?
- Error handling — consistent or ad-hoc?

## Step 3: Check Framework Compliance

For each technology in the codebase:
1. Is the code using the framework's **native capabilities**?
   - Example: Tauri's Rust invoke vs Node.js HTTP workarounds
   - Example: Next.js Server Components vs client-side fetching
2. Are there **deprecated APIs** or patterns?
3. Does the current framework version offer a **better way**?

Look up documentation: use project doc skills if installed, context7 MCP if available,
or WebSearch for current best practices.

## Step 4: Classify Each Issue

| Level | When |
|-------|------|
| PATCH | Isolated bug, local fix is correct |
| REFACTOR | Design intent is right, organization obscures it |
| REWRITE | Approach is wrong — structure produces the problem |
| RETHINK | Wrong tool/framework/paradigm entirely |

**Auto-escalate to REWRITE when:**
- Same bug class appeared more than once in this subsystem
- Fix requires changing >40% of a module for structural reasons
- Adding features fights the existing structure instead of extending it
- State is implicit, duplicated, or scattered across layers
- An abstraction was built for a problem that no longer exists

## Step 5: Report

```
## Code Review: [Target]

### Verdict
[One paragraph: overall health, most critical concern]

### Critical (REWRITE/RETHINK)
1. **[Title]** — REWRITE
   Where: [file:line]
   Why structural: [why patches can't fix this]
   Recommended: [one sentence approach]

### Important (REFACTOR)
2. **[Title]** — REFACTOR
   ...

### Minor (PATCH)
3. **[Title]** — PATCH
   ...

### Framework Compliance
| Technology | Status | Issue |
|-----------|--------|-------|

### Priority
1. [Fix this first]
2. [Then this]
```

## Agent Team Mode

If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled, spawn an adversarial team:

```
Create an agent team to review [target]:
- code-structure: dependencies, coupling, state management
- framework-compliance: native API usage, workarounds, deprecated patterns
- devil's-advocate: challenge the architecture, propose alternatives

Have them debate. The devil's-advocate tries to disprove
the code-structure reviewer's defense of the current design.
```

The debate counters anchoring bias — solo reviewers stop at the first plausible issue.
If agent teams are unavailable, do a solo review using the steps above.
