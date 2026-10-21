# flight505-harness — Composable Harness Engineering for Claude Code

**Author:** Jesper Vang (@flight505)
**Date:** 2026-03-30
**Status:** Plan — ready for implementation

---

## 1. Vision

Build a **second marketplace** of composable, headless Claude Code plugins that implement the three tiers of harness engineering:

1. **Single-agent loops** — fixed-budget optimization (autoresearch pattern)
2. **Multi-agent coordination** — parallel feature implementation (SDK Bridge pattern)
3. **Meta-harnesses** — a conductor that composes tier 1 + tier 2 plugins into pipelines

Plus a **lightweight Next.js dashboard** that reads state files and visualizes everything.

### What this is NOT

- Not a rebuild of Paperclip (no PostgreSQL, no org charts, no separate server)
- Not a refactor of flight505-plugins (standalone plugins continue unchanged)
- Not a general agent framework (purpose-built for harness workflows)

### Design Principles

- **Headless first** — no AskUserQuestion, no interactive wizards. Config in, state out.
- **Self-contained** — installing flight505-harness gives you everything. No cross-marketplace dependencies. Users never need to also install plugins from flight505-plugins to make the harness work.
- **Shared state contract** — every plugin writes the same JSON envelope to `.claude/harness/`
- **Single-session orchestration** — the conductor runs as team lead in one Claude Code session
- **Resume from state** — every phase writes checkpoints; sessions can crash and restart
- **Claude Max native** — designed for flat-rate subscriptions, no per-token budgeting

### Self-Containment Rule

Each harness plugin **absorbs** all capabilities it needs from its standalone counterpart. No thin wrappers that delegate to external plugins.

| Harness Plugin | Absorbs From | What Gets Absorbed |
|---|---|---|
| **harness-optimize** | autoresearch plugin | Hardware detection, SSH target support, RunPod provisioning, advisor skill, experiment loop agent, all hook logic |
| **harness-build** | SDK Bridge plugin | Implementer/reviewer/code-reviewer agents, all hooks (validate-task, check-idle, validate-task-name), TDD enforcement |
| **harness-research** | ai-frontier plugin | arXiv/Semantic Scholar/HF Papers search agents, Perplexity integration, MCP server configs |
| **harness-triage** | (new — no predecessor) | Everything built from scratch |
| **conductor** | (new — no predecessor) | Workflow parser, phase sequencing, resume logic |

**What remains external (not plugins — these are project repos):**
- `autoresearch-blackwell` — Python training code for NVIDIA GPUs. harness-optimize links to it, can clone it during setup, runs experiments against it.
- `autoresearch-mlx` — Python training code for Apple Silicon. Same relationship.
- Any user project being built/optimized/triaged.

These are experiment targets, not Claude Code plugins. harness-optimize knows how to find, clone, and configure them.

### Relationship to Standalone Plugins

The standalone plugins in flight505-plugins are **not deprecated**. They serve a different user journey (interactive, exploratory, with setup wizards). The harness versions are independent forks that share DNA but diverge in interface:

| Standalone (flight505-plugins) | Harness (flight505-harness) |
|---|---|
| `/autoresearch:run` — asks about hardware, SSH, etc. | harness-optimize — reads config from workflow.yaml, includes hardware/SSH/RunPod support built-in |
| `/sdk-bridge:start` — 6-checkpoint wizard | harness-build — tasks + config in, commits + state out |
| `/ai-frontier:literature-reviewer` — interactive research session | harness-research — query + context in, structured findings out |

Both marketplaces can be installed simultaneously. They don't conflict. But you never need flight505-plugins to use flight505-harness.

---

## 2. Naming

