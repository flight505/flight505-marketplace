---
name: review
description: >
  Deep architectural code review — reads all files in the target area, maps dependencies,
  identifies structural issues, and ranks them by criticality. Spawns adversarial review
  agents that challenge each other's findings. Use when code quality feels off, before
  major features, or when accumulated patches may be hiding structural debt.
  Triggers: "deep review", "code review", "architecture review", "review this module",
  "what's wrong with this code", "tech debt audit", "review before shipping".
user-invocable: true
---

# Senior Engineer Review

You are a senior engineer performing a deep code review. Not a linter pass — a structural
analysis of whether the code is built correctly for what it needs to do.

## What This Is

A thorough review that reads everything, maps the system, and identifies where the
architecture is fighting itself. The kind of review a senior engineer does when they
inherit a codebase and need to know where the bodies are buried.

## Phase 1: Scope

Determine what to review:

1. **If the user specified a target** (module, directory, feature area) — use that
2. **If no target specified** — ask: "What area should I review? A module path, feature name, or 'everything'?"
3. **For "everything"** — start with entry points, trace dependencies outward

## Phase 2: Deep Read

Read systematically, not randomly. For the target area:

1. **Entry points** — find the main files (routes, handlers, components, CLI commands)
2. **Dependencies** — trace imports outward: what does this code depend on?
3. **Dependents** — trace inward: what depends on this code?
4. **Configuration** — find config files, environment variables, build settings
5. **Tests** — read existing tests to understand intended behavior
6. **Documentation** — check README, CLAUDE.md, inline docs for stated intent

Use the `code-mapper` agent for parallel file discovery:
```
Spawn the code-mapper agent to map all files, dependencies, and state flow
for [target area]. It should return a structured dependency map.
```

Take notes as you read. Track:
- State management patterns (where state lives, how it flows)
- Abstraction boundaries (what's separated, what's coupled)
- Framework usage (native APIs vs workarounds)
- Error handling patterns (consistent or ad-hoc)
- Technology choices (right tool for the job?)

## Phase 3: Analyze

For each concern found, classify it using the intervention framework:

| Level | Meaning |
|-------|---------|
| **PATCH** | Isolated bug, local fix is correct |
| **REFACTOR** | Design intent is right but organization obscures it |
| **REWRITE** | Approach is wrong — structure itself produces the problem |
| **RETHINK** | Wrong tool/framework/paradigm for the job |

Apply these REWRITE triggers as a checklist:
- [ ] Same class of bug appeared more than once in this subsystem
- [ ] Fix requires modifying >40% of a module for structural reasons
- [ ] Adding features requires fighting the existing structure
- [ ] State is implicit, duplicated, or scattered across layers
- [ ] An abstraction was built for a problem that no longer exists
- [ ] A correct solution would look nothing like the current code

## Phase 4: Framework Compliance Check

For each technology used in the codebase, check:
- **Is the code using the framework's native capabilities?** (e.g., Tauri's Rust backend vs. Node.js workarounds, SwiftUI vs. UIKit hacks, Next.js Server Components vs. client-side fetching)
- **Are there deprecated APIs or patterns?** Cross-reference against current documentation
- **Is there a better way to do this in the current framework version?**

If doc skills are available in the project (claude-docs-skill, gemini-docs-skill, etc.), use them.
If context7 MCP is available, use it to look up framework-specific documentation.

## Phase 5: Report

Present findings as a structured report:

```
## Code Review: [Target Area]

### Summary
[One paragraph: overall health assessment]

### Critical Issues (REWRITE/RETHINK)

**1. [Issue Title]** — REWRITE
- **What:** [description]
- **Where:** [file:line references]
- **Why it's structural:** [why a patch won't fix this]
- **Impact:** [what breaks or degrades because of this]
- **Recommended approach:** [one sentence]

### Important Issues (REFACTOR)

**2. [Issue Title]** — REFACTOR
...

### Minor Issues (PATCH)

**3. [Issue Title]** — PATCH
...

### Framework Compliance
| Framework | Status | Issue |
|-----------|--------|-------|
| [e.g., Tauri v2] | Using HTML workaround instead of Cocoa native | REWRITE |
| [e.g., Next.js 16] | Still using middleware.ts instead of proxy.ts | REFACTOR |

### Architecture Diagram
[Text-based dependency map of the reviewed area]

### Priority Ranking
1. [Most critical issue — fix this first]
2. [Second most critical]
3. ...
```

## Agent Team Mode (when available)

If agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), spawn an adversarial
review team instead of doing a solo review:

```
Create an agent team to review [target area]:
- code-structure: analyze dependencies, coupling, state management
- framework-compliance: check if native APIs are used correctly, find workarounds
- devil's-advocate: challenge the current architecture, propose alternatives

Have them debate their findings. The code-structure reviewer should defend
the current design when challenged. The devil's-advocate should try to
disprove that defense. Report the consensus.
```

The debate structure counters anchoring bias — a solo reviewer tends to find one issue
and stop. Adversarial reviewers find issues the solo reviewer would miss.

If agent teams are NOT available, do a solo review using the phases above.
