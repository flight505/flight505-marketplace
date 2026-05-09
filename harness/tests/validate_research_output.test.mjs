// Tests for harness/hooks/validate-research-output.mjs.
// The validator runs as a PostToolUse hook: stdin = Claude Code hook payload,
// exit 0 = ok, exit 1 = misshapen research output (becomes feedback).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const validator = join(__dirname, '..', 'hooks', 'validate-research-output.mjs');

function runValidator(payload, cwd) {
  const result = spawnSync('node', [validator], {
    input: JSON.stringify(payload),
    cwd,
    encoding: 'utf8',
  });
  return { code: result.status, stderr: result.stderr };
}

function makeResearchFile(dir, name, body) {
  mkdirSync(dir, { recursive: true });
  const path = join(dir, name);
  writeFileSync(path, JSON.stringify(body, null, 2));
  return path;
}

test('returns 0 when tool is not Write', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const r = runValidator({ tool_name: 'Read', tool_input: {} }, tmp);
  assert.equal(r.code, 0);
});

test('returns 0 when file path does not match research-*.json', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const r = runValidator(
    { tool_name: 'Write', tool_input: { file_path: '.harness/build-a.json' } },
    tmp
  );
  assert.equal(r.code, 0);
});

test('returns 0 when output arrays have correct types', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const file = makeResearchFile(join(tmp, '.harness'), 'research-r1.json', {
    output: {
      results: [{ title: 'a' }],
      findings: ['hello'],
      recommendations: [],
    },
  });
  const r = runValidator(
    { tool_name: 'Write', tool_input: { file_path: file } },
    tmp
  );
  assert.equal(r.code, 0, `stderr: ${r.stderr}`);
});

test('returns 1 with reason when results is not an array', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const file = makeResearchFile(join(tmp, '.harness'), 'research-r2.json', {
    output: { results: 'not-an-array' },
  });
  const r = runValidator(
    { tool_name: 'Write', tool_input: { file_path: file } },
    tmp
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /results must be an array/);
});

test('returns 1 listing all violated fields together', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const file = makeResearchFile(join(tmp, '.harness'), 'research-r3.json', {
    output: {
      results: 'x',
      findings: 'y',
      tradeoff_matrix: 5,
    },
  });
  const r = runValidator(
    { tool_name: 'Write', tool_input: { file_path: file } },
    tmp
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /results.*findings.*tradeoff_matrix|tradeoff_matrix.*findings.*results/);
});

test('returns 1 when file does not exist', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const r = runValidator(
    { tool_name: 'Write', tool_input: { file_path: '.harness/research-missing.json' } },
    tmp
  );
  assert.equal(r.code, 1);
  assert.match(r.stderr, /cannot read/);
});

test('handles empty stdin without crashing', () => {
  const tmp = mkdtempSync(join(tmpdir(), 'rv-'));
  const result = spawnSync('node', [validator], { cwd: tmp, encoding: 'utf8', input: '' });
  assert.equal(result.status, 0);
});