| Item | Name | Rationale |
|------|------|-----------|
| **Marketplace** | `flight505-harness` | Sibling to `flight505-plugins`. Clear purpose. |
| **Repo** | `github.com/flight505/flight505-harness` | Matches marketplace name |
| **Conductor plugin** | `conductor` | The central orchestrator. Command: `/conductor:run` |
| **Build plugin** | `harness-build` | Headless multi-agent builder (from SDK Bridge) |
| **Optimize plugin** | `harness-optimize` | Headless keep/revert loop (from autoresearch) |
| **Research plugin** | `harness-research` | Headless literature search (from ai-frontier) |
| **Triage plugin** | `harness-triage` | Issue diagnosis + auto-fix (new) |
| **Dashboard** | `harness-dashboard` | Next.js app, reads state files |

Plugin install example: `/plugin install conductor@flight505-harness`

---

## 3. Architecture

```
flight505-harness/                    # marketplace repo (git submodules)
├── .claude-plugin/marketplace.json
├── conductor/                        # orchestrator plugin
├── harness-build/                    # parallel feature builder
├── harness-optimize/                 # keep/revert optimization loop
├── harness-research/                 # literature search + synthesis
├── harness-triage/                   # issue diagnosis + auto-fix
├── harness-dashboard/                # Next.js monitoring app
└── schema/                           # shared JSON schemas
    ├── state-v1.schema.json
    └── workflow-v1.schema.json
```

### How orchestration works

The conductor reads a `workflow.yaml` and runs **phases sequentially**. Within each phase, it uses the appropriate execution model:

```
/conductor:run workflow.yaml
  │
  ├─ Phase 1 (type: agent-teams) ──→ Spawns N implementer teammates
  │   └─ Teammates claim tasks, build in parallel, commit
  │   └─ TaskCompleted hooks gate quality
  │   └─ All tasks done → phase complete
  │
  ├─ Phase 2 (type: subagent) ──→ Spawns reviewer subagent
  │   └─ Reviews full branch diff
  │   └─ Returns verdict
  │
  ├─ Phase 3 (type: loop) ──→ Conductor runs optimization inline
  │   └─ Edit → run → measure → keep/revert → repeat
  │   └─ Max experiments or convergence → phase complete
  │
  └─ Phase 4 (type: subagent) ──→ Spawns research subagent
      └─ Condition: only if phase 3 improved > threshold
      └─ Searches literature, returns findings
```

**Key constraint:** Agent Teams cannot nest. The conductor IS the team lead during `agent-teams` phases. Only one `agent-teams` phase can run at a time. Other phase types (loop, subagent, inline) run sequentially after.

### State flow

```
workflow.yaml                          # input: what to do
  ↓
.claude/harness/                       # runtime state (shared contract)
  ├── conductor-{workflow_id}.json     # conductor's own state
  ├── build-{run_id}.json             # harness-build phase state
  ├── optimize-{run_id}.json          # harness-optimize phase state
  ├── research-{run_id}.json          # harness-research phase state
  └── triage-{run_id}.json            # harness-triage phase state
  ↓
harness-dashboard                      # reads state files, renders UI
```

---

## 4. Shared State Contract

Every harness plugin writes JSON files to `.claude/harness/` following this schema:

```json
{
  "schema": "harness/v1",
  "workflow_id": "build-and-optimize-mar30",
  "phase_id": "optimize",
  "plugin": "harness-optimize",
  "run_id": "opt-001",

  "status": "running",
  "started_at": "2026-03-30T01:00:00Z",
  "updated_at": "2026-03-30T01:47:00Z",
  "elapsed_seconds": 2820,

  "progress": {
    "current": 12,
    "total": 20,
    "unit": "experiments"
  },

  "metric": {
    "name": "p99_latency_ms",
    "direction": "lower",
    "baseline": 142,
    "current": 98,
    "best": 89,
    "history": [
      { "experiment": 1, "value": 142, "status": "baseline" },
      { "experiment": 2, "value": 135, "status": "kept", "description": "reduced pool size" },
      { "experiment": 3, "value": 148, "status": "reverted", "description": "async batching" }
    ]
  },

  "output": {},

  "error": null,

  "config": {}
}
```

### Status values

| Status | Meaning |
|--------|---------|
| `pending` | Phase defined but not yet started |
| `running` | Phase actively executing |
| `completed` | Phase finished successfully |
| `failed` | Phase encountered a fatal error |
| `skipped` | Phase skipped (condition not met) |
| `cancelled` | Phase cancelled by user or conductor |

