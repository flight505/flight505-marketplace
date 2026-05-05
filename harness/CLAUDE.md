# harness

Composable harness engineering for Claude Code — workflow orchestrator plus build, optimize, research, and triage agents. Headless, single-session, resumable.

This file replaces the five per-plugin CLAUDE.md files (conductor, harness-build, harness-optimize, harness-research, harness-triage) that existed before consolidation. Cross-cutting facts (state contract, design principles) live in the root `CLAUDE.md`.

## Commands

- `/harness:run [path]` — execute a workflow. Default path: `.harness/workflow.yaml`

## Skills

- `/harness:compose` — interactive workflow builder. The ONE interactive entry point.
- `/harness:approve <phase_id>` — approve or reject a pending `type: approval` gate. Run with no args to list pending gates.
- `/harness:plan-ready <phase_id>` — signal that a `type: ultraplan` phase's plan file is in place at `.harness/artifacts/<phase_id>/plan.md`.
- `/harness:pick-workflow <description>` — match a task description to the best default workflow, collect required values, write `.harness/workflow.yaml`, and hand off to `/harness:run`.
- `/harness:setup` — one-time interactive hardware target configuration for the optimize subsystem.
- `/harness:advisor` — scan a project and suggest autoresearch opportunities — presents findings as prose with ready-to-copy workflow.yaml snippets.

## Default Workflows

Production-ready workflow templates in `harness/workflows/defaults/`:

| Workflow | Pipeline | Use when |
|---|---|---|
| `fix-github-issue` | diagnose → ultraplan → agent-teams → review → approval → PR | Fixing a bug from a GitHub issue |
| `idea-to-pr` | ultraplan → agent-teams (3 implementers) → approval → PR | Building a feature from an idea |
| `refactor-safely` | investigate → plan → generic loop (typecheck until clean) → review → PR | Restructuring code safely |
| `smart-pr-review` | 4 parallel reviewers (security, perf, tests, docs) → synthesize → PR comment | Thorough multi-perspective PR review |

Copy a workflow to `.harness/workflow.yaml`, fill in the `REPLACE_WITH_*` placeholders, then `/harness:run`.

## Phase Types

| Type | Execution | Conductor's Role |
|------|-----------|-----------------|
| `agent-teams` | Spawns `harness:lead` which manages a native Agent Teams team | Delegates — lead becomes the team lead, conductor waits for state file |
| `loop` | Spawns optimizer agent (mode: optimize) or runs body until condition (mode: generic) | Delegates — waits for agent to complete, reads state |
| `subagent` | Spawns one agent | Delegates — waits for result |
| `inline` | Executes directly | Runs commands/scripts itself |
| `approval` | Writes pending-approval file and stops | Pauses — user runs `/harness:approve`, then resumes with `/harness:run` |
| `ultraplan` | Prints instructions for cloud-side planning, stops | Pauses — user runs `/ultraplan`, saves plan, runs `/harness:plan-ready`, then resumes |

**Key constraint:** Only one `agent-teams` phase at a time — Claude Code's native Agent Teams allows one team per session. The orchestrator enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and spawns `harness:lead` as a subagent; the lead becomes the actual team lead.

## Agents

Sixteen agents in this plugin, organized by subsystem:

| Agent | Subsystem | Purpose | Spawned By |
|-------|-----------|---------|------------|
| `lead` | build | Team lead — orchestrates an agent-teams phase | Orchestrator |
| `implementer` | build | TDD implementer, claims tasks, commits | Lead |
| `reviewer` | build | Spec compliance review (read-only, haiku) | Lead, post-build |
| `code-reviewer` | build | Code quality review (read-only, sonnet) | Lead, after spec review |
| `optimizer` | optimize | Keep/revert experiment loop | Orchestrator (loop phase) |
| `advisor` | optimize | Analyzes projects for optimization opportunities | Orchestrator (subagent) or skill |
| `searcher` | research | Searches arXiv, Semantic Scholar, HF Papers, Perplexity, web | Orchestrator (subagent) |
| `synthesizer` | research | Synthesizes findings into structured JSON + markdown output | Orchestrator (subagent) |
| `method-analyst` | research | Compares methods/tools/approaches with tradeoff analysis | Orchestrator (subagent) |
| `implementation-guide` | research | Translates research → actionable code/architecture steps | Orchestrator (subagent) |
| `architecture-evaluator` | research | Compares codebase against research SOTA, identifies gaps | Orchestrator (subagent) |
| `diagnostician` | triage | Reads issue/error, searches codebase, identifies root cause | Orchestrator (subagent) |
| `fixer` | triage | Writes minimal fix with regression test | Orchestrator (subagent) |
| `verifier` | triage | Verifies fix addresses the issue, creates PR | Orchestrator (subagent) |

## Hooks

All event handlers in `harness/hooks/hooks.json`:

| Event | Script | Purpose |
|-------|--------|---------|
| `SessionStart` | `inject-status` | Show workflow progress on session start/resume |
| `SessionStart` | `inject-targets` | Inject configured hardware targets into context |
| `Notification` | `notify-complete` | Cross-platform desktop notification on completion |
| `PostToolUse` | `validate-experiment` | Warn if metric parsing fails during optimization |
| `PostToolUse` | inline node script | Validate research agent output structure |
| `PreCompact` | `on-pre-compact.sh` | Flush optimizer state summary before compaction |
| `TaskCreated` | `on-task-created.sh` | Enforce `[XX-NNN]: Title` naming, record task |
| `TaskCompleted` | `on-task-completed.sh` | Run quality gates; block on failure; update state |
| `TaskCompleted` | `validate-fix.sh` | Run test suite during triage to verify fixes |
| `TeammateIdle` | `on-teammate-idle.sh` | Prevent idle while work remains |

