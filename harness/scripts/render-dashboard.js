#!/usr/bin/env node
// render-dashboard.js — generates dashboard.html from .harness/ state files
// Usage: node render-dashboard.js [harness-dir]
'use strict';

const fs   = require('fs');
const path = require('path');

const harnessDir = process.argv[2] || '.harness';

// ── Data loading ─────────────────────────────────────────────────────────────

function readStates(dir) {
  if (!fs.existsSync(dir)) {
    console.error(`harness dir not found: ${dir}`);
    process.exit(1);
  }
  const states = [];
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
    try {
      const parsed = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf-8'));
      if (parsed.schema === 'harness/v1') {
        parsed._subsystem = file.split('-')[0];
        parsed._filename  = file;
        states.push(parsed);
      }
    } catch {}
  }
  return states;
}

function improvementPct(baseline, best, direction) {
  if (baseline == null || best == null || baseline === 0) return null;
  const raw = direction === 'lower'
    ? (baseline - best) / baseline
    : (best   - baseline) / baseline;
  return (raw * 100).toFixed(1);
}

function basename(p) {
  if (!p) return null;
  return p.split('/').pop() || null;
}

function fmt(n) {
  return n != null ? n.toFixed(4) : '—';
}

function relTime(iso) {
  if (!iso) return '—';
  const diff = Math.round((Date.now() - new Date(iso)) / 1000);
  if (diff < 60)   return `${diff}s ago`;
  if (diff < 3600) return `${Math.round(diff/60)}m ago`;
  return `${Math.round(diff/3600)}h ago`;
}

// ── HTML helpers ──────────────────────────────────────────────────────────────

function esc(s) {
  return String(s ?? '')
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;');
}

function badge(status) {
  const map = {
    completed:         ['#22c55e','#052e16'],
    running:           ['#3b82f6','#0c1a40'],
    pending:           ['#64748b','#1e293b'],
    failed:            ['#ef4444','#2d0b0b'],
    skipped:           ['#475569','#1e293b'],
    cancelled:         ['#475569','#1e293b'],
    waiting_approval:  ['#f59e0b','#2d1b00'],
  };
  const [fg, bg] = map[status] ?? ['#94a3b8','#1e293b'];
  return `<span class="badge" style="color:${fg};background:${bg}">${esc(status)}</span>`;
}

// ── Section renderers ─────────────────────────────────────────────────────────

function renderConductor(c) {
  if (!c) return '';
  const out = c.output ?? {};
  const phases_done  = out.phases_completed ?? '?';
  const phases_total = out.phases_total     ?? '?';
  const elapsed = c.elapsed_seconds != null
    ? `${Math.round(c.elapsed_seconds / 60)}m ${c.elapsed_seconds % 60}s`
    : '—';

  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label conductor">conductor</span>
    <h2>${esc(c.workflow_id ?? 'Workflow')}</h2>
    ${badge(c.status)}
  </div>
  <dl class="meta">
    <dt>Phases</dt><dd>${esc(phases_done)} / ${esc(phases_total)}</dd>
    <dt>Run ID</dt><dd class="mono">${esc(c.run_id)}</dd>
    <dt>Elapsed</dt><dd>${elapsed}</dd>
    <dt>Updated</dt><dd>${relTime(c.updated_at)}</dd>
  </dl>
  ${c.error ? `<div class="error-box">${esc(c.error.message)}</div>` : ''}
</section>`;
}

function renderOptimize(s) {
  const cfg = s.config ?? {};
  const m   = s.metric ?? {};
  const history = m.history ?? [];

  const artifact   = basename(cfg.artifact) ?? cfg.artifact ?? '(unknown)';
  const direction  = m.direction ?? cfg.direction ?? 'lower';
  const pct        = improvementPct(m.baseline, m.best, direction);
  const targetStr  = cfg.target === 'server' && cfg.ssh_host
    ? `${cfg.ssh_host}${cfg.cwd ? ':' + cfg.cwd : ''}`
    : cfg.target ?? 'local';

  const histRows = history.map((e, i) => {
    const isBaseline = e.status === 'baseline';
    const isKept     = e.status === 'kept';
    const isRev      = e.status === 'reverted';
    const rowStyle   = isBaseline ? ''
      : isKept  ? ' style="background:#052e1620"'
      : isRev   ? ' style="background:#2d0b0b20"'
      : '';
    const shaLink = e.commit_sha
      ? `<span class="mono sha">${esc(e.commit_sha.slice(0,7))}</span>`
      : '—';
    return `<tr${rowStyle}>
      <td class="center">${i + 1}</td>
      <td class="mono">${fmt(e.value)}</td>
      <td>${badge(e.status)}</td>
      <td>${shaLink}</td>
      <td class="dim">${esc(e.description ?? '')}</td>
    </tr>`;
  }).join('');

  const kept     = history.filter(e => e.status === 'kept').length;
  const reverted = history.filter(e => e.status === 'reverted').length;

  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label optimize">optimize</span>
    <h2>${esc(artifact)}</h2>
    ${badge(s.status)}
  </div>
  <dl class="meta">
    <dt>Metric</dt><dd>${esc(m.name ?? cfg.metric ?? '—')} (${direction})</dd>
    <dt>Baseline</dt><dd class="mono">${fmt(m.baseline)}</dd>
    <dt>Best</dt><dd class="mono">${fmt(m.best)}${pct != null ? ` <span class="improvement">▲${pct}%</span>` : ''}</dd>
    <dt>Kept / Rev.</dt><dd>${kept} kept, ${reverted} reverted</dd>
    <dt>Target</dt><dd class="mono dim">${esc(targetStr)}</dd>
    <dt>Run ID</dt><dd class="mono dim">${esc(s.run_id)}</dd>
  </dl>
  ${histRows ? `
  <table>
    <thead><tr><th>#</th><th>Value</th><th>Status</th><th>SHA</th><th>Description</th></tr></thead>
    <tbody>${histRows}</tbody>
  </table>` : ''}
  ${s.error ? `<div class="error-box">${esc(s.error.message)}</div>` : ''}
</section>`;
}

