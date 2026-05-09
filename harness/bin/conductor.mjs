#!/usr/bin/env node
// harness conductor — deterministic orchestration logic extracted from
// commands/run.md so the prompt only handles agent invocation.
//
// Subcommands:
//   conductor validate <workflow.yaml>
//     Reads + parses YAML, runs structural and cross-phase validation.
//     Prints a JSON report to stdout. Exits 0 if no errors.
//
//   conductor init <workflow.yaml> <state-path>
//     Bootstraps a workflow-level state file at <state-path> with every
//     phase marked pending and retry_count=0.
//
//   conductor next <state-path>
//     Reads the workflow + state, returns a JSON descriptor of what to do
//     next. Shape: { action: "run"|"approval"|"plan"|"done"|"failed", ... }.
//
//   conductor record <state-path> <phase-id> <result-json>
//     Atomically records a phase result. result-json must include {status}.
//     Applies retry semantics (failed → pending while retry_count < 2).
//
// All file writes are atomic via .tmp + rename. State files always include
// updated_at. The workflow YAML is re-read on every command so concurrent
// edits are tolerated.

import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseYaml } from './_lib/yaml.mjs';

// Pattern + enum checks aligned to harness/schema/workflow-v1.schema.json.
// We hand-roll these instead of pulling in ajv to keep the conductor zero-dep
// (the plugin ships no node_modules). The schema file remains the canonical
// contract — when adding a check here, the schema should be updated to match.
const PATTERNS = {
  phaseId: /^[a-z0-9][a-z0-9-]*$/,
  workflowName: /^[a-z][a-z0-9-]*$/,
  timeBudget: /^\d+[smh]$/,
};
const ENUMS = {
  direction: new Set(['lower', 'higher']),
  target: new Set(['local', 'server', 'runpod']),
};

const KNOWN_AGENTS = new Set([
  'lead', 'implementer', 'reviewer', 'code-reviewer',
  'optimizer', 'advisor',
  'searcher', 'synthesizer', 'method-analyst',
  'implementation-guide', 'architecture-evaluator',
  'diagnostician', 'fixer', 'verifier',
]);

const PHASE_TYPES = new Set([
  'agent-teams', 'loop', 'subagent', 'inline', 'approval', 'ultraplan',
]);

// Required config keys for non-loop, non-conditional types. Loop is handled
// specially (two modes — generic vs. optimize — discriminated by `config.body`).
const REQUIRED_CONFIG_BY_TYPE = {
  'agent-teams': ['branch'],
  inline: ['command'],
  ultraplan: ['prompt'],
};
const LOOP_OPTIMIZE_REQUIRED = ['artifact', 'metric', 'direction', 'run_command'];
const LOOP_GENERIC_REQUIRED = ['until'];

const MAX_RETRIES = 2;
const CONDUCTOR_SCHEMA = 'harness-conductor/v1';

// ─── IO helpers ─────────────────────────────────────────────────────────────

function readWorkflow(path) {
  const text = readFileSync(path, 'utf8');
  const parsed = parseYaml(text);
  if (!parsed || typeof parsed !== 'object') {
    throw new Error(`workflow at ${path} did not parse to a mapping`);
  }
  return parsed;
}

