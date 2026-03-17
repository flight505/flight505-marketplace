# Code Coach

A Claude Code plugin that teaches you to use Claude Code effectively. It explains decisions, builds programming vocabulary, suggests better workflows, and surfaces features you didn't know existed — all on demand, using your own project as context.

## Installation

```bash
claude plugin install code-coach@flight505-marketplace
```

Restart Claude Code after installation.

## Commands

| Command | What it does | When to use it |
|---------|-------------|----------------|
| `/why` | Explains the reasoning behind the last non-trivial decision | After Claude made a choice you want to understand |
| `/teach` | Reviews the session and teaches proper programming terms | When you described something informally and want the right vocabulary |
| `/suggest` | Suggests better Claude Code workflows for your current task | When you feel like you're doing things the hard way |
| `/explain [topic]` | Explains a concept using your project as context | When you encounter an unfamiliar term or pattern |

## How It Works

**SessionStart injection:** When a session starts (or resumes/clears/compacts), Code Coach injects a lightweight command reference so you always know what's available.

**On-demand skills:** Each command invokes a dedicated skill that provides structured coaching. Skills are pure markdown — no runtime dependencies, no background processes.

## Recommended Companion

Code Coach works best when paired with [claude-docs-skill](https://github.com/flight505/claude-toolkit) installed in your project. This gives `/explain` access to complete Claude Code documentation for accurate concept lookups.

## License

MIT
