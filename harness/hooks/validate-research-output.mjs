#!/usr/bin/env node
// PostToolUse hook: validate the structural shape of research subagent output
// after a Write tool call into .harness/research-*.json.
//
// Reads the Claude Code hook payload from stdin (JSON with tool_name and
// tool_input). If the tool was Write and the path matches a research state
// file, the script JSON-parses the file and verifies that the top-level
// `output` arrays have the expected types. Misshapen output is reported on
// stderr with exit 1, which Claude Code surfaces as feedback to the agent.

import { readFileSync } from 'node:fs';

const ARRAY_FIELDS = ['results', 'findings', 'recommendations', 'tradeoff_matrix'];

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function main() {
  const raw = readStdin();
  let payload = {};
  try { payload = JSON.parse(raw); } catch { /* allow empty/non-JSON */ }

  const toolName = payload.tool_name || process.env.TOOL_NAME || '';
  if (toolName !== 'Write') return 0;

  const toolInput = payload.tool_input || {};
  const filePath = toolInput.file_path || toolInput.path || '';
  // Match .harness/research-<run-id>.json (any valid filename body).
  const m = filePath.match(/\.harness\/research-[^/"]+\.json$/);
  if (!m) return 0;

  let state;
  try {
    state = JSON.parse(readFileSync(filePath, 'utf8'));
  } catch (e) {
    console.error(`research output validation: cannot read ${filePath}: ${e.message}`);
    return 1;
  }

  const out = state.output || {};
  const errors = [];
  for (const field of ARRAY_FIELDS) {
    if (out[field] !== undefined && !Array.isArray(out[field])) {
      errors.push(`output.${field} must be an array`);
    }
  }
  if (errors.length) {
    console.error(`research output validation: ${errors.join(', ')}`);
    return 1;
  }
  return 0;
}

process.exit(main());
