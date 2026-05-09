---
description: "Run a harness workflow — validates workflow.yaml, checks for resume state, executes phases sequentially. Handles agent-teams, loop, subagent, and inline phase types."
argument-hint: "[path/to/workflow.yaml]"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Agent", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "SendMessage"]
---

# Conductor: Run Workflow

You are the conductor — the central orchestrator for harness workflows. You read a workflow.yaml, sequence phases, delegate to harness plugins, and write state. You never ask the user questions during execution — you work headlessly from the workflow definition.

## 1. Load Workflow

```bash
WORKFLOW_PATH="${1:-.harness/workflow.yaml}"
cat "$WORKFLOW_PATH"
```

If `$ARGUMENTS` provides a path, use it. Otherwise default to `.harness/workflow.yaml`.

If the file doesn't exist, stop with: "No workflow found at `<path>`. Create one with `/harness:compose` or place a workflow.yaml at `.harness/workflow.yaml`."

## 2. Validate Workflow

Delegate validation to the conductor CLI. It checks: name format, phases array, required fields per phase type, depends_on existence + no forward refs + DAG (no cycles), known agent names, and required config keys (e.g., `artifact` for optimize-mode loops, `until` for generic-mode loops).

```bash
node "${CLAUDE_PLUGIN_ROOT}/bin/conductor.mjs" validate "$WORKFLOW_PATH"
```

The CLI exits non-zero with a JSON `{errors: [...], warnings: [...]}` report on failure. Print the report and stop. On success, surface any warnings but continue.

**Implementation reference:** [`harness/bin/conductor.mjs`](../bin/conductor.mjs) — the `validate` subcommand. Tests in [`harness/tests/conductor.test.mjs`](../tests/conductor.test.mjs).

## 2b. Launch Dashboard

Before executing any phases, start the monitoring dashboard in the background so the user can follow progress in real time.

```bash
launch-dashboard "$(pwd)/.harness"
```

This:
- Starts the Next.js dashboard on `http://localhost:3000` (or next available port)
- Points it at the current workflow's state directory
- Runs in the background — does not block phase execution
- Skips if the dashboard is already running
- Opens the browser automatically

If the dashboard fails to start (missing dependencies, port conflict), log a warning and continue — the dashboard is monitoring-only, not execution-critical.

## 3. Check for Resume State

```bash
mkdir -p .harness
if [ -f .gitignore ] && ! grep -q '^\.harness/' .gitignore; then
  echo '.harness/' >> .gitignore
fi

WORKFLOW_NAME=$(node -e "import('${CLAUDE_PLUGIN_ROOT}/bin/_lib/yaml.mjs').then(m=>console.log(m.parse(require('fs').readFileSync('$WORKFLOW_PATH','utf8')).name))")
STATE_PATH=".harness/conductor-${WORKFLOW_NAME}.json"

if [ ! -f "$STATE_PATH" ]; then
  node "${CLAUDE_PLUGIN_ROOT}/bin/conductor.mjs" init "$WORKFLOW_PATH" "$STATE_PATH"
fi
```

The CLI writes a fresh state file with all phases marked `pending` and `retry_count: 0`, then atomically renames into place. If the file already exists, the CLI is not invoked — existing state is preserved for resume.

**Resume semantics** (handled by `conductor next`, see §4): completed/skipped phases are skipped, failed phases are retried while `retry_count < 2`, stale `running` phases are treated as abandoned and retried, `waiting_approval` returns an `approval`/`plan` action so the conductor can pause for the human gate.

## 4. Execute Phases

The execution loop is CLI-driven: ask `conductor next` what to do, do it, then `conductor record` the outcome. Repeat until `done`.