function renderBuild(s) {
  const out      = s.output   ?? {};
  const teammates = out.teammates ?? [];
  const tasks    = Object.entries(out.tasks ?? {});

  const teammateRows = teammates.map(t =>
    `<tr><td>${esc(t.type ?? t.role ?? '?')}</td><td>${badge(t.status ?? 'pending')}</td><td class="mono dim">${esc(t.id ?? '')}</td></tr>`
  ).join('');

  const taskRows = tasks.map(([id, t]) =>
    `<tr><td class="mono">${esc(id)}</td><td>${esc(t.title ?? '')}</td><td>${badge(t.status ?? 'pending')}</td></tr>`
  ).join('');

  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label build">build</span>
    <h2>${esc(s.phase_id ?? 'Build')}</h2>
    ${badge(s.status)}
  </div>
  <dl class="meta">
    <dt>Stories</dt><dd>${out.stories_completed ?? 0} / ${out.stories_total ?? '?'}</dd>
    <dt>Branch</dt><dd class="mono dim">${esc(s.config?.branch ?? '—')}</dd>
    <dt>Review</dt><dd>${esc(out.review_verdict ?? '—')}</dd>
    <dt>Run ID</dt><dd class="mono dim">${esc(s.run_id)}</dd>
  </dl>
  ${teammateRows ? `
  <h3>Teammates</h3>
  <table><thead><tr><th>Type</th><th>Status</th><th>ID</th></tr></thead>
  <tbody>${teammateRows}</tbody></table>` : ''}
  ${taskRows ? `
  <h3>Tasks</h3>
  <table><thead><tr><th>ID</th><th>Title</th><th>Status</th></tr></thead>
  <tbody>${taskRows}</tbody></table>` : ''}
  ${s.error ? `<div class="error-box">${esc(s.error.message)}</div>` : ''}
</section>`;
}

function renderResearch(s) {
  const cfg = s.config ?? {};
  const out = s.output  ?? {};
  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label research">research</span>
    <h2>${esc(s.phase_id ?? 'Research')}</h2>
    ${badge(s.status)}
  </div>
  <dl class="meta">
    <dt>Query</dt><dd>${esc(cfg.query ?? '—')}</dd>
    <dt>Agent</dt><dd>${esc(cfg.agent ?? s.config?.agent ?? '—')}</dd>
    <dt>Sources</dt><dd>${esc((cfg.sources ?? []).join(', ') || '—')}</dd>
    <dt>Results</dt><dd>${esc(out.results_count ?? '—')}</dd>
    <dt>Run ID</dt><dd class="mono dim">${esc(s.run_id)}</dd>
  </dl>
  ${s.error ? `<div class="error-box">${esc(s.error.message)}</div>` : ''}
</section>`;
}

