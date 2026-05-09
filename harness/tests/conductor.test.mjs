// Tests for harness/bin/conductor.mjs — validate, init, next, record.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const conductorPath = join(__dirname, '..', 'bin', 'conductor.mjs');
const { validate, init, next, record } = await import(conductorPath);

// ─── validate ───────────────────────────────────────────────────────────────

test('validate: valid minimal workflow', () => {
  const wf = {
    name: 'simple',
    phases: [{ id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' } }],
  };
  const r = validate(wf);
  assert.deepEqual(r.errors, []);
});

test('validate: rejects bad name', () => {
  const wf = {
    name: 'BadName',
    phases: [{ id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' } }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('lowercase')));
});

test('validate: rejects empty phases', () => {
  const r = validate({ name: 'x', phases: [] });
  assert.ok(r.errors.some(e => e.includes('non-empty')));
});

test('validate: rejects unknown type', () => {
  const wf = { name: 'x', phases: [{ id: 'a', plugin: 'harness', type: 'frobnicate' }] };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("type 'frobnicate'")));
});

test('validate: rejects unknown agent in subagent phase', () => {
  const wf = {
    name: 'x',
    phases: [{ id: 'a', plugin: 'harness', type: 'subagent', agent: 'wizard' }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("agent 'wizard'")));
});

test('validate: accepts known agent', () => {
  const wf = {
    name: 'x',
    phases: [{ id: 'a', plugin: 'harness', type: 'subagent', agent: 'searcher' }],
  };
  const r = validate(wf);
  assert.deepEqual(r.errors, []);
});

test('validate: rejects subagent missing top-level agent field', () => {
  const wf = {
    name: 'x',
    phases: [{ id: 'a', plugin: 'harness', type: 'subagent', config: {} }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("requires top-level 'agent' field")));
});

test('validate: optimize-mode loop without artifact errors', () => {
  const wf = {
    name: 'x',
    phases: [{ id: 'a', plugin: 'harness', type: 'loop', config: { metric: 'val', direction: 'lower', run_command: 'go' } }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('optimize mode') && e.includes('artifact')));
});

test('validate: generic-mode loop accepts body+until', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: {
        body: { type: 'inline', config: { command: 'echo' } },
        until: '$body.exit_code == 0',
      },
    }],
  };
  const r = validate(wf);
  assert.deepEqual(r.errors, []);
});

test('validate: generic-mode loop without until errors', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: { body: { type: 'inline' } },
    }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('generic mode') && e.includes('until')));
});

test('validate: rejects forward reference in depends_on', () => {
  const wf = {
    name: 'x',
    phases: [
      { id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' }, depends_on: ['b'] },
      { id: 'b', plugin: 'harness', type: 'inline', config: { command: 'echo' } },
    ],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('forward reference')));
});

test('validate: rejects unknown depends_on', () => {
  const wf = {
    name: 'x',
    phases: [
      { id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' }, depends_on: ['missing'] },
    ],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("unknown phase 'missing'")));
});

test('validate: rejects duplicate phase id', () => {
  const wf = {
    name: 'x',
    phases: [
      { id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' } },
      { id: 'a', plugin: 'harness', type: 'inline', config: { command: 'echo' } },
    ],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("duplicate id 'a'")));
});

test('validate: rejects bad phase id pattern', () => {
  const wf = {
    name: 'x',
    phases: [{ id: 'Bad_ID', plugin: 'harness', type: 'inline', config: { command: 'echo' } }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes("id 'Bad_ID'")));
});

test('validate: optimize loop with bad direction enum', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: {
        artifact: 't.py', metric: 'loss', direction: 'sideways', run_command: 'go',
      },
    }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('direction must be one of')));
});

test('validate: optimize loop with bad target enum', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: {
        artifact: 't.py', metric: 'loss', direction: 'lower', run_command: 'go',
        target: 'aws-lambda',
      },
    }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('target must be one of')));
});

test('validate: optimize loop with bad time_budget pattern', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: {
        artifact: 't.py', metric: 'loss', direction: 'lower', run_command: 'go',
        time_budget: '5 minutes',
      },
    }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('time_budget')));
});

test('validate: optimize loop with non-integer max_experiments', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'a',
      plugin: 'harness',
      type: 'loop',
      config: {
        artifact: 't.py', metric: 'loss', direction: 'lower', run_command: 'go',
        max_experiments: 0,
      },
    }],
  };
  const r = validate(wf);
  assert.ok(r.errors.some(e => e.includes('max_experiments')));
});

