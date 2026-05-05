---
name: compose
description: "Interactive workflow builder — helps create workflow.yaml files for the harness orchestrator. The ONE interactive entry point. Use when user wants to build a harness workflow, create a pipeline, or compose subsystems together."
user-invocable: true
---

# Harness: Compose Workflow

Help the user build a `workflow.yaml` for the orchestrator to execute. This is the interactive counterpart to the headless `/harness:run`.

## Step 1: Understand the goal

Ask the user what they want to accomplish. Common patterns:

- **Build + Review:** Implement features in parallel, then review
- **Build + Optimize:** Build features, then optimize the hot path
- **Optimize only:** Run a keep/revert optimization loop on an artifact
- **Research:** Search literature for a specific question
- **Triage:** Diagnose and fix an issue
- **Full pipeline:** Build → Review → Optimize → Research

## Step 2: Pick subsystems

Every phase has `plugin: harness`, plus a `type:` and (for `subagent` phases) an `agent:` selecting which subsystem handles the work:

| Subsystem | Phase types | Agents | Purpose |
|---|---|---|---|
| Build | `agent-teams`, `subagent` | `lead`, `implementer`, `reviewer`, `code-reviewer` | Parallel feature building with TDD + review |
| Optimize | `loop` | `optimizer`, `advisor` | Keep/revert optimization on any artifact + metric |
| Research | `subagent` | `searcher`, `synthesizer`, `method-analyst`, `implementation-guide`, `architecture-evaluator` | Literature search + synthesis |
| Triage | `subagent` | `diagnostician`, `fixer`, `verifier` | Issue diagnosis + auto-fix |

Also check hardware targets for optimization phases:
```bash
cat "${HOME}/.harness/config.json" 2>/dev/null || echo "NO_CONFIG"
```

## Step 3: Build phases interactively

For each phase the user wants, collect the required config:

### Build phase (agent-teams)
- Branch name for the feature work
- Number of parallel teammates (1-5, default 3)
- Tasks: collect user stories inline or point to a tasks file
- Whether to run code review after

### Optimize phase (loop)
- Which file to optimize (the artifact)
- What metric to measure
- Whether lower or higher is better
- The command to run
- Time budget per experiment
- Max experiments
- Target: local or server (if server, need ssh_host and remote cwd)

### Research phase (subagent)
- The research question
- Which sources to search (arxiv, semantic-scholar, hf-papers, perplexity)
- Max papers to include

### Triage phase (subagent)
- Issue URL or error log
- Whether to create a PR for the fix

## Step 4: Wire dependencies and conditions

- Ask about phase ordering and dependencies
- Suggest conditions (e.g., "only research if optimization improved >10%")
- Add `depends_on` and `condition` fields

## Step 5: Set defaults

Ask about quality commands:
```yaml
defaults:
  quality:
    test: "npm test"        # or "pytest", "cargo test", etc.
    build: "npm run build"  # or "cargo build", etc.
    typecheck: "tsc --noEmit"  # if TypeScript
```

## Step 6: Generate and write

Assemble the full workflow.yaml and write it:

```bash
mkdir -p .harness
```

Write the file to `.harness/workflow.yaml`.

Show the user the complete workflow and explain:
- How to run: `/harness:run`
- How to monitor: check `.harness/` state files or the dashboard
- How to resume: just re-run `/harness:run` — it picks up where it left off

## Example Output

```yaml
name: build-and-optimize
description: "Build user management API, then optimize the hot path"

defaults:
  quality:
    test: "npm test"
    build: "npm run build"
    typecheck: "tsc --noEmit"

phases:
  - id: build
    plugin: harness
    type: agent-teams
    config:
      branch: "feat/user-api"
      max_teammates: 3
      code_review: true
      tasks:
        - id: "US-001"
          title: "Set up project structure"
          description: "As a developer, I want the Express project scaffolded with TypeScript"
          criteria:
            - "package.json has express dependency"
            - "src/ directory structure exists"
            - "TypeScript configured"

  - id: review
    plugin: harness
    type: subagent
    agent: reviewer
    depends_on: [build]

  - id: optimize
    plugin: harness
    type: loop
    depends_on: [review]
    config:
      artifact: "src/api/handler.ts"
      metric: "p99_latency_ms"
      direction: lower
      run_command: "npm run benchmark"
      time_budget: "2m"
      max_experiments: 20
```
