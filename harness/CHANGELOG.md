# harness changelog

## 2.0.0 — 2026-05-10

Major version: orchestration moved from prompt to code, plus security and reliability hardening. State files written by 1.x are not migrated — finish or cancel any in-flight 1.x workflows before upgrading.

### Added

- **Conductor CLI** — [`bin/conductor.mjs`](bin/conductor.mjs) handles workflow validation (DAG, cycles, forward refs, agent names, type-specific config, enums, patterns), state init, next-phase selection with retry semantics, and atomic phase result recording. The `/harness:run` slash command delegates to the CLI; the prompt only handles agentic per-phase execution. 31 unit tests.
- **State liveness via heartbeat** — `bin/heartbeat.mjs` writes a dedicated `last_heartbeat` field every 1.5s. `find_active_build_state` in `_lib.sh` checks freshness against `HARNESS_STALE_THRESHOLD_SECONDS` (default 600s). Stale state files no-op so a crashed previous session never hijacks unrelated subsequent sessions. 8 unit tests.
- **Quality-gate allowlist** — `is_safe_quality_command` in `_lib.sh` validates that commands sourced from `workflow.yaml` quality config match a binary allowlist (pnpm/npm/cargo/pytest/uv/make/tsc/...) and don't chain via `;`, `&&`, `||`, `$()`, or backticks. Configurable via `HARNESS_QUALITY_ALLOWED_BINARIES`. Pipes and `2>&1` still allowed. 16 unit tests.
- **State mutation CLI** — `bin/state-mutate.py` provides three named ops (`mark-task-completed`, `record-teammate-status`, `add-task`) with atomic `.tmp` + `os.replace` writes. Replaces the bash → python heredoc pattern in hooks. 12 unit tests.
- **Standalone research validator** — `hooks/validate-research-output.mjs` replaces the inline node-inside-bash-inside-JSON blob in `hooks.json`. Plain JS, testable. 7 unit tests.
- **Test infrastructure** — `harness/tests/` with bash + node test runners, isolated tmpdirs per test, sanity helpers, and CI workflow at `.github/workflows/harness-tests.yml`. 54+ tests total.
- **Minimal YAML parser** — `bin/_lib/yaml.mjs` covers the workflow.yaml subset (block maps/seqs/scalars/`|`/`>`). Zero deps. 19 unit tests.

### Changed

- **`commands/run.md`** shrank from 492 → 442 lines. §2 (validate), §3 (resume), §4 loop control, and §5 finalize now delegate to the conductor CLI. Per-phase agentic logic stays in the prompt.
- **`on-teammate-idle.sh`** now blocks idle only when `pending_tasks > other_working_teammates` (slack-based). Previously prodded every idle teammate to claim while ANY task was incomplete, causing thrash with more workers than work.
- **`on-task-completed.sh`** uses `bash -c -- "$cmd"` instead of `eval`, with allowlist validation before execution.
- **All hook scripts** that previously called `mutate_state` now invoke `bin/state-mutate.py` with explicit args. The old `mutate_state` heredoc helper is removed.

### Validation tightened

The conductor `validate` subcommand now enforces (in addition to existing checks):
- Phase id pattern: `^[a-z0-9][a-z0-9-]*$`
- Optimize-loop `direction` enum: `lower|higher`
- Optimize-loop `target` enum: `local|server|runpod`
- Optimize-loop `time_budget` regex: `^\d+[smh]$`
- Optimize-loop `max_experiments`: integer ≥ 1

These align with `harness/schema/workflow-v1.schema.json` (which remains the canonical contract). All four shipped default workflows continue to validate clean.

### Migration

- **In-flight 1.x state files**: finish or cancel before upgrading. The conductor's expected state schema added `phase_status`, `last_heartbeat`, and `heartbeat_pid` fields. 1.x files lack these and will be treated as stale.
- **Custom quality commands**: if your `workflow.yaml` uses a runner not in the default allowlist (default covers pnpm/npm/yarn/bun/cargo/go/rustc/pytest/python/uv/ruff/mypy/make/tsc/eslint/prettier/biome/node/deno/bash/sh), set `HARNESS_QUALITY_ALLOWED_BINARIES="my-runner other-runner"` before invoking `/harness:run`.
- **Custom hook scripts**: the `mutate_state` helper in `_lib.sh` is removed. Use `bin/state-mutate.py` (or add a new named op there) instead of bash-templated Python.

### Security model (newly documented)

`harness/CLAUDE.md` adds a Security model section. Trusted: workflow.yaml, hardware target config, state files. Untrusted: agent prompts and tool outputs from external sources (PR diffs, web results, fetched issues). The quality-gate allowlist applies even to "trusted" workflow.yaml as defense-in-depth.

## 1.1.0 — 2026-05-10

Added dashboard skill + render-dashboard.js.

## 1.0.0 — 2026-05-10

Initial consolidated release. Replaces the former five-plugin lineup (conductor + harness-build/optimize/research/triage).