### Plugin-specific output shapes

**harness-build output:**
```json
{
  "branch": "feat/new-api",
  "stories_completed": 5,
  "stories_total": 5,
  "commits": ["abc123", "def456"],
  "files_changed": ["src/api/handler.ts", "src/api/routes.ts"],
  "review_verdict": "approve",
  "code_review_verdict": "approve"
}
```

**harness-optimize output:**
```json
{
  "best_commit": "abc123",
  "best_description": "Reduced connection pool size, added response caching",
  "baseline_value": 142,
  "best_value": 89,
  "improvement_pct": 37.3,
  "experiments_run": 20,
  "experiments_kept": 7
}
```

**harness-research output:**
```json
{
  "query": "Why did reducing connection pool size improve p99 latency?",
  "findings": ["Connection pool contention causes tail latency spikes..."],
  "papers": [{ "title": "...", "url": "...", "relevance": "high" }],
  "recommendations": ["Consider adaptive pool sizing..."]
}
```

**harness-triage output:**
```json
{
  "issue_url": "https://github.com/...",
  "diagnosis": "Missing null check in user lookup causes 500 on deleted accounts",
  "fix_branch": "fix/null-check-user-lookup",
  "pr_url": "https://github.com/.../pull/42",
  "tests_added": 2,
  "tests_passing": true
}
```

---

## 5. Workflow Format

```yaml
# .claude/harness/workflow.yaml
name: build-and-optimize
description: "Build user management API, then optimize the hot path"

# Global config inherited by all phases
defaults:
  quality:
    test: "npm test"
    build: "npm run build"
    typecheck: "tsc --noEmit"

phases:
  - id: build
    plugin: harness-build
    type: agent-teams
    config:
      branch: "feat/user-api"
      max_teammates: 3
      code_review: true
      # Tasks can be inline or loaded from a file
      tasks_from: "tasks/prd-user-api.md"
      # OR inline tasks:
      # tasks:
      #   - id: "US-001"
      #     title: "Set up project structure"
      #     description: "As a developer, I want..."
      #     criteria:
      #       - "package.json has express dependency"
      #       - "src/ directory structure exists"

  - id: review
    plugin: harness-build
    type: subagent
    agent: reviewer
    depends_on: [build]

  - id: optimize
    plugin: harness-optimize
    type: loop
    depends_on: [review]
    config:
      artifact: "src/api/handler.ts"
      metric: "p99_latency_ms"
      direction: lower
      run_command: "npm run benchmark"
      time_budget: "3m"
      max_experiments: 20

  - id: research
    plugin: harness-research
    type: subagent
    depends_on: [optimize]
    condition: "phases.optimize.output.improvement_pct > 10"
    config:
      query: "Why did {phases.optimize.output.best_description} improve latency?"
```

### Example: Standalone autoresearch workflow

A single-phase workflow that targets autoresearch-blackwell — equivalent to running `/autoresearch:run` but headless:

```yaml
# .claude/harness/workflow.yaml
name: autoresearch-overnight
description: "Overnight autoresearch run on RTX 5070 Ti"

phases:
  - id: optimize
    plugin: harness-optimize
    type: loop
    config:
      artifact: "train.py"
      metric: "val_bpb"
      direction: lower
      run_command: "uv run train.py"
      time_budget: "5m"
      max_experiments: 100
      cwd: "~/Projects/Dev_projects/Tools/autoresearch-blackwell"
```

This demonstrates that harness-optimize subsumes the autoresearch plugin's core loop. The standalone plugin adds interactive value (hardware detection, SSH, advisor); the harness version adds composability.

### Phase types

| Type | Execution Model | When to Use |
|------|----------------|-------------|
| `agent-teams` | Conductor spawns N teammates, waits for all tasks | Parallel work: multiple stories, concurrent edits |
| `loop` | Conductor runs keep/revert loop inline (no teammates) | Optimization: edit → measure → keep/revert |
| `subagent` | Conductor spawns one subagent, waits for result | Review, research, analysis — bounded single-agent work |
| `inline` | Conductor executes directly (no delegation) | Simple tasks: git operations, file transforms, API calls |