test('validate: warns when teammates exceed task count', () => {
  const wf = {
    name: 'x',
    phases: [{
      id: 'build',
      plugin: 'harness',
      type: 'agent-teams',
      config: {
        branch: 'feat/x',
        teammates: [{ type: 'implementer', count: 5 }],
        tasks: [{ id: 'T-1' }, { id: 'T-2' }],
      },
    }],
  };
  const r = validate(wf);
  assert.deepEqual(r.errors, []);
  assert.ok(r.warnings.some(w => w.includes('exceeds task count')));
});

// ─── init ───────────────────────────────────────────────────────────────────

test('init: creates state with all phases pending', () => {
  const wf = {
    name: 'x',
    phases: [
      { id: 'a', plugin: 'harness', type: 'inline' },
      { id: 'b', plugin: 'harness', type: 'inline' },
    ],
  };
  const s = init(wf, '/tmp/wf.yaml');
  assert.equal(s.workflow_id, 'x');
  assert.equal(s.workflow_path, '/tmp/wf.yaml');
  assert.equal(s.phases.a.status, 'pending');
  assert.equal(s.phases.a.retry_count, 0);
  assert.equal(s.phases.b.status, 'pending');
  assert.match(s.started_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
});

// ─── next ───────────────────────────────────────────────────────────────────

const sampleWorkflow = {
  name: 'demo',
  phases: [
    { id: 'plan', plugin: 'harness', type: 'ultraplan', config: { prompt: 'p' } },
    { id: 'build', plugin: 'harness', type: 'agent-teams', config: { branch: 'b' } },
    { id: 'gate', plugin: 'harness', type: 'approval' },
    { id: 'pr', plugin: 'harness', type: 'inline', config: { command: 'gh pr create' } },
  ],
};

test('next: returns first pending phase', () => {
  const s = init(sampleWorkflow, '/x');
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'run');
  assert.equal(r.phase.id, 'plan');
});

test('next: skips completed phases', () => {
  const s = init(sampleWorkflow, '/x');
  s.phases.plan.status = 'completed';
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'run');
  assert.equal(r.phase.id, 'build');
});

test('next: returns done when all completed', () => {
  const s = init(sampleWorkflow, '/x');
  for (const id of ['plan', 'build', 'gate', 'pr']) s.phases[id].status = 'completed';
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'done');
});

test('next: retries failed phase up to MAX_RETRIES then fails workflow', () => {
  const s = init(sampleWorkflow, '/x');
  s.phases.plan.status = 'failed';
  s.phases.plan.retry_count = 0;
  let r = next(sampleWorkflow, s);
  assert.equal(r.action, 'run');
  assert.equal(r.retry, 1);

  s.phases.plan.retry_count = 2;
  r = next(sampleWorkflow, s);
  assert.equal(r.action, 'failed');
  assert.equal(r.phase_id, 'plan');
});

test('next: waiting_approval on approval phase emits approval action', () => {
  const s = init(sampleWorkflow, '/x');
  for (const id of ['plan', 'build']) s.phases[id].status = 'completed';
  s.phases.gate.status = 'waiting_approval';
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'approval');
  assert.equal(r.phase_id, 'gate');
});

test('next: waiting_approval on ultraplan phase emits plan action', () => {
  const s = init(sampleWorkflow, '/x');
  s.phases.plan.status = 'waiting_approval';
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'plan');
  assert.equal(r.phase_id, 'plan');
});

test('next: stale running phase is retried as abandoned', () => {
  const s = init(sampleWorkflow, '/x');
  s.phases.plan.status = 'running';
  const r = next(sampleWorkflow, s);
  assert.equal(r.action, 'run');
  assert.equal(r.reason, 'previous run abandoned');
});

// ─── record ────────────────────────────────────────────────────────────────

test('record: marks completed and stores output', async () => {
  const s = init(sampleWorkflow, '/x');
  // Sleep 10ms so updated_at differs from started_at.
  await new Promise(r => setTimeout(r, 10));
  const before = s.updated_at;
  const r = record(s, 'plan', { status: 'completed', output: { plan_path: '.harness/plan.md' } });
  assert.equal(r.phases.plan.status, 'completed');
  assert.deepEqual(r.phases.plan.output, { plan_path: '.harness/plan.md' });
  assert.notEqual(r.updated_at, before);
});

test('record: failed increments retry_count and stores reason', () => {
  const s = init(sampleWorkflow, '/x');
  record(s, 'plan', { status: 'failed', reason: 'oom' });
  assert.equal(s.phases.plan.status, 'failed');
  assert.equal(s.phases.plan.retry_count, 1);
  assert.equal(s.phases.plan.last_failure, 'oom');
});

test('record: rejects unknown phase', () => {
  const s = init(sampleWorkflow, '/x');
  assert.throws(() => record(s, 'nope', { status: 'completed' }), /unknown phase 'nope'/);
});

test('record: rejects missing status', () => {
  const s = init(sampleWorkflow, '/x');
  assert.throws(() => record(s, 'plan', {}), /status is required/);
});
