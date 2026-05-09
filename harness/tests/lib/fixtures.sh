#!/usr/bin/env bash
# Fixture builders for harness tests. Each function writes a minimal, valid
# artifact (state file, workflow.yaml, etc.) into the current working directory
# so tests can stage realistic inputs without bespoke setup.

# make_build_state <state-dir> <name>
# Writes a minimal valid build-*.json with one task pending.
make_build_state() {
  local dir="$1"
  local name="$2"
  mkdir -p "$dir"
  cat > "$dir/build-${name}.json" <<JSON
{
  "schema_version": "1",
  "phase_id": "${name}",
  "phase_status": "running",
  "team_name": "test-team",
  "config": {
    "branch": "feat/test",
    "quality": {}
  },
  "output": {
    "tasks": {
      "T-001": {"subject": "first task", "status": "pending"}
    },
    "stories_completed": 0,
    "stories_total": 1
  },
  "progress": {"current": 0, "total": 1, "unit": "stories"},
  "teammates": [],
  "updated_at": "2026-01-01T00:00:00Z"
}
JSON
  echo "$dir/build-${name}.json"
}

# make_build_state_with_quality <state-dir> <name> <typecheck-cmd> <test-cmd>
# Like make_build_state but includes quality gate commands.
make_build_state_with_quality() {
  local dir="$1"
  local name="$2"
  local typecheck="$3"
  local test_cmd="$4"
  mkdir -p "$dir"
  cat > "$dir/build-${name}.json" <<JSON
{
  "schema_version": "1",
  "phase_id": "${name}",
  "phase_status": "running",
  "team_name": "test-team",
  "config": {
    "branch": "feat/test",
    "quality": {
      "typecheck": "${typecheck}",
      "test": "${test_cmd}"
    }
  },
  "output": {
    "tasks": {
      "T-001": {"subject": "first task", "status": "pending"}
    }
  },
  "updated_at": "2026-01-01T00:00:00Z"
}
JSON
  echo "$dir/build-${name}.json"
}

# make_workflow <path> [phase-yaml]
# Writes a minimal valid workflow.yaml. If phase-yaml is provided, uses it as
# the phases array body; otherwise emits a single inline phase.
make_workflow() {
  local path="$1"
  local phases="${2:-}"
  mkdir -p "$(dirname "$path")"
  if [ -z "$phases" ]; then
    phases=$'  - id: hello\n    plugin: harness\n    type: inline\n    config:\n      command: "echo hello"'
  fi
  cat > "$path" <<YAML
name: test-workflow
version: 1
phases:
${phases}
YAML
  echo "$path"
}

# isolate_tmp [prefix]
# Mints a fresh tmp dir and registers a cleanup trap on EXIT for the caller.
# Echoes the path. Tests should `cd "$(isolate_tmp)"` to enter it.
isolate_tmp() {
  local prefix="${1:-harness-test}"
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
  echo "$dir"
}