### Conditions and references

Phases can reference output from previous phases using `phases.<id>.output.<field>`:

```yaml
condition: "phases.optimize.output.improvement_pct > 10"
```

String interpolation in config values:

```yaml
query: "Why did {phases.optimize.output.best_description} work?"
```

### Resume semantics

When the conductor starts and finds existing state files:

1. Read `.claude/harness/conductor-{workflow_id}.json`
2. For each phase:
   - `completed` or `skipped` → skip
   - `failed` → ask conductor's caller whether to retry or abort
   - `running` (stale) → treat as failed (session died mid-phase)
   - `pending` → execute normally
3. Resume from first non-completed phase

---

## 6. Plugin Specifications

### 6.1 conductor

The orchestrator. Reads workflow.yaml, sequences phases, manages Agent Teams.

```
conductor/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── commands/
│   └── run.md                    # /conductor:run [workflow.yaml]
├── hooks/
│   ├── hooks.json
│   └── inject-status.sh          # SessionStart: inject workflow progress
├── skills/
│   └── compose/                  # Helps build workflow.yaml interactively
│       └── SKILL.md
└── schema/
    └── workflow-v1.schema.json
```

**Command: `/conductor:run`**
- Input: path to workflow.yaml (default: `.claude/harness/workflow.yaml`)
- Behavior: validates workflow → checks for resume state → executes phases sequentially
- For `agent-teams` phases: creates tasks via TaskCreate, spawns teammates, monitors
- For `loop` phases: runs the optimization loop inline using harness-optimize's agent
- For `subagent` phases: spawns the appropriate agent from the target plugin
- Writes conductor state to `.claude/harness/conductor-{workflow_id}.json`

**Skill: `/conductor:compose`**
- Interactive workflow builder for when a human wants to create a workflow.yaml
- This is the ONE place user interaction happens — the conductor command itself is headless
- Asks: what plugins to compose, in what order, with what config

**Agents: none** — the conductor IS the team lead; it doesn't delegate itself.

### 6.2 harness-build

Headless parallel feature builder. Forked from SDK Bridge, stripped of wizard UX.

```
harness-build/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── agents/
│   ├── implementer.md            # Teammate: claim tasks, TDD, commit
│   ├── reviewer.md               # Subagent: spec compliance review
│   └── code-reviewer.md          # Subagent: code quality review
├── hooks/
│   ├── hooks.json
│   ├── validate-task-name.sh     # TaskCreated: enforce naming
│   ├── validate-task.sh          # TaskCompleted: test/build/typecheck gate
│   └── check-idle.sh             # TeammateIdle: keep working
└── schema/
    └── tasks-v1.schema.json      # Task input format
```

**No commands or skills.** Harness-build is purely agent-driven. The conductor creates tasks and spawns implementer teammates. The reviewer and code-reviewer are spawned as subagents by the conductor after all tasks complete.

**Differences from standalone SDK Bridge:**
- No `/start` command (no wizard)
- No prd-generator skill (planning happens upstream or in conductor:compose)
- No prd-converter skill (tasks come pre-structured from workflow.yaml or a tasks file)
- No AskUserQuestion calls anywhere
- No resume logic (conductor handles resume)
- No progress.jsonl (state contract replaces it)
- Agents read task descriptions from TaskList, not from prd.json

**What stays the same:**
- implementer.md TDD discipline and quality checks
- reviewer.md two-phase review (spec compliance + validation)
- code-reviewer.md code quality review
- TaskCompleted validation hook
- TeammateIdle prevention hook

### 6.3 harness-optimize

Headless keep/revert optimization loop. Absorbs ALL capabilities from the standalone autoresearch plugin — hardware detection, SSH remote execution, RunPod provisioning, advisor analysis — plus generalizes beyond ML training to any artifact + metric.