```bash
while true; do
  ACTION_JSON=$(node "${CLAUDE_PLUGIN_ROOT}/bin/conductor.mjs" next "$STATE_PATH")
  ACTION=$(echo "$ACTION_JSON" | jq -r '.action')
  case "$ACTION" in
    done)     break ;;
    failed)   echo "$ACTION_JSON" | jq -r '.reason'; exit 1 ;;
    approval) echo "Pause: phase $(echo "$ACTION_JSON" | jq -r '.phase_id') waiting on /harness:approve"; exit 0 ;;
    plan)     echo "Pause: phase $(echo "$ACTION_JSON" | jq -r '.phase_id') waiting on /ultraplan + /harness:plan-ready"; exit 0 ;;
    run)      ;;  # fall through to per-type execution below
    *)        echo "unknown action: $ACTION"; exit 1 ;;
  esac
  # The per-type execution logic in §4a–§4h decides which agent to spawn for
  # the phase descriptor at .phase. After execution, record the outcome:
  #   node "${CLAUDE_PLUGIN_ROOT}/bin/conductor.mjs" record "$STATE_PATH" "$PHASE_ID" \
  #     '{"status":"completed","output":{...}}'
done
```

Process phases in order. For each phase:

### 4a. Check dependencies

If `depends_on` is set, verify all listed phases have `completed` status. If any dependency is `failed` or `skipped`, skip this phase too.

### 4b. Evaluate condition

If `condition` is set, evaluate it against completed phase outputs:
- Parse: `phases.<id>.output.<field> <op> <value>`
- Operators: `>`, `<`, `>=`, `<=`, `==`, `!=`
- If condition is false, skip the phase (set status to `skipped`)

### 4c. Resolve config interpolation

Two interpolation patterns are supported in config string values:

1. **Phase output:** `{phases.<id>.output.<field>}` — replaced with the actual value from a completed phase's output. The referenced `<id>` must be a prior completed phase.

2. **Artifact file:** `{artifact:<phase_id>/<filename>}` — replaced with the full contents of the file at `.harness/artifacts/<phase_id>/<filename>`. The referenced `<phase_id>` must be a prior completed phase. If the file does not exist, interpolation fails with an error and the phase is skipped.

**Artifact directory convention:**

Phases write artifacts to `.harness/artifacts/<phase_id>/` using conventional filenames:

| Filename | Written by | Contains |
|---|---|---|
| `plan.md` | ultraplan, planning subagents | Implementation plan |
| `investigation.md` | triage diagnostician, research searcher | Analysis findings |
| `review.md` | harness reviewer | Spec compliance verdict + evidence |
| `code-review.md` | harness code-reviewer | Code quality verdict + issues |
| `synthesis.md` | research synthesizer | Research synthesis report |
| `diagnosis.md` | triage diagnostician | Root cause analysis |
| `metrics.json` | optimizer | Metric history as structured data |

Phases create their artifact directory with `mkdir -p .harness/artifacts/<phase_id>/` before writing. The conductor does NOT create these directories — each phase is responsible for its own.

Both interpolation patterns are resolved recursively across all string values in the phase's `config` object before dispatch.

### 4d. Merge defaults

Merge `defaults` from workflow into phase config (phase config takes precedence).

### 4e. Execute by type

---

#### Phase Type: `agent-teams`

This is for parallel feature building via the build subsystem. The conductor delegates the entire team lifecycle to the `harness:lead` agent, which uses Claude Code's native Agent Teams feature for task coordination, teammate spawning, and inter-agent messaging.

**Requires:** Claude Code v2.1.32+ and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment.

1. **Generate** a unique `run_id` for the phase (e.g., `build-<workflow>-001`).

2. **Enable Agent Teams** by exporting the experimental flag for this phase:
   ```bash
   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
   ```
   If the flag was unset at conductor startup, it persists only for subsequent phases within this run.

3. **Read tasks** from `config.tasks` (inline) or `config.tasks_from` (file path). Validate that every task has `id`, `title`, `description`. If neither source is present, fail the phase.