function readState(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

function writeAtomic(path, obj) {
  const tmp = path + '.tmp';
  writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n');
  renameSync(tmp, path);
}

function nowIso() {
  return new Date().toISOString();
}

// ─── validate ───────────────────────────────────────────────────────────────

export function validate(workflow) {
  const errors = [];
  const warnings = [];

  if (!workflow || typeof workflow !== 'object') {
    return { errors: ['workflow must be a mapping'], warnings: [] };
  }
  if (typeof workflow.name !== 'string' || !PATTERNS.workflowName.test(workflow.name)) {
    errors.push('workflow.name must be lowercase with hyphens only');
  }
  if (!Array.isArray(workflow.phases) || workflow.phases.length === 0) {
    errors.push('workflow.phases must be a non-empty array');
    return { errors, warnings };
  }

  const seen = new Set();
  const phaseIndex = new Map(); // id → array index
  for (let i = 0; i < workflow.phases.length; i++) {
    const p = workflow.phases[i];
    const where = `phases[${i}]`;
    if (!p || typeof p !== 'object') {
      errors.push(`${where}: must be a mapping`);
      continue;
    }
    if (typeof p.id !== 'string' || p.id === '') {
      errors.push(`${where}: missing id`);
      continue;
    }
    if (!PATTERNS.phaseId.test(p.id)) {
      errors.push(`${where}: id '${p.id}' must match ${PATTERNS.phaseId} (lowercase alphanumerics + hyphens, must start with [a-z0-9])`);
    }
    if (seen.has(p.id)) {
      errors.push(`${where}: duplicate id '${p.id}'`);
      continue;
    }
    seen.add(p.id);
    phaseIndex.set(p.id, i);

    if (typeof p.plugin !== 'string') {
      errors.push(`phase '${p.id}': missing plugin`);
    }
    if (!PHASE_TYPES.has(p.type)) {
      errors.push(
        `phase '${p.id}': type '${p.type}' must be one of ${[...PHASE_TYPES].join(', ')}`
      );
    }

    // Required config by type.
    const cfg = p.config || {};
    const required = REQUIRED_CONFIG_BY_TYPE[p.type] || [];
    for (const key of required) {
      if (cfg[key] === undefined || cfg[key] === null || cfg[key] === '') {
        errors.push(`phase '${p.id}' (${p.type}): config.${key} is required`);
      }
    }

    // Loop has two modes: generic (config.body present) and optimize (no body).
    if (p.type === 'loop') {
      const isGeneric = cfg.body !== undefined;
      const loopRequired = isGeneric ? LOOP_GENERIC_REQUIRED : LOOP_OPTIMIZE_REQUIRED;
      const mode = isGeneric ? 'generic' : 'optimize';
      for (const key of loopRequired) {
        if (cfg[key] === undefined || cfg[key] === null || cfg[key] === '') {
          errors.push(`phase '${p.id}' (loop, ${mode} mode): config.${key} is required`);
        }
      }
      // Enum + pattern checks for optimize-mode fields.
      if (!isGeneric) {
        if (cfg.direction !== undefined && !ENUMS.direction.has(cfg.direction)) {
          errors.push(`phase '${p.id}' (loop, optimize): direction must be one of ${[...ENUMS.direction].join(', ')}; got '${cfg.direction}'`);
        }
        if (cfg.target !== undefined && !ENUMS.target.has(cfg.target)) {
          errors.push(`phase '${p.id}' (loop, optimize): target must be one of ${[...ENUMS.target].join(', ')}; got '${cfg.target}'`);
        }
        if (cfg.time_budget !== undefined && !PATTERNS.timeBudget.test(cfg.time_budget)) {
          errors.push(`phase '${p.id}' (loop, optimize): time_budget '${cfg.time_budget}' must match ${PATTERNS.timeBudget} (e.g., 30s, 5m, 2h)`);
        }
        if (cfg.max_experiments !== undefined && (!Number.isInteger(cfg.max_experiments) || cfg.max_experiments < 1)) {
          errors.push(`phase '${p.id}' (loop, optimize): max_experiments must be an integer >= 1; got ${cfg.max_experiments}`);
        }
      }
    }

    // Agent name validation for subagent phases — `agent` is a phase-level
    // field per workflow-v1.schema.json, not nested under config.
    if (p.type === 'subagent') {
      const agent = p.agent;
      if (typeof agent !== 'string') {
        errors.push(`phase '${p.id}': subagent phase requires top-level 'agent' field`);
      } else if (!KNOWN_AGENTS.has(agent)) {
        errors.push(
          `phase '${p.id}': agent '${agent}' is not a known agent. Known: ${[...KNOWN_AGENTS].sort().join(', ')}`
        );
      }
    }

    // depends_on: existence + no forward refs.
    if (p.depends_on !== undefined) {
      if (!Array.isArray(p.depends_on)) {
        errors.push(`phase '${p.id}': depends_on must be an array`);
      } else {
        for (const dep of p.depends_on) {
          if (!phaseIndex.has(dep)) {
            // It either doesn't exist or appears later (forward ref).
            const laterIdx = workflow.phases.findIndex(x => x && x.id === dep);
            if (laterIdx === -1) {
              errors.push(`phase '${p.id}': depends_on references unknown phase '${dep}'`);
            } else if (laterIdx >= i) {
              errors.push(
                `phase '${p.id}': depends_on '${dep}' is a forward reference (phase appears later)`
              );
            }
          }
        }
      }
    }

    // teammates count vs tasks count (warning only).
    if (p.type === 'agent-teams') {
      const teammates = Array.isArray(cfg.teammates) ? cfg.teammates : [];
      const totalCount = teammates.reduce((s, t) => s + (Number(t.count) || 1), 0);
      const tasks = Array.isArray(cfg.tasks) ? cfg.tasks : null;
      if (tasks && totalCount > tasks.length) {
        warnings.push(
          `phase '${p.id}': teammates total (${totalCount}) exceeds task count (${tasks.length}); extras will idle`
        );
      }
    }
  }

  // Cycle detection on depends_on graph.
  if (errors.length === 0) {
    const adj = new Map();
    for (const p of workflow.phases) {
      adj.set(p.id, Array.isArray(p.depends_on) ? p.depends_on : []);
    }
    const WHITE = 0, GRAY = 1, BLACK = 2;
    const color = new Map([...adj.keys()].map(k => [k, WHITE]));
    function visit(node, path) {
      if (color.get(node) === GRAY) {
        const cycleStart = path.indexOf(node);
        errors.push(`cycle detected: ${path.slice(cycleStart).concat(node).join(' → ')}`);
        return false;
      }
      if (color.get(node) === BLACK) return true;
      color.set(node, GRAY);
      for (const dep of adj.get(node) || []) {
        if (!visit(dep, [...path, node])) return false;
      }
      color.set(node, BLACK);
      return true;
    }
    for (const node of adj.keys()) visit(node, []);
  }

  return { errors, warnings };
}

// ─── init ───────────────────────────────────────────────────────────────────

export function init(workflow, workflowPath) {
  const phases = {};
  for (const p of workflow.phases) {
    phases[p.id] = { status: 'pending', retry_count: 0 };
  }
  return {
    schema: CONDUCTOR_SCHEMA,
    workflow_id: workflow.name,
    workflow_path: workflowPath,
    started_at: nowIso(),
    updated_at: nowIso(),
    phases,
  };
}

// ─── next ───────────────────────────────────────────────────────────────────

export function next(workflow, state) {
  for (const p of workflow.phases) {
    const ps = state.phases[p.id];
    if (!ps) {
      // Workflow has phases the state doesn't know about — treat as pending.
      return { action: 'run', phase: p };
    }
    if (ps.status === 'completed' || ps.status === 'skipped') continue;
    if (ps.status === 'failed') {
      if ((ps.retry_count || 0) < MAX_RETRIES) {
        return { action: 'run', phase: p, retry: (ps.retry_count || 0) + 1 };
      }
      return {
        action: 'failed',
        phase_id: p.id,
        reason: `phase '${p.id}' failed ${MAX_RETRIES + 1} times, giving up`,
      };
    }
    if (ps.status === 'waiting_approval') {
      if (p.type === 'ultraplan') return { action: 'plan', phase_id: p.id };
      return { action: 'approval', phase_id: p.id };
    }
    if (ps.status === 'running') {
      // Stale — treat as failed for retry purposes (the session that started
      // this phase died). Liveness is enforced by Step 2's heartbeat check.
      if ((ps.retry_count || 0) < MAX_RETRIES) {
        return {
          action: 'run',
          phase: p,
          retry: (ps.retry_count || 0) + 1,
          reason: 'previous run abandoned',
        };
      }
      return { action: 'failed', phase_id: p.id, reason: 'phase abandoned too many times' };
    }
    // pending
    return { action: 'run', phase: p };
  }
  return { action: 'done' };
}

// ─── record ────────────────────────────────────────────────────────────────

export function record(state, phaseId, result) {
  if (!state.phases[phaseId]) {
    throw new Error(`unknown phase '${phaseId}' in state`);
  }
  const ps = state.phases[phaseId];
  const status = result.status;
  if (!status) throw new Error('record: result.status is required');

  if (status === 'completed' || status === 'skipped') {
    ps.status = status;
    if (result.output) ps.output = result.output;
  } else if (status === 'failed') {
    ps.status = 'failed';
    ps.retry_count = (ps.retry_count || 0) + 1;
    if (result.reason) ps.last_failure = result.reason;
  } else if (status === 'waiting_approval') {
    ps.status = 'waiting_approval';
  } else if (status === 'running') {
    ps.status = 'running';
  } else {
    throw new Error(`record: unknown status '${status}'`);
  }
  state.updated_at = nowIso();
  return state;
}

// ─── CLI dispatch ──────────────────────────────────────────────────────────

function cmdValidate(argv) {
  const wfPath = argv[0];
  if (!wfPath) {
    console.error('usage: conductor validate <workflow.yaml>');
    process.exit(2);
  }
  const wf = readWorkflow(resolve(wfPath));
  const report = validate(wf);
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  process.exit(report.errors.length > 0 ? 1 : 0);
}

function cmdInit(argv) {
  const [wfPath, statePath] = argv;
  if (!wfPath || !statePath) {
    console.error('usage: conductor init <workflow.yaml> <state-path>');
    process.exit(2);
  }
  const wf = readWorkflow(resolve(wfPath));
  const report = validate(wf);
  if (report.errors.length > 0) {
    console.error('refusing to init from invalid workflow:');
    for (const e of report.errors) console.error('  - ' + e);
    process.exit(1);
  }
  const state = init(wf, resolve(wfPath));
  writeAtomic(resolve(statePath), state);
  process.stdout.write(JSON.stringify({ ok: true, state_path: statePath }) + '\n');
}

function cmdNext(argv) {
  const statePath = argv[0];
  if (!statePath) {
    console.error('usage: conductor next <state-path>');
    process.exit(2);
  }
  const state = readState(resolve(statePath));
  const wf = readWorkflow(resolve(state.workflow_path));
  const result = next(wf, state);
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

function cmdRecord(argv) {
  const [statePath, phaseId, resultJson] = argv;
  if (!statePath || !phaseId || !resultJson) {
    console.error('usage: conductor record <state-path> <phase-id> <result-json>');
    process.exit(2);
  }
  const state = readState(resolve(statePath));
  const result = JSON.parse(resultJson);
  const updated = record(state, phaseId, result);
  writeAtomic(resolve(statePath), updated);
  process.stdout.write(JSON.stringify({ ok: true }) + '\n');
}

const SUBCOMMANDS = {
  validate: cmdValidate,
  init: cmdInit,
  next: cmdNext,
  record: cmdRecord,
};

// Only run the CLI when invoked as a script, not when imported by tests.
const isMain = (() => {
  try {
    return resolve(process.argv[1] || '') === fileURLToPath(import.meta.url);
  } catch { return false; }
})();

if (isMain) {
  const [sub, ...rest] = process.argv.slice(2);
  const fn = SUBCOMMANDS[sub];
  if (!fn) {
    console.error('usage: conductor <validate|init|next|record> [args...]');
    process.exit(2);
  }
  try {
    fn(rest);
  } catch (e) {
    console.error('error: ' + (e?.message || e));
    process.exit(1);
  }
}
