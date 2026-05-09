// Minimal YAML parser for harness workflow.yaml files.
//
// Supported subset:
//   - Block mappings:           key: value
//   - Block sequences:          - item
//   - Nested via indentation (spaces only — tabs reject)
//   - Scalars: bare strings, double-quoted, single-quoted, numbers, booleans, null
//   - Flow sequences inline:    [a, b, "c d"]
//   - Comments: # to end of line (outside quoted strings)
//   - Blank lines between entries
//
// NOT supported (out of scope, throws or ignores):
//   - Anchors/aliases (& *), merge keys (<<), multi-doc (---), custom tags (!!),
//     block scalar styles (>, |), flow mappings ({a: b}), complex keys.
//
// API:
//   parse(text) → primitive | object | array | null
//
// Errors carry { line: <1-based> } for diagnostics.

class YamlError extends Error {
  constructor(msg, line) {
    super(line ? `YAML line ${line}: ${msg}` : `YAML: ${msg}`);
    this.line = line;
  }
}

// Strip comments outside quoted strings. Returns content with trailing # ...
// removed. We track quote state to avoid splitting inside `"a # b"`.
function stripComment(line) {
  let out = '';
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '#' && !inSingle && !inDouble) break;
    out += ch;
  }
  return out;
}

// Tokenize input into [{indent, content, lineNo}] entries, skipping blanks.
// Block scalars (`key: |` / `key: >`) consume subsequent indented lines and
// emit a single token whose `content` is `key: <literal-payload>` with the
// payload encoded as a single-line JSON string; the parser detects this via
// the `blockScalar` field and assigns the value directly without re-parsing.
function tokenize(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const lineNo = i + 1;
    if (/^\s*$/.test(raw)) continue;
    if (/^\s*#/.test(raw)) continue;
    if (/^\t/.test(raw) || /^( *)\t/.test(raw)) {
      throw new YamlError('tab indentation is not allowed', lineNo);
    }
    const stripped = stripComment(raw).replace(/\s+$/, '');
    if (stripped === '') continue;
    const indent = stripped.match(/^( *)/)[1].length;
    const content = stripped.slice(indent);

    // Detect block scalar: `key: |` or `key: >` (with optional +/-).
    const blockMatch = content.match(/^([^:\s][^:]*?):\s*([|>])([+-]?)\s*$/);
    if (blockMatch) {
      const key = blockMatch[1];
      const style = blockMatch[2]; // | or >
      const chomp = blockMatch[3]; // '', +, or -
      // Consume subsequent lines indented strictly deeper than `indent`.
      const bodyLines = [];
      let bodyIndent = -1;
      let j = i + 1;
      while (j < lines.length) {
        const peek = lines[j];
        if (/^\s*$/.test(peek)) {
          bodyLines.push('');
          j++;
          continue;
        }
        const peekIndent = peek.match(/^( *)/)[1].length;
        if (peekIndent <= indent) break;
        if (bodyIndent === -1) bodyIndent = peekIndent;
        bodyLines.push(peek.slice(bodyIndent));
        j++;
      }
      // Trim trailing blanks then apply chomping.
      while (bodyLines.length > 0 && bodyLines[bodyLines.length - 1] === '') {
        bodyLines.pop();
      }
      let payload;
      if (style === '|') {
        payload = bodyLines.join('\n');
      } else {
        // Folded: blank lines preserve as \n, otherwise join with space.
        const folded = [];
        for (const ln of bodyLines) {
          if (ln === '') folded.push('\n');
          else if (folded.length === 0 || folded[folded.length - 1] === '\n') folded.push(ln);
          else folded[folded.length - 1] += ' ' + ln;
        }
        payload = folded.join('');
      }
      if (chomp !== '-') payload += '\n';
      out.push({ indent, content: `${key}:`, lineNo, blockScalarValue: payload });
      i = j - 1;
      continue;
    }

    out.push({ indent, content, lineNo });
  }
  return out;
}

// Parse a scalar value (right-hand side of `key:` or sequence item).
// Returns the typed value.
function parseScalar(text, lineNo) {
  const t = text.trim();
  if (t === '' || t === '~' || t === 'null') return null;
  if (t === 'true') return true;
  if (t === 'false') return false;
  // Flow sequence: [a, b, "c d"]
  if (t.startsWith('[') && t.endsWith(']')) {
    return parseFlowSequence(t, lineNo);
  }
  // Quoted string
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  // Number
  if (/^-?\d+$/.test(t)) return parseInt(t, 10);
  if (/^-?\d*\.\d+$/.test(t)) return parseFloat(t);
  // Bare string
  return t;
}

// Parse `[a, b, "c, d", 3]` → typed array. Handles quoted commas.
function parseFlowSequence(text, lineNo) {
  const inner = text.slice(1, -1).trim();
  if (inner === '') return [];
  const items = [];
  let buf = '';
  let inSingle = false;
  let inDouble = false;
  let depth = 0;
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '[' && !inSingle && !inDouble) depth++;
    else if (ch === ']' && !inSingle && !inDouble) depth--;
    if (ch === ',' && !inSingle && !inDouble && depth === 0) {
      items.push(parseScalar(buf, lineNo));
      buf = '';
      continue;
    }
    buf += ch;
  }
  if (buf.trim() !== '') items.push(parseScalar(buf, lineNo));
  return items;
}