Team hooks (`TaskCreated`, `TaskCompleted`, `TeammateIdle`) cannot be filtered by `matcher` or `if`; each script exits 0 cleanly when no active state file is present. `_lib.sh` provides shared helpers.

## Subsystem-specific notes

### Build

Built on Claude Code's native Agent Teams. The orchestrator spawns `harness:lead`, which enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, creates tasks via `TaskCreate`, and spawns teammates via the Agent tool. Hard constraints: one team per session, no nested teams, session resumption does not restore teammates, `skills`/`mcpServers`/`permissionMode` frontmatter on subagent definitions are ignored in teammate mode.

Build state output extends the shared schema with `team_name`, `teammates[]`, `output.tasks{}`, `output.stories_completed/total`, `output.commits[]`, `output.files_changed[]`, `output.review_verdict`, `output.code_review_verdict`.

### Optimize

Headless keep/revert loop. Any artifact + metric, local or remote via SSH. Hardware targets persist at `${CLAUDE_PLUGIN_DATA}/config.json`:

```json
{
  "version": 1,
  "targets": {
    "local":  { "enabled": bool, "path": str, "backend": "mlx"|"cuda"|"cpu", "description": str },
    "server": { "enabled": bool, "ssh_host": str, "path": str, "backend": "cuda", "gpu_type": str },
    "runpod": { "enabled": bool, "api_key": str, "gpu_type": str }
  }
}
```

Scripts in `harness/scripts/`: `detect-hardware.sh`, `test-ssh.sh <host> [path]`, `clone-target.sh <type> <dest>`, `write-config.sh`. Optimize state is updated after every experiment with progress, metric history, best result, and improvement percentage.

### Research

Domain-agnostic — works for any research question (ML, engineering, economics, medicine). Optional API key: `S2_API_KEY` for higher Semantic Scholar rate limits. Perplexity uses the MCP server (configured in Claude Code settings, not here). The synthesizer writes both JSON state and a human-readable `.harness/research-{run_id}.md` prose summary alongside.

### Triage

`diagnostician` → `fixer` → `verifier` chain. Fixer creates a fix branch with a regression test; verifier runs tests and optionally creates a PR.

## Workflow Configs

```yaml
# Build
- id: build
  plugin: harness
  type: agent-teams
  config:
    branch: "feat/user-api"
    teammates:
      - type: implementer
        count: 3
    require_plan_approval: false
    code_review: true
    tasks: [...]   # or tasks_from: <path>

# Optimize
- id: optimize
  plugin: harness
  type: loop
  config:
    artifact: "train.py"
    metric: "val_bpb"
    direction: lower
    run_command: "uv run train.py"
    time_budget: "5m"
    max_experiments: 20
    target: "local"   # or "server" / "runpod"

# Research
- id: research
  plugin: harness
  type: subagent
  agent: searcher    # or synthesizer, method-analyst, implementation-guide, architecture-evaluator
  config:
    query: "Best practices for database connection pooling"
    sources: ["arxiv", "semantic-scholar", "hf-papers", "perplexity"]
    max_results: 10

# Triage
- id: triage
  plugin: harness
  type: subagent
  agent: diagnostician   # or fixer, verifier
  config:
    issue_url: "https://github.com/owner/repo/issues/42"
    fix_branch_prefix: "fix/"
    create_pr: true
```

## Proactive behavior

When a harness-relevant signal appears in the conversation, surface the right skill or workflow proactively. Don't wait to be asked — name the option, give the exact command, let the user accept or redirect.

| Signal | Suggest |
|---|---|
| User mentions "fix bug", "fix issue #N" AND no workflow is active | `/harness:pick-workflow fix...` |
| User describes a feature to build AND no workflow is active | `/harness:pick-workflow build...` |
| User wants to optimize/tune a metric | `/harness:advisor` to analyze, then `/harness:pick-workflow optimize...` |
| User mentions "review PR", "audit PR" | `/harness:pick-workflow review PR...` |
| User asks "what workflows do I have?" | List the four defaults |
| State shows `waiting_approval` OR `.harness/pending-approval-*.json` exists | Tell user to run `/harness:approve <phase_id>` |
| `agent-teams` or `loop` phase about to run with `max_experiments > 10` or `count > 2` | Suggest launching the dashboard |
| Run finished with `output.review_verdict == "reject"` or any failure | Surface the failure and offer the fix path |
| User pastes a stacktrace AND no workflow is active | Offer triage workflow or `harness:diagnostician` directly |

**Rules:**
- Give the exact command. Don't ask "would you like me to…?"
- Don't suggest the same thing twice in a row.
- When multiple suggestions match, pick the most specific one.
- If you're already in a workflow, never suggest starting a new one — finish or cancel first.

## See also

- Root `CLAUDE.md` — design principles, state contract, marketplace rules
- `docs/research/2026-04-primitives.md` — research that shaped the agent-teams design
- `harness/commands/run.md` — full conductor execution model
