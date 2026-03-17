---
name: explaining-concepts
description: "Explains a programming or Claude Code concept using your project as context, adapted to your experience level. Use when encountering an unfamiliar term, wanting to understand an architecture pattern, learning how a Claude Code feature works, or when you'd say 'what does X mean' or 'how does Y work.'"
---

# Explaining Concepts

## Overview

Concepts stick when they connect to something you already know. This skill explains programming and Claude Code concepts using YOUR codebase as the teaching aid — not textbook examples. It adapts to your experience level, so a data scientist gets different analogies than a systems engineer.

## When to Invoke

- User types `/explain [topic]`
- User asks "what is X?" or "how does Y work?" or "what does Z mean?"
- When the user encounters an unfamiliar term in documentation or error messages
- When the user wants to understand an architecture pattern in context

## How It Works

### Step 1: Identify the Topic

Parse the user's argument or question. The topic might be:
- A specific term: "closure", "middleware", "webhook"
- A pattern: "dependency injection", "pub/sub", "CQRS"
- A Claude Code feature: "hooks", "worktrees", "skills", "MCP"
- A question: "how does the event loop work?"

If no topic is provided or it's ambiguous, ask for clarification. Don't guess.

### Step 2: Categorize and Source

| Category | Source | Approach |
|----------|--------|----------|
| **Claude Code concept** | `claude-docs-skill` (if installed) | Read official docs, explain with accuracy. Mention specific hook events, frontmatter fields, commands. |
| **Programming concept** | General knowledge + project code | Explain the concept, then find an example in the user's codebase that demonstrates it. |
| **Architecture pattern** | General knowledge + project structure | Explain the pattern, then show how it applies (or could apply) to the current project. |
| **Language-specific feature** | General knowledge + project code | Explain with examples from the project's language and codebase. |

For Claude Code concepts: check if `claude-docs-skill` is installed. If yes, read the relevant documentation to ensure accuracy. If no, explain from general knowledge but note that `claude-docs-skill` would provide more detailed, current information.

### Step 3: Adapt to User Level

Check auto-memory for the user's experience profile:
- What programming languages are they comfortable with?
- What's their role (data scientist, frontend dev, systems engineer)?
- What terms have they already learned (from teaching-terms)?

Use this to calibrate:
- **Beginner:** Use analogies to everyday concepts. Explain prerequisites.
- **Intermediate:** Use analogies to concepts they know. Skip basics.
- **Expert in adjacent field:** Map to their domain ("hooks are like database triggers", "skills are like Ansible playbooks").

If no user profile exists, default to intermediate level and adjust based on the conversation.

### Step 4: Output

## <Topic Name>

**Concept:** <1-2 paragraph explanation, adapted to user level>

**In your project:** <concrete example from the codebase or current work that demonstrates this concept. If nothing in the project directly demonstrates it, explain how it COULD apply.>

**Related:** <2-3 adjacent concepts worth exploring, as a bulleted list>

**Vocabulary:** <if introducing new terms within the explanation, note them briefly>

## Guidelines

### What Makes a Good Explanation

- **Project-grounded.** The "In your project" section is the key differentiator. Use actual file paths, function names, or patterns from the user's codebase.
- **Analogies over definitions.** "A closure is like a backpack that a function carries with it" is better than "a closure is a function bundled with its lexical scope."
- **One level of depth.** Explain the concept, not every related concept. The "Related" section lets the user go deeper on their own.
- **Honest about limits.** If you don't know how a concept applies to the project, say so rather than forcing a connection.

### What to Avoid

- **Textbook dumps.** Don't reproduce Wikipedia or documentation verbatim.
- **Condescension.** Don't say "simply" or "just" or "as you probably know."
- **Overloading.** One concept per invocation. If the topic is broad ("explain hooks"), focus on the core concept and mention subtopics in "Related."

## Edge Cases

- **Topic not provided:** Ask "What would you like me to explain?" with 2-3 suggestions based on what's been discussed in the session.
- **Topic too broad:** Narrow it. "Hooks is a big topic — would you like me to explain hook events, hook types, or how to write your first hook?"
- **Topic already well-understood:** If the user clearly knows the concept (they've used it correctly throughout the session), acknowledge that and offer a deeper dive into an advanced aspect.
- **Topic is a Claude Code feature that doesn't exist:** Correct the misconception gently. If the user confused feature names, suggest the right one.
