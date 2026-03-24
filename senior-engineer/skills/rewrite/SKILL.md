---
name: rewrite
description: >
  Researched rewrite that reads all related files, looks up framework documentation
  for the correct approach, evaluates up to 3 options with pros and cons, waits for
  approval, then implements in an isolated worktree. Use when a review found a REWRITE
  issue, when Claude has been patching around a structural problem, or when you know
  the approach is wrong but need to find the right one.
argument-hint: "[problem description or file path]"
user-invocable: true
effort: high
---

# Senior Engineer Rewrite

You do a researched, methodical rewrite. Not a patch. The entire point is to stop,
research the correct approach, evaluate options, and get approval before writing code.

**Project root:** !`git rev-parse --show-toplevel 2>/dev/null || pwd`

## Step 1: Define the Problem

- **After a review** → the issue to fix should be clear from the review findings
- **Direct invocation** → ask: "What needs to be rewritten?" if not specified via $ARGUMENTS
- **No context at all** → suggest running `/senior-engineer:review` first

State clearly before proceeding:

```
**Problem:** [what's broken]
**Where:** [file:line references]
**Why patches fail:** [structural reason]
**Current behavior:** [what happens now]
**Desired behavior:** [what should happen]
```

## Step 2: Read Everything Connected

Not just the broken file — everything it touches.

Spawn the `code-mapper` agent:
```
Spawn code-mapper to trace all files connected to [problem area]:
imports, dependents, config, and tests.
```

Build a behavioral spec from what you read: what does this code do (including
bugs and workarounds), and what constraints exist (performance, compatibility,
framework requirements)?

## Step 3: Research the Right Approach

**This is the step Claude usually skips. Do NOT skip it.**

Spawn the `doc-researcher` agent:
```
Spawn doc-researcher to look up:
1. [Framework] documentation for [specific topic]
2. Current best practices for [pattern]
3. Whether [current approach] is recommended in [framework version]
```

Also check: project doc skills (if installed), context7 MCP (if available).

Document findings:
```
**Docs recommend:** [what the framework says]
**Our code does:** [how we diverge]
**Native API available:** [yes/no, which one]
**Source:** [URL or doc reference]
```

## Step 4: Evaluate Options

Present up to 3 approaches:

```
## Option A: [Name]
**Approach:** [2-3 sentences]
**Pros:** [concrete benefits]
**Cons:** [concrete drawbacks]
**Effort:** [small / medium / large]
**Framework alignment:** [follows best practices? yes/no]

## Option B: [Name]
...

## Recommendation: Option [X]
**Why:** [senior engineer reasoning]
**Why not the others:** [brief dismissal]
```

## Step 5: Approval Gate

**STOP. Do not write code until the user approves.**

Present the problem, research, options, and recommendation. Ask:
"Proceed with Option [X], or prefer a different approach?"

## Step 6: Implement in Worktree

After approval, isolate the work:

```
EnterWorktree to create an isolated branch for this rewrite.
```

Or spawn the `implementer` agent (which has `isolation: worktree`):
```
Spawn the implementer agent with:
- Problem statement
- Approved approach (Option X)
- Research findings (framework docs, correct APIs)
- Behavioral spec (what the code must do)
```

Implementation rules:
1. Write new code first — don't modify old files until the new approach works
2. Use framework-native patterns — that's the whole point
3. Run existing tests — they must pass
4. One concern per commit

## Step 7: Present the Diff

```
## Rewrite Complete
**Changes:** [git diff --stat]
**What changed:** [file-by-file summary]
**Tests:** [pass/fail count]
**Before → After:** [how the problem is resolved]
```

Ask: "Merge to main, adjust, or discard?"

## No Worktree Fallback

If not in a git repo: create new files with `.rewrite.` suffix, present diff
between old and new, let the user decide when to swap.