```
harness-optimize/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── agents/
│   ├── optimizer.md              # The keep/revert loop agent (local + remote via SSH)
│   └── advisor.md                # Analyzes projects for optimization opportunities
├── hooks/
│   ├── hooks.json
│   ├── validate-experiment.sh    # Verifies metric parsing after each run
│   └── inject-targets.sh         # SessionStart: injects configured hardware targets
├── skills/
│   └── setup/                    # Hardware target configuration
│       └── SKILL.md              # Detects hardware, configures SSH, RunPod guidance
├── scripts/
│   ├── detect-hardware.sh        # Apple Silicon / NVIDIA / CPU detection
│   ├── test-ssh.sh               # SSH connectivity test for remote targets
│   └── clone-target.sh           # Clone autoresearch-blackwell or autoresearch-mlx
└── schema/
    └── optimize-config.schema.json
```

**Agent: optimizer**
- Receives config: artifact, metric, direction, run_command, time_budget, max_experiments, target (local/server)
- For local targets: runs directly on the machine
- For server targets: executes via SSH (reads `ssh_host`, `path` from config)
- Runs the loop: read artifact → propose change → commit → run → parse metric → keep or revert
- Writes state to `.claude/harness/optimize-{run_id}.json` after each experiment
- Stops when: max_experiments reached, or convergence (N experiments with no improvement)

**Agent: advisor**
- Analyzes any project and suggests optimization opportunities (absorbed from autoresearch plugin)
- Identifies: mutable artifact, scalar metric, run command, time budget
- References configured hardware targets
- Outputs structured suggestions, not conversational advice