4. **Write initial phase state** to `.harness/build-{run_id}.json`:
   ```json
   {
     "schema": "harness/v1",
     "workflow_id": "<workflow>",
     "phase_id": "<phase_id>",
     "plugin": "harness",
     "run_id": "<run_id>",
     "status": "running",
     "started_at": "<ISO 8601 now>",
     "updated_at": "<ISO 8601 now>",
     "progress": { "current": 0, "total": <task count>, "unit": "stories" },
     "teammates": [],
     "output": { "tasks": {} },
     "config": {
       "branch": "<config.branch>",
       "teammates": <config.teammates>,
       "quality": <merged defaults.quality + phase config.quality>
     }
   }
   ```

5. **Spawn the lead.** Use the `Agent` tool with `subagent_type: "harness:lead"` and pass the full phase config as a JSON payload in the prompt. Include:
   - `workflow_id`, `phase_id`, `run_id`, `state_file` (path from step 4)
   - `branch`, `teammates`, `require_plan_approval`, `approval_criteria`, `code_review`
   - `tasks` (fully resolved — inline or loaded from `tasks_from`)
   - `quality` (merged from workflow defaults and phase config)

6. **The lead runs autonomously.** It creates tasks, spawns teammates as native Agent Teams members, monitors progress, runs reviews, and writes the final output to the state file. The conductor's role is just to wait for the lead agent to return.

7. **On lead return**, read the state file and:
   - If `status == "completed"` — record the phase as completed in conductor state
   - If `status == "failed"` — record the failure and error, respect `depends_on` for subsequent phases
   - Copy `output` into the conductor state's `phases.<phase_id>.output`