function renderTriage(s) {
  const cfg = s.config ?? {};
  const out = s.output  ?? {};
  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label triage">triage</span>
    <h2>${esc(s.phase_id ?? 'Triage')}</h2>
    ${badge(s.status)}
  </div>
  <dl class="meta">
    <dt>Agent</dt><dd>${esc(cfg.agent ?? '—')}</dd>
    <dt>Issue</dt><dd class="mono dim">${esc(cfg.issue_url ?? '—')}</dd>
    <dt>Fix branch</dt><dd class="mono dim">${esc(out.fix_branch ?? '—')}</dd>
    <dt>PR</dt><dd class="mono dim">${esc(out.pr_url ?? '—')}</dd>
    <dt>Run ID</dt><dd class="mono dim">${esc(s.run_id)}</dd>
  </dl>
  ${s.error ? `<div class="error-box">${esc(s.error.message)}</div>` : ''}
</section>`;
}

function renderGeneric(s) {
  return `
<section class="card">
  <div class="card-header">
    <span class="subsystem-label">${esc(s._subsystem ?? s.plugin ?? '?')}</span>
    <h2>${esc(s.phase_id ?? s.run_id)}</h2>
    ${badge(s.status)}
  </div>
  <dl class="meta">
    <dt>Run ID</dt><dd class="mono dim">${esc(s.run_id)}</dd>
    <dt>Updated</dt><dd>${relTime(s.updated_at)}</dd>
  </dl>
  ${s.error ? `<div class="error-box">${esc(s.error.message)}</div>` : ''}
</section>`;
}

// ── HTML shell ────────────────────────────────────────────────────────────────

const CSS = `
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:#0d1117;color:#c9d1d9;font-size:13px;line-height:1.6;padding:24px}
h1{font-size:16px;font-weight:600;color:#e6edf3;margin-bottom:4px}
h2{font-size:13px;font-weight:600;color:#e6edf3}
h3{font-size:12px;font-weight:600;color:#8b949e;margin:14px 0 6px;text-transform:uppercase;letter-spacing:.05em}
a{color:#58a6ff;text-decoration:none}
.header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:24px;padding-bottom:16px;border-bottom:1px solid #21262d}
.generated{font-size:11px;color:#484f58;margin-top:2px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(480px,1fr));gap:16px}
.card{background:#161b22;border:1px solid #21262d;border-radius:6px;padding:16px;overflow:hidden}
.card-header{display:flex;align-items:center;gap:10px;margin-bottom:12px}
.card-header h2{flex:1}
.subsystem-label{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;padding:2px 7px;border-radius:3px;flex-shrink:0}
.subsystem-label.conductor{background:#1c2744;color:#79c0ff}
.subsystem-label.build{background:#1a2d1a;color:#56d364}
.subsystem-label.optimize{background:#2d1b44;color:#d2a8ff}
.subsystem-label.research{background:#2d2200;color:#e3b341}
.subsystem-label.triage{background:#2d1212;color:#f85149}
.badge{font-size:10px;font-weight:600;padding:2px 8px;border-radius:3px;white-space:nowrap}
dl.meta{display:grid;grid-template-columns:auto 1fr;gap:3px 14px;margin-bottom:12px}
dt{color:#484f58;white-space:nowrap}
dd{color:#c9d1d9;word-break:break-all}
.improvement{color:#22c55e;font-size:11px}
.mono{font-family:inherit}
.dim{color:#484f58}
.sha{font-size:11px}
table{width:100%;border-collapse:collapse;font-size:12px;margin-top:8px}
th{text-align:left;color:#484f58;font-weight:600;padding:4px 8px;border-bottom:1px solid #21262d;text-transform:uppercase;font-size:10px;letter-spacing:.05em}
td{padding:4px 8px;border-bottom:1px solid #161b22}
tr:last-child td{border-bottom:none}
.center{text-align:center}
.error-box{margin-top:10px;padding:8px 10px;background:#2d0b0b;border:1px solid #6e1a1a;border-radius:4px;color:#f85149;font-size:12px;word-break:break-word}
`;

function buildHtml(conductor, phases) {
  const workflowName = conductor?.workflow_id ?? 'Harness Run';
  const workflowStatus = conductor?.status ?? 'unknown';

  const sections = [
    renderConductor(conductor),
    ...phases.map(s => {
      switch (s._subsystem) {
        case 'optimize': return renderOptimize(s);
        case 'build':    return renderBuild(s);
        case 'research': return renderResearch(s);
        case 'triage':   return renderTriage(s);
        default:         return renderGeneric(s);
      }
    }),
  ].filter(Boolean).join('\n');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Harness — ${esc(workflowName)}</title>
<style>${CSS}</style>
</head>
<body>
<div class="header">
  <div>
    <h1>Harness Dashboard</h1>
    <div class="generated">Generated ${new Date().toISOString()} · ${esc(path.resolve(harnessDir))}</div>
  </div>
  ${badge(workflowStatus)}
</div>
<div class="cards">
${sections}
</div>
</body>
</html>`;
}

// ── Main ──────────────────────────────────────────────────────────────────────

const states    = readStates(harnessDir);
const conductor = states
  .filter(s => s._subsystem === 'conductor')
  .sort((a,b) => new Date(b.updated_at) - new Date(a.updated_at))[0] ?? null;
const phases    = states.filter(s => s._subsystem !== 'conductor');

const html     = buildHtml(conductor, phases);
const outPath  = path.join(harnessDir, 'dashboard.html');
fs.writeFileSync(outPath, html, 'utf-8');

// Text summary to stdout
const done    = phases.filter(s => s.status === 'completed').length;
const failed  = phases.filter(s => s.status === 'failed').length;
const running = phases.filter(s => s.status === 'running').length;
console.log(`Dashboard written to ${outPath}`);
console.log(`Workflow: ${conductor?.workflow_id ?? '(none)'} — ${conductor?.status ?? 'no conductor'}`);
console.log(`Phases: ${done} completed, ${running} running, ${failed} failed, ${phases.length} total`);
for (const s of phases) {
  const tag = s._subsystem === 'optimize'
    ? ` [${basename(s.config?.artifact) ?? '?'} → best ${fmt(s.metric?.best)}]`
    : '';
  console.log(`  ${s._subsystem.padEnd(10)} ${s.status}${tag}`);
}