**Skill: `/harness-optimize:setup`**
- Interactive hardware target configuration (the ONE interactive entry point)
- Detects local hardware (Apple Silicon model, NVIDIA GPU, CPU fallback)
- Configures SSH targets for remote servers (tests connectivity)
- Provides RunPod provisioning guidance (GPU selection, cost estimation)
- Writes config to `${CLAUDE_PLUGIN_DATA}/config.json`
- Links to and can clone experiment target repos:
  - [autoresearch-blackwell](https://github.com/flight505/autoresearch-blackwell) — NVIDIA GPUs (Turing through Blackwell)
  - [autoresearch-mlx](https://github.com/trevin-creator/autoresearch-mlx) — Apple Silicon (MLX)
  - [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — H100 (upstream, Flash Attention 3)

**Workflow config with remote target:**
```yaml
- id: optimize-model
  plugin: harness-optimize
  type: loop
  config:
    target: server                                    # or "local" or "runpod"
    ssh_host: "jesper@192.168.1.100"                  # for server target
    cwd: "/home/jesper/autoresearch-blackwell"        # remote working directory
    artifact: "train.py"
    metric: "val_bpb"
    direction: lower
    run_command: "uv run train.py"
    time_budget: "5m"
    max_experiments: 100
```

**What's absorbed from the standalone autoresearch plugin:**
- Hardware detection and target configuration (setup skill)
- SSH remote execution support (optimizer agent)
- RunPod provisioning guidance (setup skill)
- Project analysis for optimization opportunities (advisor agent)
- SessionStart hardware target injection (hook)

**What's new vs the standalone plugin:**
- Generalized: any artifact + metric, not just train.py + val_bpb
- State contract output (JSON to `.claude/harness/`), not TSV
- No `/run`, `/status` commands (headless — conductor or direct agent spawn)
- Composable: can be a phase in a larger conductor workflow
- Experiment target repos linked and cloneable, not bundled

### 6.4 harness-research

Headless literature search and synthesis. Absorbs search and analysis capabilities from ai-frontier — arXiv, Semantic Scholar, HF Papers, Perplexity integration. Self-contained.

```
harness-research/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── agents/
│   ├── searcher.md               # Searches arXiv, Semantic Scholar, HF Papers, Perplexity
│   ├── synthesizer.md            # Synthesizes findings into structured output
│   └── method-analyst.md         # Compares methods/architectures (from ai-frontier)
└── .mcp.json                     # Perplexity MCP server config (bundled, not external)
```

**What's absorbed from the standalone ai-frontier plugin:**
- arXiv search via API
- Semantic Scholar search (citation counts, TLDRs, influence scores)
- Hugging Face Papers search (community-curated, trending)
- Perplexity web-grounded search (current SOTA, what practitioners actually use)
- Method comparison and tradeoff analysis
- MCP server configurations for external search APIs

**What's different:**
- No interactive skills (literature-reviewer, implementation-guide, etc.) — agents accept structured input
- Output follows state contract (JSON with findings, papers, recommendations)
- Can receive context from previous phases (e.g., "why did this optimization work?")
- No architecture-evaluator agent (that's a code quality concern for harness-build's reviewer)

### 6.5 harness-triage (new)

Issue diagnosis and auto-fix agent. No standalone equivalent.

```
harness-triage/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── agents/
│   ├── diagnostician.md          # Reads issue/error, searches codebase, identifies root cause
│   ├── fixer.md                  # Writes fix with tests
│   └── verifier.md               # Runs tests, verifies fix addresses the issue
└── hooks/
    ├── hooks.json
    └── validate-fix.sh           # TaskCompleted: test suite must pass
```

**Workflow:**
1. Diagnostician reads issue URL or error log → searches codebase → identifies root cause
2. Fixer writes minimal fix + regression test
3. Verifier runs full test suite, checks fix addresses the original issue
4. Output: diagnosis, fix branch, PR URL (or escalation reason if unfixable)

**Trigger patterns:**
- Manual: conductor runs a triage workflow
- Scheduled: `/loop` or cron checks for new issues labeled `auto-fix`
- Future: GitHub webhook → RemoteTrigger → conductor

---

## 7. Dashboard Specification

### harness-dashboard

A read-only Next.js app that monitors harness state files. No orchestration logic.

```
harness-dashboard/
├── app/
│   ├── layout.tsx                # Dark mode, Geist fonts, shadcn
│   ├── page.tsx                  # Workflow pipeline view
│   └── api/
│       └── state/route.ts        # Reads .claude/harness/*.json
├── components/
│   ├── pipeline.tsx              # Phase cards in pipeline layout
│   ├── metric-chart.tsx          # Line chart for optimization metrics
│   ├── story-progress.tsx        # Progress bar for build phases
│   ├── experiment-table.tsx      # Table of optimization experiments
│   └── agent-output.tsx          # AI Elements MessageResponse wrapper
├── lib/
│   └── state.ts                  # File watcher + state aggregation
├── package.json
└── next.config.ts
```

**Stack:**
- Next.js 16 (App Router)
- shadcn/ui (Card, Table, Badge, Tabs, Progress)
- AI Elements (MessageResponse for agent output rendering)
- Recharts (metric charts)
- Geist Sans/Mono, dark mode default
- chokidar (file watching for local dev)

**Views:**

1. **Pipeline view** (main page)
   - Horizontal pipeline of phase Cards
   - Each card shows: phase name, plugin, status Badge, progress, elapsed time
   - Click to expand: phase details, agent output, metrics

2. **Optimize view** (expanded optimize phase)
   - Line chart: metric value over experiments
   - Table: experiment ID, description, metric value, status (kept/reverted)
   - Best result highlighted

3. **Build view** (expanded build phase)
   - Progress bar: stories completed / total
   - Story list with status badges
   - Review verdict display

4. **Output view** (any phase)
   - Agent output rendered with `<MessageResponse>` from AI Elements
   - Structured JSON output in collapsible panels

**Data flow:**
- Dashboard reads `.claude/harness/*.json` via API route
- API route uses chokidar to watch directory for changes
- SSE or polling pushes updates to client
- No database, no external dependencies

**V1 scope:** local dev server only (`pnpm dev`). Future: deploy to Vercel, read from git repo.

---

## 8. Build Phases

### Phase 0: Foundation (1 day)

- [ ] Create `flight505-harness` repo on GitHub
- [ ] Set up marketplace structure (marketplace.json, submodule scaffolding)
- [ ] Write `schema/state-v1.schema.json` (the shared state contract)
- [ ] Write `schema/workflow-v1.schema.json` (workflow format)
- [ ] Write CLAUDE.md for the marketplace
- [ ] Set up webhook chain (same pattern as flight505-plugins)

### Phase 1: harness-optimize (4-5 days)

**Why first:** Tightest feedback loop, highest standalone value. Proves the state contract works. Can be tested without the conductor (just spawn the optimizer agent directly).

- [ ] Scaffold plugin structure
- [ ] Write optimizer.md agent (the keep/revert loop — local + SSH remote)
- [ ] Write advisor.md agent (project analysis for optimization opportunities)
- [ ] Write setup skill (hardware detection, SSH config, RunPod guidance, repo cloning)
- [ ] Port hardware detection scripts from autoresearch plugin (detect-hardware.sh, test-ssh.sh)
- [ ] Write clone-target.sh (clones autoresearch-blackwell or autoresearch-mlx based on hardware)
- [ ] Implement state contract writing (JSON after each experiment)
- [ ] Write validate-experiment.sh hook
- [ ] Write inject-targets.sh SessionStart hook
- [ ] Test standalone local: spawn optimizer on autoresearch-blackwell
- [ ] Test standalone remote: spawn optimizer via SSH on NVIDIA server
- [ ] Test state output: verify JSON matches schema

### Phase 2: conductor (4-5 days)

**Why second:** Needs at least one harness plugin to orchestrate. harness-optimize is the simplest target.

- [ ] Scaffold plugin structure
- [ ] Write `/conductor:run` command
- [ ] Implement workflow.yaml parser + validator
- [ ] Implement phase sequencing (pending → running → completed)
- [ ] Implement `loop` phase type (delegates to harness-optimize's optimizer agent)
- [ ] Implement `subagent` phase type
- [ ] Implement `inline` phase type
- [ ] Implement resume logic (read existing state files)
- [ ] Write inject-status.sh SessionStart hook
- [ ] Write `/conductor:compose` skill (interactive workflow builder)
- [ ] Test: conductor runs a 2-phase workflow (optimize → inline report)

### Phase 3: harness-build (5-6 days)

**Why third:** Largest plugin, needs conductor's `agent-teams` phase type.

- [ ] Fork SDK Bridge agents (implementer, reviewer, code-reviewer)
- [ ] Strip all AskUserQuestion calls and interactive flows
- [ ] Adapt agents to read config from task descriptions (not prd.json)
- [ ] Write state contract output for build phases
- [ ] Add `agent-teams` phase type to conductor
- [ ] Fork and adapt hooks (validate-task, check-idle, validate-task-name)
- [ ] Test: conductor runs build → review pipeline
- [ ] Test: full pipeline — build → review → optimize

### Phase 4: harness-dashboard (3-4 days)

- [ ] Scaffold Next.js 16 app with shadcn/ui dark theme
- [ ] Implement state file reader (API route + chokidar watcher)
- [ ] Build pipeline view (phase Cards)
- [ ] Build optimize view (metric chart + experiment table)
- [ ] Build build view (story progress + review verdict)
- [ ] Add AI Elements MessageResponse for agent output
- [ ] Test against real state files from Phase 1-3 runs

### Phase 5: harness-research (2-3 days)

- [ ] Fork ai-frontier agents into headless versions
- [ ] Adapt to accept structured input (query + context from previous phases)
- [ ] Write state contract output
- [ ] Add to conductor (subagent phase type already exists)
- [ ] Test: optimize → research pipeline (uses optimization results as context)

### Phase 6: harness-triage (3-4 days)

- [ ] Design diagnostician → fixer → verifier agent chain
- [ ] Implement issue reading (GitHub API via gh CLI)
- [ ] Implement codebase search for root cause
- [ ] Implement fix generation with regression tests
- [ ] Implement verification (test suite + issue-specific checks)
- [ ] Write state contract output
- [ ] Test: manually trigger on a known issue

### Phase 7: Integration & Polish (2-3 days)

- [ ] End-to-end test: build → review → optimize → research pipeline
- [ ] Dashboard shows all phases correctly
- [ ] Resume test: kill session mid-pipeline, restart, verify resume
- [ ] Write README.md for the marketplace
- [ ] Write getting-started guide
- [ ] Validate all plugins against marketplace schema

---

## 9. Relationship to Standalone Plugins & External Repos

### flight505-harness is self-contained

Installing `flight505-harness` gives you a complete system. You do NOT need to also install `flight505-plugins`. The harness plugins absorb all capabilities from their standalone counterparts.

**Users can install both marketplaces simultaneously** — they don't conflict. But they're independent products:

| | Standalone (flight505-plugins) | Harness (flight505-harness) |
|---|---|---|
| **User** | Human developer at keyboard | Conductor agent or scheduled trigger |
| **Interface** | Interactive wizard, AskUserQuestion | JSON config, no interaction (except setup skills) |
| **Install** | `/plugin install sdk-bridge@flight505-plugins` | `/plugin install harness-build@flight505-harness` |
| **State** | Plugin-specific (prd.json, results.tsv) | Shared contract (.claude/harness/) |
| **Resume** | Plugin-specific logic | Conductor handles all resume |
| **Dashboard** | None (terminal output) | harness-dashboard reads state files |

### External repos (not plugins)

These are Python project repos that harness-optimize can target. They are cloned into the user's workspace, not installed as plugins:

| Repo | Hardware | Relationship |
|------|----------|-------------|
| [flight505/autoresearch-blackwell](https://github.com/flight505/autoresearch-blackwell) | NVIDIA RTX 20xx–50xx | harness-optimize's setup skill can clone this; optimizer agent runs experiments against it |
| [trevin-creator/autoresearch-mlx](https://github.com/trevin-creator/autoresearch-mlx) | Apple Silicon (M3–M5) | Same — clone target, not a dependency |
| [karpathy/autoresearch](https://github.com/karpathy/autoresearch) | H100 (datacenter) | Upstream reference; harness-optimize links to it for datacenter users |

harness-optimize doesn't require any of these repos to function. They're pre-built experiment targets for ML training. For non-ML optimization (API latency, build speed, etc.), no external repo is needed — the user's own project is the target.

---

## 10. Open Questions

1. **Task format for harness-build** — should tasks come from a markdown PRD (parsed by conductor), a JSON file, or inline in workflow.yaml? Starting with both `tasks_from` (file path) and inline `tasks` seems reasonable.

2. **Parallel phases** — the current design is strictly sequential phases. Some workflows could benefit from parallel independent phases (e.g., optimize frontend AND optimize backend simultaneously). This requires two separate loop agents, which is possible within Agent Teams. Defer to v2.

3. **Condition language** — `phases.optimize.output.improvement_pct > 10` is simple but fragile. Consider using jq expressions or a tiny expression evaluator. Start simple, grow if needed.

4. **Dashboard deployment** — V1 is local dev server. For production: deploy to Vercel, authenticate with GitHub, read state files from repo. Or: use Vercel Blob to store state files and have plugins write there.

5. **Notification** — when a long-running pipeline completes, how does the user find out? Options: desktop notification (Claude Code's Notification hook), Slack message (via Chat SDK), email, or just dashboard polling. Start with Notification hook.

6. **RunPod integration depth** — harness-optimize's setup skill provides RunPod guidance (GPU selection, cost, SSH config). Should it also automate provisioning (create/destroy pods via RunPod API)? Defer to v2 — start with manual provisioning + SSH config.

---

## 11. Success Criteria

The platform works when you can:

1. Write a `workflow.yaml` that chains build → optimize → research
2. Run `/conductor:run` and walk away
3. Come back to a dashboard showing all phases completed with metrics
4. Resume a failed pipeline by re-running `/conductor:run`
5. Run `/conductor:run` on a single-phase optimize workflow as a simpler autoresearch

If those five things work, the three tiers of harness engineering are covered and the system is useful for real work.

---

**Next step:** Create the repo, define the state contract schema, and build harness-optimize.
