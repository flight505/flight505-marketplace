---
name: advisor
description: "Analyze the current project for autoresearch optimization opportunities. Scans the project, identifies candidates matching the keep/revert loop pattern (single mutable artifact, scalar metric, fixed time budget, repeatable execution), and presents ready-to-run suggestions with workflow.yaml snippets. Use when the user asks what they can optimize, what to autoresearch, or how to apply the optimization loop to their project."
argument-hint: "[path — defaults to current directory]"
user-invocable: true
allowed-tools: Bash Read Glob Grep
---

# Harness-Optimize Advisor

Analyze a project for autoresearch optimization opportunities and present findings conversationally with concrete, ready-to-use workflow config snippets. Speak to the user — do not return raw JSON.

## Hardware context

```bash
cat "${CLAUDE_PLUGIN_DATA:-${HOME}/.harness}/config.json" 2>/dev/null || echo "NO_CONFIG"
```

If output is `NO_CONFIG`, tell the user to run `/harness:setup` first to register hardware targets, then continue the analysis using `target: local` as a placeholder in any suggested workflow snippets.

## Step 1: Determine the target directory

If `$ARGUMENTS` is provided, treat it as the path to analyze. Otherwise use the current working directory.

```bash
ls -la ${ARGUMENTS:-.}
```

Read key files: `README.md`, `package.json`, `pyproject.toml`, `Cargo.toml`, `Makefile`, main entry points, and any existing benchmark or test scripts. For ML repos specifically, look for `train.py`, `program.md`, `prepare.py`.

## Step 2: Apply the four-condition test

The autoresearch keep/revert loop works when ALL FOUR conditions hold:

| # | Condition | What to look for |
|---|-----------|-----------------|
| 1 | **Single mutable artifact** | One file the agent edits each iteration |
| 2 | **Scalar automated metric** | A number computable without human judgment (lower or higher is better) |
| 3 | **Fixed time-boxed cycle** | Every experiment runs for identical wall-clock time |
| 4 | **Repeatable automated execution** | End-to-end, no human in the loop |

For each candidate you identify, check all four honestly. If the metric requires human judgment or execution isn't fully automated, say so — don't oversell weak fits.

**Strong candidate domains:**

| Domain | Typical artifact | Typical metric | Typical budget |
|--------|-----------------|----------------|----------------|
| ML training | `train.py` | `val_bpb`, `val_loss` | 5 min |
| API latency | route handler | p99 response time (ms) | 2–5 min load test |
| Database queries | query/schema file | execution time (ms) | 1–3 min benchmark |
| Build pipeline | build config | build duration (s) | single build |
| Bundle size | bundler config | output bytes | single build |
| Inference speed | serving/model code | tokens/sec | fixed eval run |
| Prompt quality | prompt template | accuracy on eval set | eval run time |
| ETL pipeline | transform script | wall-clock time | fixed dataset |

**Do not suggest:**
- Subjective quality with no automated metric
- Changes spanning multiple files (violates single-artifact constraint)
- Tasks requiring human judgment to evaluate

## Step 3: Match to hardware

Use the hardware config injected above to recommend the best target for each candidate:

| Scenario | Recommend |
|----------|-----------|
| PyTorch / CUDA workload | `server` or `runpod` |
| Overnight unattended run | `server` or `runpod` — frees the Mac |
| Quick daytime iteration | `local` |
| Apple Silicon / MLX workload | `local` |
| No targets configured | Suggest `/harness:setup` before running |

## Step 4: Present findings

Present **2–3 concrete suggestions** as prose. For each:

1. **Name it** and explain why it fits the pattern
2. **Artifact** — the exact file the agent would edit
3. **Metric** — what to measure and how to extract it from output (show the grep/regex if needed)
4. **Hardware target** — which one and why
5. **Setup needed** — be explicit if a benchmark script must be written first, data must be prepared, etc.

Then show a ready-to-copy workflow.yaml snippet for each:

```yaml
# .harness/workflow.yaml
name: optimize-<what>
phases:
  - id: optimize
    plugin: harness
    type: loop
    config:
      artifact: "path/to/artifact.py"
      metric: "metric_name"
      direction: lower          # or higher
      run_command: "command to run"
      time_budget: "5m"
      max_experiments: 30
      target: local             # or server / runpod
      # ssh_host: "user@host"   # required if target: server
      # cwd: "/remote/path"     # required if target: server
```

Fill in actual values from your analysis — never leave placeholder text in the snippet.

## Step 5: Offer next steps

After presenting suggestions, close with:

> "Want me to build the full `workflow.yaml` for one of these? If you need a benchmark script written first, I can help with that too. Or run `/harness:setup` to register your hardware targets before we start."

If the project has no strong candidates, say so plainly:

> "I didn't find a strong fit for the autoresearch pattern here. The main blocker is [specific reason]. To make it work, you'd need [what's missing]."

## Constraints

- Prose output only — no raw JSON to the user
- Name actual files and commands found in the project — no generic placeholders
- Maximum 3 suggestions — quality over quantity
- Be honest about weak fits; a missing benchmark script is a real blocker, say so
- If metric extraction requires a custom parser or grep, show it explicitly