**Key constraints** (from Claude Code's Agent Teams documentation):

- **One team per session.** Only one `agent-teams` phase can run at a time. If a workflow has multiple, they run sequentially.
- **No nested teams.** Teammates cannot spawn their own teams. Sub-team phases are impossible.
- **Session resumption does not restore teammates.** If the conductor session crashes mid-phase on resume, the lead must spawn fresh teammates rather than try to reattach.
- **Permissions inherit from the conductor.** All teammates start in the conductor's permission mode; the lead can change individual modes after spawn but not at spawn time.

**Why the conductor delegates to a lead agent:** the lead has its own context window, so it can maintain conversational state with teammates via `SendMessage` without consuming the conductor's context. The conductor remains free to handle other phases after this one completes.

---

#### Phase Type: `loop`

Runs a body repeatedly until a condition is met. Two modes:

**Mode: `optimize`** (default when `config.artifact` is present)

Delegates to `harness:optimizer` for keep/revert scalar-metric optimization.

1. Generate a unique `run_id`
2. Spawn the `harness:optimizer` agent with config:
   ```
   artifact, metric, direction, run_command, time_budget,
   max_experiments, convergence_window, target, ssh_host, cwd,
   workflow_id, phase_id, run_id
   ```
3. The optimizer agent runs autonomously and writes its own state to `.harness/optimize-{run_id}.json`
4. Wait for the optimizer to finish (it will set status to `completed` or `failed`)
5. Read the optimizer's final state to get output
6. Copy output to the conductor's phase record

**Mode: `generic`** (when `config.body` is present)

Runs a body action in a loop, evaluating `config.until` after each iteration.

1. Generate a unique `run_id`. Set `iteration = 0`.
2. Write initial phase state with `status: "running"` and `progress: {current: 0, total: config.max_iterations}`.
3. **Loop start:**
   a. Increment `iteration`. Update `progress.current`.
   b. Execute `config.body` according to its `type`:
      - `type: "inline"` → run `config.body.config.command` via Bash. Capture exit code as `$body.exit_code` and stdout as `$body.stdout`.
      - `type: "subagent"` → spawn the agent specified by `config.body.agent` (e.g., `harness:fixer`). Capture its output as `$body.output`.
   c. Evaluate `config.until` — an expression using the same grammar as phase `condition` fields, plus `$body.*` variables from the current iteration and `$iteration` for the loop counter.
      - If the expression evaluates to **true**: exit the loop, set phase status to `completed`.
      - If the expression evaluates to **false**: continue to the next iteration.
   d. If `iteration >= config.max_iterations`: exit the loop, set phase status to `completed` with `output.exit_reason: "max_iterations"`.
4. Write final output:
   ```json
   {
     "iterations": N,
     "exit_reason": "condition_met" | "max_iterations",
     "last_body_result": { ... }
   }
   ```

**Expression variables available in `until`:**

| Variable | Type | Description |
|---|---|---|
| `$body.exit_code` | integer | Exit code of the last inline command (0 = success) |
| `$body.stdout` | string | Stdout of the last inline command (trimmed) |
| `$body.output` | object | Output from the last subagent invocation |
| `$iteration` | integer | Current iteration number (1-based) |

**Example — test-fix loop:**
```yaml
- id: fix-loop
  plugin: harness
  type: loop
  config:
    body:
      type: inline
      config:
        command: "npm test 2>&1; echo EXIT:$?"
    until: "$body.exit_code == 0"
    max_iterations: 5
```

**Mode detection:** The conductor checks for `config.artifact` (→ optimize) or `config.body` (→ generic). If neither is present, fail the phase with an error. If both are present, prefer `optimize` (backward compatibility).

---

#### Phase Type: `ultraplan`

Delegates planning to Claude Code on the web. The user reviews the plan in a browser with inline comments, then the approved plan becomes an artifact for the next phase.

**Requirements:** Claude Code on the web account + GitHub repository. NOT available on Bedrock, Vertex, or Foundry.

**Guard clause:** Before entering this phase, check for `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY` environment variables. If any are set, fail the phase immediately with:

```
Ultraplan is not available on third-party providers (Bedrock/Vertex/Foundry).
Use a direct Anthropic plan (Pro, Max, Team, Enterprise) instead.
```

**Execution (interactive hand-off):**

1. Create the artifact directory: `mkdir -p .harness/artifacts/{phase_id}/`

2. Set the phase status to `waiting_approval` in the conductor state file (reuses the approval gate status).

3. Print the ultraplan prompt to the conversation:
   ```
   ## Ultraplan: <phase_id>

   Run the following command to start cloud-side planning:

   /ultraplan <config.prompt>

   After the plan is ready:
   1. Review it in your browser (claude.ai/code)
   2. When satisfied, choose "Approve plan and teleport back to terminal"
   3. In the teleport dialog, choose "Cancel" to save the plan to a file
   4. Copy the saved plan to: .harness/artifacts/<phase_id>/plan.md
   5. Run: /harness:plan-ready <phase_id>

   The conductor will resume from this point.
   ```

4. **Stop the conductor run** (same pattern as `type: approval`).

5. **On resume** (`/harness:run` re-invoked):
   - Check if `.harness/artifacts/{phase_id}/plan.md` exists
   - If yes: mark the phase as `completed`, set `output.plan_file` to the artifact path
   - If no: check `.harness/pending-approval-{phase_id}.json` for a manual signal from `/harness:plan-ready`
   - If neither: stop again with the same instructions

**Why interactive hand-off:** Ultraplan's browser review (inline comments, emoji reactions, outline navigation) is inherently interactive. There is no documented headless polling API for the status indicators. The conductor embraces the pause rather than fighting the design.

---

#### Phase Type: `subagent`

This is for bounded single-agent work (review, research, analysis).

1. Generate a unique `run_id`
2. Write initial phase state
3. Determine which agent to spawn:
   - If `config.agent` is set, use `<plugin>:<agent>` (e.g., `harness:reviewer`)
   - Otherwise, use the plugin's default agent
4. Spawn the agent with the phase config as input
5. Wait for agent to return
6. Write the agent's output to phase state
7. Set status to `completed`

---

#### Phase Type: `inline`

This is for simple tasks the conductor executes directly.

1. Write initial phase state
2. Execute the inline config:
   - If `config.command` is set, run it via Bash
   - If `config.script` is set, run the script
   - If `config.message` is set, output it (for reporting/logging)
3. Capture output
4. Write phase state with output
5. Set status to `completed`

---

#### Phase Type: `approval`

This is a human-in-the-loop gate. The conductor pauses and waits for a user decision before continuing.

**This phase type does not require a plugin.** Set `plugin` to any valid value (the conductor ignores it for approval phases) or use the plugin that owns the preceding work.

1. Write `.harness/pending-approval-{phase_id}.json`:
   ```json
   {
     "phase_id": "<phase_id>",
     "workflow_id": "<workflow_name>",
     "prompt": "<config.prompt>",
     "context_file": "<resolved path to context_from artifact, or null>",
     "created_at": "<ISO 8601 now>",
     "status": "pending",
     "decision": null,
     "decision_reason": null,
     "decided_at": null
   }
   ```

2. If `config.context_from` is set, resolve it to `.harness/artifacts/<context_from>` and verify the file exists. If missing, log a warning but continue.

3. Set the phase status to `waiting_approval` in the conductor state file.

4. Print an approval prompt to the conversation:
   ```
   ## Approval Required: <phase_id>

   <config.prompt>

   Context: <path to context file, or "none">

   To approve:  /harness:approve <phase_id>
   To reject:   /harness:approve <phase_id> --reject "reason"

   The conductor will stop here. Re-run /harness:run to continue after approving.
   ```

5. **Stop the conductor run.** Do NOT continue to the next phase. The conductor writes its state with `status: "running"` and the current phase marked as `waiting_approval`, then exits cleanly. This is NOT a failure — it's a designed pause point.

6. **On resume** (`/harness:run` re-invoked):
   - The conductor reads `.harness/pending-approval-{phase_id}.json`
   - If `status == "approved"`: mark the phase as `completed`, continue to the next phase
   - If `status == "rejected"`: mark the phase as `failed` with `error.message = decision_reason`, apply normal failure handling (skip dependent phases)
   - If `status == "pending"`: the conductor stops again with the same prompt — the user hasn't approved yet

**Why file-based, not deferred tool use:** The `permissionDecision: "defer"` primitive requires `-p` (headless) mode, but the conductor runs interactively. A file-based gate leverages the conductor's existing resume protocol without requiring a mode switch. This can be upgraded to deferred tool use in the future if the conductor moves to headless execution.

---

### 4f. Update conductor state

After each phase completes (or fails/skips):
1. Update `.harness/conductor-{workflow_name}.json`:
   - Increment `progress.current`
   - Add phase result to `output.phases.<phase_id>`
   - Update `updated_at` and `elapsed_seconds`
2. If phase failed and is not the last phase, log the failure and continue to next phase only if it doesn't depend on the failed phase

## 5. Finalize

When the loop in §4 exits with `action: done`, the conductor state file already reflects the final per-phase status (the CLI writes it atomically on every `record`). Just summarize for the user:

1. Read the final state: `cat "$STATE_PATH" | jq '.phases'`
2. Output a final summary to the conversation:
   ```
   ## Workflow Complete: <name>
   - Phases: N completed, N skipped, N failed
   - Duration: Xm Ys
   - Results: <brief summary of key outputs>
   ```

## Error Handling

- **Phase fails:** Log error in phase state, set status to `failed`. Continue to next phase unless it depends on the failed phase.
- **Agent crashes:** If an agent doesn't return, check its state file. If stale `running`, treat as failed.
- **Session dies:** On resume, the conductor reads existing state and picks up where it left off (step 3).
- **Invalid workflow:** Report all validation errors upfront, don't start execution.

## Constraints

- **Never ask questions** — work from the workflow definition
- **Always write state** — the dashboard and future resumes depend on fresh state files
- **One agent-teams at a time** — Claude Code's Agent Teams only allows one team per session; the conductor spawns `harness:lead` which becomes the team lead
- **Sequential phases** — phases execute in order, respecting depends_on
- **Idempotent resume** — re-running after a crash should pick up cleanly

$ARGUMENTS
