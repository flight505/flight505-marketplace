---
name: pick-workflow
description: "Match a task description to the best default workflow, collect the required values interactively, write .harness/workflow.yaml with everything filled in, and hand off to /harness:run. Full path from description to ready-to-run — no manual file copying or placeholder editing."
argument-hint: "<describe what you want to do>"
user-invocable: true
allowed-tools: Bash Read Write
---

# Pick and Configure Workflow

Match `$ARGUMENTS` to a default workflow, collect required values in one message, write `.harness/workflow.yaml` with all placeholders replaced, then hand off to `/harness:run`.

## Step 1: Match

Read the available templates:

```bash
ls "${CLAUDE_PLUGIN_ROOT}/workflows/defaults/"
```

Match `$ARGUMENTS` against these rules:

| User says... | Workflow |
|---|---|
| fix, bug, issue, diagnose, error, crash, triage | `fix-github-issue` |
| feature, idea, build, implement, add, create | `idea-to-pr` |
| refactor, clean up, migrate, restructure, rename | `refactor-safely` |
| review, PR, check, audit, inspect | `smart-pr-review` |

If no clear match, list all four with their one-line descriptions and ask the user to choose before continuing.

## Step 2: Ask all questions in one message

Announce the matched workflow (one sentence — name + pipeline summary). Then ask for all required values in a single response. Never ask one question at a time.

**fix-github-issue — ask for:**
- GitHub issue URL (e.g. `https://github.com/owner/repo/issues/42`)
- Issue number only (e.g. `42`) — used in the branch name

**idea-to-pr — ask for:**
- Feature description — this goes to ultraplan, so the more detail the better
- Short branch slug (e.g. `dark-mode`, `user-api`, `payment-flow`)

**refactor-safely — ask for:**
- Refactoring goal — one sentence describing what to restructure
- Typecheck command (e.g. `pnpm typecheck`, `tsc --noEmit`, `cargo check`)
- Test command (e.g. `pnpm test`, `pytest`, `cargo test`)
- Branch name slug (e.g. `cleanup-auth`, `migrate-to-esm`)

**smart-pr-review — ask for:**
- PR branch name (e.g. `feat/dark-mode`)
- PR number (e.g. `87`)

## Step 3: Write the workflow

Once the user has provided all values:

Create the directory:

```bash
mkdir -p .harness
```

Read the template into context:

```bash
cat "${CLAUDE_PLUGIN_ROOT}/workflows/defaults/<matched-workflow>.yaml"
```

Perform all placeholder substitutions in memory — replace every `REPLACE_WITH_*` string with the corresponding user-provided value. Then write the complete substituted content to `.harness/workflow.yaml` using the Write tool.

Placeholder map per workflow:

| Workflow | Placeholder | Replace with |
|----------|------------|--------------|
| fix-github-issue | `REPLACE_WITH_ISSUE_URL` | full issue URL |
| fix-github-issue | `REPLACE_WITH_ISSUE_NUMBER` | issue number (appears in branch + pr command) |
| idea-to-pr | `REPLACE_WITH_FEATURE_DESCRIPTION` | feature description |
| idea-to-pr | `REPLACE_WITH_FEATURE_NAME` | branch slug (appears in branch + pr command) |
| refactor-safely | `REPLACE_WITH_REFACTORING_GOAL` | refactoring goal |
| refactor-safely | `REPLACE_WITH_TYPECHECK_CMD` | typecheck command (appears twice — defaults block + loop body) |
| refactor-safely | `REPLACE_WITH_TEST_CMD` | test command |
| refactor-safely | `REPLACE_WITH_BRANCH_NAME` | branch slug |
| smart-pr-review | `REPLACE_WITH_PR_BRANCH` | PR branch name |
| smart-pr-review | `REPLACE_WITH_PR_NUMBER` | PR number |

Replace ALL occurrences of each placeholder — some appear more than once in the same file.

## Step 4: Confirm

After writing the file, confirm with a brief summary:

```
Ready: .harness/workflow.yaml

  <workflow-name> — <one-line pipeline summary>

Run it:
  /harness:run
```

Do not run the conductor automatically — the user triggers it.
