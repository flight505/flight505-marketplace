// Tests for harness/bin/_lib/yaml.mjs — a minimal YAML parser scoped to the
// workflow.yaml subset (block maps, block sequences, scalars, flow sequences,
// quoted strings, comments). NOT a full YAML implementation.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const yamlModulePath = join(__dirname, '..', 'bin', '_lib', 'yaml.mjs');
const { parse } = await import(yamlModulePath);

test('parse: empty input → null', () => {
  assert.equal(parse(''), null);
  assert.equal(parse('\n\n\n'), null);
});

test('parse: scalar mapping with bare strings', () => {
  const out = parse('name: hello\nkind: greeting\n');
  assert.deepEqual(out, { name: 'hello', kind: 'greeting' });
});

test('parse: double-quoted strings preserve spaces and colons', () => {
  const out = parse('msg: "hello: world"\n');
  assert.deepEqual(out, { msg: 'hello: world' });
});

test('parse: numbers and booleans are typed', () => {
  const out = parse('count: 3\nenabled: true\nratio: 0.5\nblank: null\n');
  assert.deepEqual(out, { count: 3, enabled: true, ratio: 0.5, blank: null });
});

test('parse: comments are stripped', () => {
  const out = parse('# leading\nname: a # inline\n# trailing\n');
  assert.deepEqual(out, { name: 'a' });
});

test('parse: block sequence of scalars', () => {
  const out = parse('items:\n  - one\n  - two\n  - three\n');
  assert.deepEqual(out, { items: ['one', 'two', 'three'] });
});

test('parse: block sequence of mappings', () => {
  const yaml = `phases:
  - id: plan
    type: ultraplan
  - id: build
    type: agent-teams
`;
  const out = parse(yaml);
  assert.deepEqual(out, {
    phases: [
      { id: 'plan', type: 'ultraplan' },
      { id: 'build', type: 'agent-teams' },
    ],
  });
});

test('parse: nested mapping under a key', () => {
  const yaml = `config:
  branch: feat/x
  quality:
    test: pnpm test
    typecheck: tsc
`;
  const out = parse(yaml);
  assert.deepEqual(out, {
    config: {
      branch: 'feat/x',
      quality: { test: 'pnpm test', typecheck: 'tsc' },
    },
  });
});

test('parse: flow sequence (inline array)', () => {
  const out = parse('depends_on: [plan, build]\n');
  assert.deepEqual(out, { depends_on: ['plan', 'build'] });
});

test('parse: flow sequence with quoted strings', () => {
  const out = parse('args: ["pnpm test", "tsc -p ."]\n');
  assert.deepEqual(out, { args: ['pnpm test', 'tsc -p .'] });
});

test('parse: deeply nested workflow structure', () => {
  const yaml = `name: idea-to-pr
phases:
  - id: build
    plugin: harness
    type: agent-teams
    depends_on: [plan]
    config:
      branch: "feat/x"
      teammates:
        - type: implementer
          count: 3
      code_review: true
`;
  const out = parse(yaml);
  assert.deepEqual(out, {
    name: 'idea-to-pr',
    phases: [
      {
        id: 'build',
        plugin: 'harness',
        type: 'agent-teams',
        depends_on: ['plan'],
        config: {
          branch: 'feat/x',
          teammates: [{ type: 'implementer', count: 3 }],
          code_review: true,
        },
      },
    ],
  });
});

test('parse: blank lines between mapping entries are tolerated', () => {
  const yaml = `name: x

phases:

  - id: a
    type: inline

  - id: b
    type: inline
`;
  const out = parse(yaml);
  assert.deepEqual(out, {
    name: 'x',
    phases: [
      { id: 'a', type: 'inline' },
      { id: 'b', type: 'inline' },
    ],
  });
});

test('parse: single-quoted strings', () => {
  const out = parse(`msg: 'hello world'\n`);
  assert.deepEqual(out, { msg: 'hello world' });
});

test('parse: literal block scalar with |', () => {
  const yaml = `description: |
  line one
  line two
  line three
`;
  const out = parse(yaml);
  assert.equal(out.description, 'line one\nline two\nline three\n');
});

test('parse: literal block scalar inside sequence item', () => {
  const yaml = `tasks:
  - id: T-001
    description: |
      first paragraph
      continues here
    title: short
`;
  const out = parse(yaml);
  assert.deepEqual(out, {
    tasks: [
      {
        id: 'T-001',
        description: 'first paragraph\ncontinues here\n',
        title: 'short',
      },
    ],
  });
});

test('parse: folded block scalar with >', () => {
  const yaml = `msg: >
  the quick
  brown fox
`;
  const out = parse(yaml);
  assert.equal(out.msg, 'the quick brown fox\n');
});

test('parse: block scalar chomp -', () => {
  const yaml = `msg: |-
  no trailing newline
`;
  const out = parse(yaml);
  assert.equal(out.msg, 'no trailing newline');
});

test('parse: error on tab indentation', () => {
  assert.throws(() => parse('a:\n\t- 1\n'), /tab/i);
});

test('parse: error on inconsistent indent', () => {
  // A child indented less than its parent's children is invalid.
  const yaml = `a:
  b: 1
 c: 2
`;
  assert.throws(() => parse(yaml));
});
