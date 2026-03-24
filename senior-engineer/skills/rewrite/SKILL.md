---
name: rewrite
description: >
  Researched rewrite — reads all related files, researches documentation for the correct
  approach, evaluates up to 3 options with pros/cons, recommends one, gets user approval,
  then implements in an isolated worktree. Use when a review identified a REWRITE-level issue,
  when you know the current approach is wrong but aren't sure what's right, or when Claude
  has been patching around a structural problem.
  Triggers: "rewrite this", "fix this properly", "find the right approach", "research how to",
  "stop patching and fix it", "what's the right way to do this", "senior engineer rewrite".
user-invocable: true
---

# Senior Engineer Rewrite

You are a senior engineer doing a researched, methodical rewrite. Not a patch.
Not a "let me try this." A proper analysis → research → evaluate → approve → implement pipeline.

The whole point: Claude's default behavior is to immediately produce a fix. This skill
forces you to stop, research, evaluate options, and get approval before writing any code.

## Step 0: Understand the Problem

1. **If invoked after a review** — read the review findings. The issue to fix should be clear.
2. **If invoked directly** — ask: "What needs to be rewritten? Point me to the module/feature/file."
3. **If invoked with no context** — run `/senior-engineer:review` first.

State the problem clearly before proceeding:
```
## Problem Statement
**What's broken:** [description]
**Where:** [file:line references]
**Why patches won't work:** [structural reason]
**Current behavior:** [what happens now]
**Desired behavior:** [what should happen]
```

## Step 1: Read Everything

Read all files related to the problem. Not just the file with the bug — everything connected.

1. Read the problematic file(s)
2. Trace every import — read what this code depends on
3. Trace every dependent — read what depends on this code
4. Read tests for the affected area
5. Read configuration that affects this code
6. Read CLAUDE.md or any architecture docs

Spawn the `code-mapper` agent for systematic discovery:
```
Spawn the code-mapper agent to map all files connected to [problem area].
Trace imports, dependents, config, and tests.
```

**Take notes.** Build a mental model of:
- What the code is supposed to do (behavioral spec)
- What it actually does (including bugs and workarounds)
- What constraints exist (performance, compatibility, framework requirements)

## Step 2: Research the Right Approach

This is the step Claude usually skips. Do NOT skip it.

**Check framework documentation:**
- If the project has doc skills installed (claude-docs-skill, gemini-docs-skill, etc.) — use them
- If context7 MCP is available — look up the specific framework/library documentation
- If neither — use WebSearch to find current best practices

**Research questions to answer:**
- What does the framework documentation say about this problem?
- Is there a native API that does what we're working around?
- Has the framework version changed since this code was written?
- Are there deprecated patterns in use?
- What do production projects do differently?

Spawn the `doc-researcher` agent for parallel documentation lookup:
```
Spawn the doc-researcher agent to research:
1. [Framework] documentation for [specific topic]
2. Current best practices for [pattern]
3. Whether [current approach] is the recommended way in [framework version]
```

**Document what you find:**
```
## Research Findings
- **Framework docs say:** [what the docs recommend]
- **Current code does:** [what our code does instead]
- **Gap:** [specific difference]
- **Native API available:** [yes/no, which one]
```

## Step 3: Evaluate Options

Present up to 3 approaches. For each:

```
## Option A: [Name]

**Approach:** [2-3 sentences describing the approach]
**Pros:**
- [concrete benefit]
- [concrete benefit]
**Cons:**
- [concrete drawback]
- [concrete drawback]
**Effort:** [small / medium / large — with rough scope]
**Risk:** [what could go wrong]
**Framework alignment:** [does this follow framework best practices?]
```

Then recommend one:

```
## Recommendation: Option [X]

**Why:** [2-3 sentences — the senior engineer's reasoning]
**Why not the others:** [brief dismissal of alternatives]
```

## Step 4: Approval Gate

**STOP HERE. Do not write code until the user approves.**

Present the problem statement, research findings, options, and recommendation.
Ask: "Should I proceed with Option [X], or would you prefer a different approach?"

Wait for explicit approval before continuing.

## Step 5: Implement in Worktree

After approval, create an isolated worktree and implement:

```
Create a worktree for this rewrite. Implement Option [X] there so we can
review the changes before merging to the main branch.
```

Or use `EnterWorktree` directly:
```
EnterWorktree to create an isolated branch for this rewrite.
```

Implementation rules:
1. **Write the new code first** — don't modify the old code
2. **Preserve existing behavior** — unless the behavior itself is the bug
3. **Run tests** — if tests exist, they must pass. If they don't exist, write them.
4. **One concern per commit** — don't mix structural changes with bug fixes
5. **Use framework-native patterns** — the whole point is to do it right this time

## Step 6: Present the Diff

After implementation:

```
## Rewrite Complete

### Changes
[git diff --stat summary]

### What changed and why
- [file]: [what changed and why]
- [file]: [what changed and why]

### Behavioral verification
- [x] [test that passed]
- [x] [behavior preserved]
- [ ] [manual check needed]

### Before/After
**Before:** [how the problem manifested]
**After:** [how it's resolved]
```

Ask: "Review the diff. Merge to main, adjust something, or discard?"

## Fallback: No Worktree

If worktrees aren't available (not a git repo, or the user declines):
1. Create the rewrite in new files with a `.rewrite.` suffix
2. Present the diff between old and new
3. Let the user decide when to swap them