// Recursive parser. Consumes tokens at `indent` and returns the parsed value.
// `tokens` is mutated (shifts from front via index). State is passed via `ctx`.
function parseBlock(ctx, parentIndent) {
  if (ctx.i >= ctx.tokens.length) return null;
  const first = ctx.tokens[ctx.i];
  // The block at `parentIndent + something` — its own indent is whatever the
  // first child has, and all siblings must match.
  const blockIndent = first.indent;
  if (blockIndent <= parentIndent) return null;

  // Sequence?
  if (first.content.startsWith('- ') || first.content === '-') {
    return parseSequence(ctx, blockIndent);
  }
  return parseMapping(ctx, blockIndent);
}

function parseMapping(ctx, indent) {
  const result = {};
  while (ctx.i < ctx.tokens.length) {
    const tok = ctx.tokens[ctx.i];
    if (tok.indent < indent) break;
    if (tok.indent > indent) {
      throw new YamlError(
        `unexpected indent (got ${tok.indent}, expected ${indent})`,
        tok.lineNo
      );
    }
    const m = tok.content.match(/^([^:\s][^:]*?):\s*(.*)$/);
    if (!m) {
      throw new YamlError(`expected 'key: value', got: ${tok.content}`, tok.lineNo);
    }
    const key = m[1].trim();
    const rest = m[2];
    if (tok.blockScalarValue !== undefined) {
      result[key] = tok.blockScalarValue;
      ctx.i++;
      continue;
    }
    ctx.i++;
    if (rest === '' || rest === undefined) {
      // Value is on subsequent lines (nested block).
      const next = ctx.tokens[ctx.i];
      if (!next || next.indent <= indent) {
        result[key] = null;
      } else {
        result[key] = parseBlock(ctx, indent);
      }
    } else {
      result[key] = parseScalar(rest, tok.lineNo);
    }
  }
  return result;
}

function parseSequence(ctx, indent) {
  const result = [];
  while (ctx.i < ctx.tokens.length) {
    const tok = ctx.tokens[ctx.i];
    if (tok.indent < indent) break;
    if (tok.indent > indent) {
      throw new YamlError(
        `unexpected indent in sequence (got ${tok.indent}, expected ${indent})`,
        tok.lineNo
      );
    }
    if (!tok.content.startsWith('-')) break;
    const after = tok.content.slice(1).replace(/^\s+/, '');
    ctx.i++;
    if (after === '') {
      // Item is a block on subsequent lines.
      result.push(parseBlock(ctx, indent));
      continue;
    }
    // Item is inline. Could be a scalar, or a single-key mapping (`- key: val`),
    // possibly followed by sibling keys at indent + 2.
    const m = after.match(/^([^:\s][^:]*?):\s*(.*)$/);
    if (m) {
      const key = m[1].trim();
      const rest = m[2];
      const obj = {};
      if (rest === '') {
        const next = ctx.tokens[ctx.i];
        if (next && next.indent > indent) {
          // The continuation indent for `- key:` items is indent+2 (the dash
          // plus space). Build a synthetic indent for the nested mapping.
          obj[key] = parseBlock(ctx, indent + 2);
        } else {
          obj[key] = null;
        }
      } else {
        obj[key] = parseScalar(rest, tok.lineNo);
      }
      // Absorb sibling keys at indent + 2 (e.g., `  type: implementer\n  count: 3`).
      while (ctx.i < ctx.tokens.length) {
        const sib = ctx.tokens[ctx.i];
        if (sib.indent !== indent + 2) break;
        const sm = sib.content.match(/^([^:\s][^:]*?):\s*(.*)$/);
        if (!sm) break;
        const sKey = sm[1].trim();
        const sRest = sm[2];
        if (sib.blockScalarValue !== undefined) {
          obj[sKey] = sib.blockScalarValue;
          ctx.i++;
          continue;
        }
        ctx.i++;
        if (sRest === '') {
          const next = ctx.tokens[ctx.i];
          if (next && next.indent > indent + 2) {
            obj[sKey] = parseBlock(ctx, indent + 2);
          } else {
            obj[sKey] = null;
          }
        } else {
          obj[sKey] = parseScalar(sRest, sib.lineNo);
        }
      }
      result.push(obj);
    } else {
      result.push(parseScalar(after, tok.lineNo));
    }
  }
  return result;
}

export function parse(text) {
  const tokens = tokenize(text);
  if (tokens.length === 0) return null;
  const ctx = { tokens, i: 0 };
  // Determine top-level indent (first token's indent — usually 0).
  const first = tokens[0];
  if (first.content.startsWith('- ') || first.content === '-') {
    return parseSequence(ctx, first.indent);
  }
  return parseMapping(ctx, first.indent);
}

export { YamlError };
