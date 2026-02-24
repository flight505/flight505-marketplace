# Research Assistant — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a skills-first Claude Code plugin that gives Claude and agents deep access to SOTA research via arXiv, Semantic Scholar, and Papers With Code — with synthesis agents for literature review, method comparison, and implementation guidance.

**Architecture:** 4 skills (1 router + 3 retrieval with Node.js scripts), 3 synthesis agents, 2 validation hooks. No MCP server. All free APIs, zero API keys required. Output optimized for LLM consumption.

**Tech Stack:** Node.js 18+ (built-in `fetch()`), Python 3 (hook validators), Bash (script wrappers)

**Design doc:** `docs/plans/2026-02-24-research-assistant-design.md`

---

## Task 1: Create GitHub Repo & Submodule Scaffold

**Files:**
- Create: `research-assistant/` (via git submodule)
- Create: `research-assistant/.claude-plugin/plugin.json`
- Create: `research-assistant/.gitignore`
- Create: `research-assistant/LICENSE`

**Step 1: Create the GitHub repository**

```bash
gh repo create flight505/research-assistant --public --description "Deep research intelligence for Claude Code — SOTA papers, method analysis, and implementation guidance" --license MIT
```

**Step 2: Add as submodule to marketplace**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
git submodule add https://github.com/flight505/research-assistant.git research-assistant
```

**Step 3: Create the plugin manifest**

Create `research-assistant/.claude-plugin/plugin.json`:
```json
{
  "name": "research-assistant",
  "version": "1.0.0",
  "description": "Deep research intelligence for Claude and agents — access, understand, and apply SOTA scientific research from arXiv, Semantic Scholar, and Papers With Code",
  "author": {
    "name": "Jesper Vang",
    "url": "https://github.com/flight505"
  },
  "license": "MIT",
  "repository": "https://github.com/flight505/research-assistant",
  "homepage": "https://github.com/flight505/research-assistant",
  "keywords": [
    "research",
    "arxiv",
    "semantic-scholar",
    "papers-with-code",
    "literature-review",
    "ai-research",
    "foundation-models",
    "machine-learning"
  ],
  "skills": [
    "./skills/using-research-assistant",
    "./skills/arxiv-search",
    "./skills/semantic-scholar-search",
    "./skills/papers-with-code-search"
  ],
  "agents": [
    "./agents/literature-reviewer.md",
    "./agents/method-analyst.md",
    "./agents/implementation-guide.md"
  ]
}
```

**Step 4: Create .gitignore**

Create `research-assistant/.gitignore`:
```
node_modules/
__pycache__/
*.pyc
.DS_Store
.env
*.log
```

**Step 5: Verify plugin.json is valid**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
python3 -c "import json; json.load(open('research-assistant/.claude-plugin/plugin.json'))" && echo "Valid JSON"
```

**Step 6: Commit scaffold in plugin repo**

```bash
cd research-assistant
git add .claude-plugin/plugin.json .gitignore
git commit -m "feat: initial plugin scaffold with manifest"
git push origin main
```

---

## Task 2: arXiv Search Skill

**Files:**
- Create: `research-assistant/skills/arxiv-search/SKILL.md`
- Create: `research-assistant/skills/arxiv-search/scripts/search` (bash wrapper)
- Create: `research-assistant/skills/arxiv-search/scripts/search.mjs` (Node.js implementation)

**Step 1: Write the Node.js search script**

Create `research-assistant/skills/arxiv-search/scripts/search.mjs`:

```javascript
#!/usr/bin/env node

/**
 * arXiv Search — Direct API access (no API key required)
 * Searches arXiv Atom API for papers in AI/ML/data science categories.
 * Returns unified JSON envelope optimized for LLM consumption.
 */

const ARXIV_API = 'http://export.arxiv.org/api/query';

const DEFAULT_CATEGORIES = ['cs.AI', 'cs.LG', 'cs.CL', 'cs.CV', 'stat.ML', 'cs.MA'];

function buildQuery(query, categories, sortBy, maxResults) {
  const catFilter = categories.map(c => `cat:${c}`).join('+OR+');
  const searchQuery = `all:${encodeURIComponent(query)}+AND+(${catFilter})`;
  const sortParam = sortBy === 'date' ? 'submittedDate' : 'relevance';
  return `${ARXIV_API}?search_query=${searchQuery}&start=0&max_results=${maxResults}&sortBy=${sortParam}&sortOrder=descending`;
}

function parseAtomXml(xml) {
  const entries = [];
  const entryPattern = /<entry>([\s\S]*?)<\/entry>/g;
  let match;

  while ((match = entryPattern.exec(xml)) !== null) {
    const entry = match[1];
    const get = (tag) => {
      const m = entry.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`));
      return m ? m[1].trim() : '';
    };
    const getAll = (tag) => {
      const results = [];
      const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'g');
      let m;
      while ((m = re.exec(entry)) !== null) results.push(m[1].trim());
      return results;
    };
    const getAttr = (tag, attr) => {
      const m = entry.match(new RegExp(`<${tag}[^>]*${attr}="([^"]*)"[^>]*/?>`, 'g'));
      return m ? m.map(x => { const a = x.match(new RegExp(`${attr}="([^"]*)"`)); return a ? a[1] : ''; }) : [];
    };

    const title = get('title').replace(/\s+/g, ' ');
    const abstract = get('summary').replace(/\s+/g, ' ');
    const published = get('published');
    const updated = get('updated');
    const authors = getAll('name');
    const categories = getAttr('category', 'term');
    const links = entry.match(/<link[^>]*>/g) || [];
    const pdfLink = links.find(l => l.includes('type="application/pdf"'));
    const pdfUrl = pdfLink ? (pdfLink.match(/href="([^"]*)"/) || [])[1] || '' : '';
    const absLink = links.find(l => l.includes('type="text/html"')) || links.find(l => !l.includes('type='));
    const absUrl = absLink ? (absLink.match(/href="([^"]*)"/) || [])[1] || '' : '';
    const id = get('id');
    const arxivId = id.replace('http://arxiv.org/abs/', '').replace(/v\d+$/, '');

    entries.push({
      title,
      authors,
      year: published ? parseInt(published.substring(0, 4), 10) : null,
      abstract: abstract.length > 500 ? abstract.substring(0, 500) + '...' : abstract,
      tldr: '',
      url: absUrl || id,
      pdf_url: pdfUrl,
      citations: null,
      code_repos: [],
      relevance_score: null,
      key_methods: [],
      source_specific: {
        arxiv_id: arxivId,
        categories,
        published,
        updated
      }
    });
  }
  return entries;
}

async function searchArxiv(query, maxResults = 10, sortBy = 'relevance', categories = null) {
  const cats = categories || DEFAULT_CATEGORIES;

  try {
    const url = buildQuery(query, cats, sortBy, maxResults);
    const response = await fetch(url);

    if (!response.ok) {
      return {
        success: false,
        error: `arXiv API returned HTTP ${response.status}`,
        source: 'arxiv'
      };
    }

    const xml = await response.text();
    const results = parseAtomXml(xml);

    return {
      success: true,
      query,
      source: 'arxiv',
      result_count: results.length,
      results,
      meta: {
        timestamp: new Date().toISOString(),
        api_version: 'arxiv-atom-1.0',
        categories_searched: cats,
        sort_by: sortBy
      }
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
      source: 'arxiv'
    };
  }
}

// CLI
const args = process.argv.slice(2);

if (args.length === 0 || args[0] === '--help') {
  console.log(JSON.stringify({
    success: false,
    error: 'Query required. Usage: search <query> [maxResults] [--sort=date|relevance] [--cats=cs.AI,cs.LG]'
  }, null, 2));
  process.exit(1);
}

const query = args[0];
let maxResults = 10;
let sortBy = 'relevance';
let categories = null;

for (let i = 1; i < args.length; i++) {
  if (args[i].startsWith('--sort=')) {
    sortBy = args[i].split('=')[1];
  } else if (args[i].startsWith('--cats=')) {
    categories = args[i].split('=')[1].split(',');
  } else if (!isNaN(parseInt(args[i], 10))) {
    maxResults = parseInt(args[i], 10);
  }
}

searchArxiv(query, maxResults, sortBy, categories).then(result => {
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.success ? 0 : 1);
});
```

**Step 2: Write the bash wrapper**

Create `research-assistant/skills/arxiv-search/scripts/search`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$1" in
    --path|--location|--where) echo "${SCRIPT_DIR}/search"; exit 0 ;;
    --script-dir) echo "$SCRIPT_DIR"; exit 0 ;;
esac
node "${SCRIPT_DIR}/search.mjs" "$@"
```

**Step 3: Make scripts executable**

```bash
chmod +x research-assistant/skills/arxiv-search/scripts/search
chmod +x research-assistant/skills/arxiv-search/scripts/search.mjs
```

**Step 4: Test the script**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
node research-assistant/skills/arxiv-search/scripts/search.mjs "transformer attention mechanisms" 3
```

Expected: JSON with `success: true`, `source: "arxiv"`, `result_count: 3`, and results array with title, authors, abstract, pdf_url.

**Step 5: Write the SKILL.md**

Create `research-assistant/skills/arxiv-search/SKILL.md`:

```markdown
---
name: arxiv-search
description: Search arXiv for latest AI/ML preprints. Use when Claude needs bleeding-edge research not yet in peer-reviewed journals — newest methods, architectures, training techniques, benchmarks.
keywords: [arxiv, preprints, papers, research, machine-learning, deep-learning, AI, foundation-models]
---

# arXiv Search

Search arXiv preprints across AI/ML categories: cs.AI, cs.LG, cs.CL, cs.CV, stat.ML, cs.MA.

No API key required. Uses arXiv public API directly.

## Usage

Find the script path, then execute:

```bash
SCRIPT=$(find ~/.claude/plugins -path "*/research-assistant/skills/arxiv-search/scripts/search.mjs" 2>/dev/null | head -1)
node "$SCRIPT" "your query" [maxResults] [--sort=date|relevance] [--cats=cs.AI,cs.LG]
```

## Arguments

| Arg | Default | Description |
|-----|---------|-------------|
| query | (required) | Natural language search query |
| maxResults | 10 | Number of results (1-100) |
| --sort=date | relevance | Sort by submission date or relevance |
| --cats=cs.AI,cs.LG | all 6 defaults | Comma-separated arXiv categories |

## When to Use

- Finding the newest preprints on a topic (use `--sort=date`)
- Searching for specific methods or architectures
- Getting abstracts and PDF links for deeper reading
- Checking if new work exists in a specific arXiv category

## Output Format

Returns JSON with unified envelope:
- `results[].title` — paper title
- `results[].authors` — author list
- `results[].abstract` — first 500 chars of abstract
- `results[].pdf_url` — direct PDF link
- `results[].source_specific.arxiv_id` — arXiv identifier
- `results[].source_specific.categories` — arXiv categories
- `results[].source_specific.published` — publication date

## Examples

```bash
# Latest papers on chain-of-thought reasoning
node "$SCRIPT" "chain-of-thought reasoning" 10 --sort=date

# Search specific category
node "$SCRIPT" "diffusion models" 5 --cats=cs.CV

# Broad AI safety search
node "$SCRIPT" "AI alignment safety" 20
```
```

**Step 6: Commit**

```bash
cd research-assistant
git add skills/arxiv-search/
git commit -m "feat: add arxiv-search skill with Node.js script"
git push origin main
```

---

## Task 3: Semantic Scholar Search Skill

**Files:**
- Create: `research-assistant/skills/semantic-scholar-search/SKILL.md`
- Create: `research-assistant/skills/semantic-scholar-search/scripts/search` (bash wrapper)
- Create: `research-assistant/skills/semantic-scholar-search/scripts/search.mjs`

**Step 1: Write the Node.js search script**

Create `research-assistant/skills/semantic-scholar-search/scripts/search.mjs`:

```javascript
#!/usr/bin/env node

/**
 * Semantic Scholar Search — Academic Graph API (free, no key for 100 req/sec)
 * Rich metadata: citations, TLDRs, influence scores, related papers.
 * Returns unified JSON envelope optimized for LLM consumption.
 */

const S2_API = 'https://api.semanticscholar.org/graph/v1';
const FIELDS = 'title,authors,year,abstract,tldr,url,openAccessPdf,citationCount,influentialCitationCount,fieldsOfStudy,venue,externalIds,publicationDate';

async function searchPapers(query, maxResults = 10, yearFrom = null, openAccess = false) {
  try {
    const params = new URLSearchParams({
      query,
      limit: String(Math.min(maxResults, 100)),
      fields: FIELDS
    });
    if (yearFrom) params.set('year', `${yearFrom}-`);
    if (openAccess) params.set('openAccessPdf', '');

    const response = await fetch(`${S2_API}/paper/search?${params}`);

    if (response.status === 429) {
      return { success: false, error: 'Rate limited. Wait a moment and retry.', source: 'semantic_scholar' };
    }

    if (!response.ok) {
      return { success: false, error: `S2 API returned HTTP ${response.status}`, source: 'semantic_scholar' };
    }

    const data = await response.json();
    const papers = (data.data || []).map(paper => ({
      title: paper.title || '',
      authors: (paper.authors || []).map(a => a.name),
      year: paper.year,
      abstract: paper.abstract
        ? (paper.abstract.length > 500 ? paper.abstract.substring(0, 500) + '...' : paper.abstract)
        : '',
      tldr: paper.tldr?.text || '',
      url: paper.url || '',
      pdf_url: paper.openAccessPdf?.url || '',
      citations: paper.citationCount || 0,
      code_repos: [],
      relevance_score: null,
      key_methods: [],
      source_specific: {
        s2_paper_id: paper.paperId,
        influential_citations: paper.influentialCitationCount || 0,
        fields_of_study: paper.fieldsOfStudy || [],
        venue: paper.venue || '',
        doi: paper.externalIds?.DOI || '',
        arxiv_id: paper.externalIds?.ArXiv || '',
        publication_date: paper.publicationDate || ''
      }
    }));

    return {
      success: true,
      query,
      source: 'semantic_scholar',
      result_count: papers.length,
      results: papers,
      meta: {
        timestamp: new Date().toISOString(),
        api_version: 'semantic-scholar-graph-v1',
        total_available: data.total || papers.length
      }
    };
  } catch (error) {
    return { success: false, error: error.message, source: 'semantic_scholar' };
  }
}

async function getPaperDetails(paperId) {
  try {
    const detailFields = FIELDS + ',references,citations';
    const response = await fetch(`${S2_API}/paper/${encodeURIComponent(paperId)}?fields=${detailFields}`);

    if (!response.ok) {
      return { success: false, error: `S2 API returned HTTP ${response.status}`, source: 'semantic_scholar' };
    }

    const paper = await response.json();

    return {
      success: true,
      source: 'semantic_scholar',
      paper: {
        title: paper.title || '',
        authors: (paper.authors || []).map(a => a.name),
        year: paper.year,
        abstract: paper.abstract || '',
        tldr: paper.tldr?.text || '',
        url: paper.url || '',
        pdf_url: paper.openAccessPdf?.url || '',
        citations: paper.citationCount || 0,
        influential_citations: paper.influentialCitationCount || 0,
        venue: paper.venue || '',
        fields_of_study: paper.fieldsOfStudy || [],
        doi: paper.externalIds?.DOI || '',
        references_count: (paper.references || []).length,
        top_references: (paper.references || []).slice(0, 10).map(r => ({
          title: r.title,
          year: r.year,
          citations: r.citationCount
        })),
        recent_citations: (paper.citations || []).slice(0, 10).map(c => ({
          title: c.title,
          year: c.year,
          citations: c.citationCount
        }))
      },
      meta: { timestamp: new Date().toISOString(), api_version: 'semantic-scholar-graph-v1' }
    };
  } catch (error) {
    return { success: false, error: error.message, source: 'semantic_scholar' };
  }
}

// CLI
const args = process.argv.slice(2);

if (args.length === 0 || args[0] === '--help') {
  console.log(JSON.stringify({
    success: false,
    error: 'Usage: search <query> [maxResults] [--year=2024] [--open-access] [--detail=<paperId>]'
  }, null, 2));
  process.exit(1);
}

// Check for --detail mode
const detailArg = args.find(a => a.startsWith('--detail='));
if (detailArg) {
  const paperId = detailArg.split('=')[1];
  getPaperDetails(paperId).then(result => {
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.success ? 0 : 1);
  });
} else {
  const query = args[0];
  let maxResults = 10;
  let yearFrom = null;
  let openAccess = false;

  for (let i = 1; i < args.length; i++) {
    if (args[i].startsWith('--year=')) yearFrom = parseInt(args[i].split('=')[1], 10);
    else if (args[i] === '--open-access') openAccess = true;
    else if (!isNaN(parseInt(args[i], 10))) maxResults = parseInt(args[i], 10);
  }

  searchPapers(query, maxResults, yearFrom, openAccess).then(result => {
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.success ? 0 : 1);
  });
}
```

**Step 2: Write the bash wrapper**

Create `research-assistant/skills/semantic-scholar-search/scripts/search`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$1" in
    --path|--location|--where) echo "${SCRIPT_DIR}/search"; exit 0 ;;
    --script-dir) echo "$SCRIPT_DIR"; exit 0 ;;
esac
node "${SCRIPT_DIR}/search.mjs" "$@"
```

**Step 3: Make scripts executable**

```bash
chmod +x research-assistant/skills/semantic-scholar-search/scripts/search
chmod +x research-assistant/skills/semantic-scholar-search/scripts/search.mjs
```

**Step 4: Test the script**

```bash
node research-assistant/skills/semantic-scholar-search/scripts/search.mjs "ReAct prompting framework" 3
```

Expected: JSON with `success: true`, `source: "semantic_scholar"`, results with `tldr` fields populated, `citations` counts, and `source_specific.influential_citations`.

**Step 5: Test detail mode**

```bash
# Use a known paper ID (e.g., "Attention Is All You Need")
node research-assistant/skills/semantic-scholar-search/scripts/search.mjs --detail=204e3073870fae3d05bcbc2f6a8e263d9b72e776
```

Expected: JSON with `paper` object containing `top_references` and `recent_citations` arrays.

**Step 6: Write the SKILL.md**

Create `research-assistant/skills/semantic-scholar-search/SKILL.md`:

```markdown
---
name: semantic-scholar-search
description: Search Semantic Scholar for papers with rich metadata — citation counts, AI-generated TLDRs, influence scores, citation graphs. Use for finding established research, tracing citation chains, understanding paper impact and field structure.
keywords: [semantic-scholar, citations, papers, research, tldr, impact, academic, literature]
---

# Semantic Scholar Search

Search 200M+ papers with rich metadata. No API key required (100 req/sec).

Two modes:
1. **Search** — find papers by query
2. **Detail** — get deep info on a specific paper (references, citations)

## Usage

```bash
SCRIPT=$(find ~/.claude/plugins -path "*/research-assistant/skills/semantic-scholar-search/scripts/search.mjs" 2>/dev/null | head -1)

# Search mode
node "$SCRIPT" "your query" [maxResults] [--year=2024] [--open-access]

# Detail mode (get paper + citations + references)
node "$SCRIPT" --detail=<s2PaperId|DOI|ArXiv:id>
```

## Arguments

| Arg | Default | Description |
|-----|---------|-------------|
| query | (required) | Natural language search query |
| maxResults | 10 | Number of results (1-100) |
| --year=YYYY | none | Only papers from YYYY onward |
| --open-access | false | Only papers with free PDF |
| --detail=ID | n/a | Get full details for a specific paper |

## When to Use

- Finding papers with citation context (how influential, who cites it)
- Getting AI-generated TLDRs for quick understanding
- Tracing citation chains (what a paper builds on, what builds on it)
- Filtering by year to find recent work
- Finding open access PDFs for deeper reading

## Key Fields

- `results[].tldr` — AI-generated one-sentence summary (from S2)
- `results[].citations` — total citation count
- `results[].source_specific.influential_citations` — citations from influential papers
- `results[].source_specific.fields_of_study` — e.g., ["Computer Science", "Mathematics"]
- Detail mode: `paper.top_references` and `paper.recent_citations` for citation graph

## Examples

```bash
# Find influential papers on RLHF
node "$SCRIPT" "reinforcement learning from human feedback" 10

# Recent papers only (2025+)
node "$SCRIPT" "mixture of experts scaling" 15 --year=2025

# Get details + citation graph for a specific paper
node "$SCRIPT" --detail=ArXiv:2210.11416
```
```

**Step 7: Commit**

```bash
cd research-assistant
git add skills/semantic-scholar-search/
git commit -m "feat: add semantic-scholar-search skill with detail mode"
git push origin main
```

---

## Task 4: Papers With Code Search Skill

**Files:**
- Create: `research-assistant/skills/papers-with-code-search/SKILL.md`
- Create: `research-assistant/skills/papers-with-code-search/scripts/search` (bash wrapper)
- Create: `research-assistant/skills/papers-with-code-search/scripts/search.mjs`

**Step 1: Write the Node.js search script**

Create `research-assistant/skills/papers-with-code-search/scripts/search.mjs`:

```javascript
#!/usr/bin/env node

/**
 * Papers With Code Search — Free API, no key required
 * Links papers to code repositories, benchmarks, datasets, and methods.
 * Returns unified JSON envelope optimized for LLM consumption.
 */

const PWC_API = 'https://paperswithcode.com/api/v1';

async function searchPapers(query, maxResults = 10) {
  try {
    const params = new URLSearchParams({ q: query, page: '1', items_per_page: String(maxResults) });
    const response = await fetch(`${PWC_API}/papers/?${params}`);

    if (!response.ok) {
      return { success: false, error: `PwC API returned HTTP ${response.status}`, source: 'papers_with_code' };
    }

    const data = await response.json();
    const papers = (data.results || []).map(paper => ({
      title: paper.title || '',
      authors: (paper.authors || []),
      year: paper.published ? parseInt(paper.published.substring(0, 4), 10) : null,
      abstract: paper.abstract
        ? (paper.abstract.length > 500 ? paper.abstract.substring(0, 500) + '...' : paper.abstract)
        : '',
      tldr: '',
      url: paper.url_abs || paper.paper_url || '',
      pdf_url: paper.url_pdf || '',
      citations: null,
      code_repos: [],
      relevance_score: null,
      key_methods: [],
      source_specific: {
        pwc_id: paper.id,
        proceeding: paper.proceeding || '',
        tasks: paper.tasks || [],
        methods: paper.methods || []
      }
    }));

    // Fetch repos for each paper (batch — first 5 only to stay fast)
    const repoPromises = papers.slice(0, 5).map(async (paper, idx) => {
      if (!paper.source_specific.pwc_id) return;
      try {
        const repoResp = await fetch(`${PWC_API}/papers/${paper.source_specific.pwc_id}/repositories/`);
        if (repoResp.ok) {
          const repoData = await repoResp.json();
          papers[idx].code_repos = (repoData.results || []).slice(0, 3).map(r => ({
            url: r.url || '',
            stars: r.stars || 0,
            framework: r.framework || 'unknown'
          }));
        }
      } catch { /* skip repo fetch failures */ }
    });
    await Promise.all(repoPromises);

    return {
      success: true,
      query,
      source: 'papers_with_code',
      result_count: papers.length,
      results: papers,
      meta: {
        timestamp: new Date().toISOString(),
        api_version: 'paperswithcode-v1',
        total_available: data.count || papers.length
      }
    };
  } catch (error) {
    return { success: false, error: error.message, source: 'papers_with_code' };
  }
}

async function getMethodDetails(methodId) {
  try {
    const response = await fetch(`${PWC_API}/methods/${encodeURIComponent(methodId)}/`);
    if (!response.ok) {
      return { success: false, error: `PwC API returned HTTP ${response.status}`, source: 'papers_with_code' };
    }
    const method = await response.json();
    return {
      success: true,
      source: 'papers_with_code',
      method: {
        name: method.name || '',
        full_name: method.full_name || '',
        description: method.description || '',
        paper: method.paper?.title || '',
        paper_url: method.paper?.url_abs || '',
        category: method.main_collection?.name || '',
        area: method.main_collection?.area?.name || ''
      },
      meta: { timestamp: new Date().toISOString(), api_version: 'paperswithcode-v1' }
    };
  } catch (error) {
    return { success: false, error: error.message, source: 'papers_with_code' };
  }
}

// CLI
const args = process.argv.slice(2);

if (args.length === 0 || args[0] === '--help') {
  console.log(JSON.stringify({
    success: false,
    error: 'Usage: search <query> [maxResults] [--method=<methodId>]'
  }, null, 2));
  process.exit(1);
}

const methodArg = args.find(a => a.startsWith('--method='));
if (methodArg) {
  getMethodDetails(methodArg.split('=')[1]).then(result => {
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.success ? 0 : 1);
  });
} else {
  const query = args[0];
  let maxResults = 10;
  for (let i = 1; i < args.length; i++) {
    if (!isNaN(parseInt(args[i], 10))) maxResults = parseInt(args[i], 10);
  }
  searchPapers(query, maxResults).then(result => {
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.success ? 0 : 1);
  });
}
```

**Step 2: Write the bash wrapper**

Create `research-assistant/skills/papers-with-code-search/scripts/search`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$1" in
    --path|--location|--where) echo "${SCRIPT_DIR}/search"; exit 0 ;;
    --script-dir) echo "$SCRIPT_DIR"; exit 0 ;;
esac
node "${SCRIPT_DIR}/search.mjs" "$@"
```

**Step 3: Make scripts executable**

```bash
chmod +x research-assistant/skills/papers-with-code-search/scripts/search
chmod +x research-assistant/skills/papers-with-code-search/scripts/search.mjs
```

**Step 4: Test the script**

```bash
node research-assistant/skills/papers-with-code-search/scripts/search.mjs "vision transformer" 3
```

Expected: JSON with `success: true`, `source: "papers_with_code"`, results with `code_repos` arrays populated (at least for top results), `source_specific.tasks` and `source_specific.methods`.

**Step 5: Write the SKILL.md**

Create `research-assistant/skills/papers-with-code-search/SKILL.md`:

```markdown
---
name: papers-with-code-search
description: Search Papers With Code for papers linked to implementations, benchmarks, and datasets. Use when Claude needs to find code for a method, compare benchmark performance, or identify the reference implementation of a technique.
keywords: [papers-with-code, implementations, benchmarks, code, github, methods, datasets, reproducibility]
---

# Papers With Code Search

Search papers linked to code repos, benchmarks, and methods taxonomy. No API key required.

Two modes:
1. **Search** — find papers with associated code
2. **Method** — get details on a specific ML method

## Usage

```bash
SCRIPT=$(find ~/.claude/plugins -path "*/research-assistant/skills/papers-with-code-search/scripts/search.mjs" 2>/dev/null | head -1)

# Search mode
node "$SCRIPT" "your query" [maxResults]

# Method detail mode
node "$SCRIPT" --method=<methodId>
```

## When to Use

- Finding reference implementations for a method (code + framework + stars)
- Comparing methods on benchmarks
- Checking if a paper has available code before recommending it
- Understanding the methods taxonomy (what family a technique belongs to)
- Finding datasets used for evaluating a method

## Key Fields

- `results[].code_repos` — GitHub repos with stars count and framework
- `results[].source_specific.tasks` — ML tasks this paper addresses
- `results[].source_specific.methods` — methods used in the paper
- Method mode: `method.description`, `method.category`, `method.area`

## Examples

```bash
# Find implementations of LoRA
node "$SCRIPT" "low-rank adaptation LoRA" 10

# Search for SOTA object detection
node "$SCRIPT" "object detection transformer" 5

# Get details on a specific method
node "$SCRIPT" --method=lora
```
```

**Step 6: Commit**

```bash
cd research-assistant
git add skills/papers-with-code-search/
git commit -m "feat: add papers-with-code-search skill with method details"
git push origin main
```

---

## Task 5: Routing Skill (using-research-assistant)

**Files:**
- Create: `research-assistant/skills/using-research-assistant/SKILL.md`

**Step 1: Write the routing SKILL.md**

Create `research-assistant/skills/using-research-assistant/SKILL.md`:

```markdown
---
name: using-research-assistant
description: Research assistant plugin — gives Claude and agents access to latest scientific research across arXiv, Semantic Scholar, and Papers With Code. Use when needing SOTA methods, research consensus, or implementation guidance from academic literature.
keywords: [research, papers, SOTA, literature-review, methods, AI, machine-learning, foundation-models]
---

# Research Assistant

You have access to deep research intelligence via three data sources and three synthesis agents. No API keys required.

## Decision Tree

When you encounter these situations, use the appropriate tool:

### Need to understand what the field knows
**Agent:** `literature-reviewer`
**Triggers:** "What's the SOTA for X?", "Survey of approaches to X", "What does the research say about X?"
**Returns:** CONSENSUS, FRONTIER, OPEN QUESTIONS, KEY PAPERS, METHOD TAXONOMY

### Need to choose between approaches
**Agent:** `method-analyst`
**Triggers:** "Should I use X or Y?", "Compare methods for Z", "Tradeoffs between approaches"
**Returns:** COMPARISON MATRIX, RECOMMENDATION, IMPLEMENTATION NOTES

### Need to implement a research method
**Agent:** `implementation-guide`
**Triggers:** "How to implement X from paper Y?", "Code for method Z", "Architecture of approach X"
**Returns:** CORE ALGORITHM, ARCHITECTURE, REFERENCE IMPLEMENTATIONS, ADAPTATION GUIDE

### Quick lookups (skip agents, use skills directly)

| Need | Skill | Example |
|------|-------|---------|
| Bleeding-edge preprints | `arxiv-search` | Latest papers on speculative decoding |
| Citations + TLDRs + impact | `semantic-scholar-search` | How influential is paper X? |
| Code implementations | `papers-with-code-search` | Find PyTorch impl of method X |

## When NOT to Use

- API docs, library usage, tutorials → use web search or documentation skills
- Common engineering knowledge → not a research question
- Debugging errors → use debugging tools
- Recent news or announcements → use perplexity

## How Skills Return Data

All retrieval skills return a unified JSON envelope with:
- `results[].title`, `authors`, `year`, `abstract`, `tldr`
- `results[].pdf_url`, `url`, `citations`
- `results[].code_repos` — GitHub repos with stars and framework
- `results[].key_methods` — extracted method names

Agents return structured markdown sections optimized for reasoning.
```

**Step 2: Commit**

```bash
cd research-assistant
git add skills/using-research-assistant/
git commit -m "feat: add routing skill for research-assistant"
git push origin main
```

---

## Task 6: Synthesis Agents

**Files:**
- Create: `research-assistant/agents/literature-reviewer.md`
- Create: `research-assistant/agents/method-analyst.md`
- Create: `research-assistant/agents/implementation-guide.md`

**Step 1: Write literature-reviewer agent**

Create `research-assistant/agents/literature-reviewer.md`:

```markdown
---
name: literature-reviewer
description: Conducts multi-source literature review producing structured knowledge synthesis. Use when Claude needs to understand what a research field knows about a topic — consensus, frontier, open questions, and key papers.
tools: Bash, Read, Grep, Glob
model: sonnet
---

You are a literature review agent. Your job is to search academic sources, synthesize findings, and produce a structured knowledge report that another Claude agent can reason over.

## Workflow

1. **Search all three sources in parallel:**
   - Find the arxiv-search script: `ARXIV=$(find ~/.claude/plugins -path "*/research-assistant/skills/arxiv-search/scripts/search.mjs" 2>/dev/null | head -1)`
   - Find the semantic-scholar script: `S2=$(find ~/.claude/plugins -path "*/research-assistant/skills/semantic-scholar-search/scripts/search.mjs" 2>/dev/null | head -1)`
   - Find the papers-with-code script: `PWC=$(find ~/.claude/plugins -path "*/research-assistant/skills/papers-with-code-search/scripts/search.mjs" 2>/dev/null | head -1)`
   - Run all three: `node "$ARXIV" "<query>" 15 --sort=date`, `node "$S2" "<query>" 15`, `node "$PWC" "<query>" 10`

2. **Deduplicate** papers across sources by matching titles (case-insensitive, strip punctuation).

3. **Rank** by composite signal: papers that are recent (last 2 years), highly cited, AND have code available rank highest.

4. **Synthesize** into the structured output format below.

## Output Format (REQUIRED — all sections mandatory)

```
## CONSENSUS
[2-5 bullet points of what the field broadly agrees on. Cite specific papers.]

## FRONTIER
[2-5 bullet points of the most recent developments not yet established as consensus. Focus on papers from last 12 months.]

## OPEN QUESTIONS
[2-4 bullet points of what remains unsolved or actively debated.]

## KEY PAPERS
[Ranked list of 5-10 most important papers:]
1. **Title** (Year) — [why it matters]. Citations: N. Code: yes/no.
2. ...

## METHOD TAXONOMY
[Tree structure of approaches in this area:]
- Family A
  - Method A1 (paper, year)
  - Method A2 (paper, year)
- Family B
  - Method B1 (paper, year)

## APPLICABILITY
[2-3 bullet points on how this research connects to practical implementation. What should an engineer building with these methods know?]
```

## Rules

- Always search all three sources. Do not skip any.
- If a source returns an error, note it and continue with available data.
- Prefer TLDRs from Semantic Scholar for quick paper summaries.
- Include arxiv_id or DOI when available for traceability.
- Be precise about what is consensus vs frontier vs speculation.
- Every claim must reference at least one paper.
```

**Step 2: Write method-analyst agent**

Create `research-assistant/agents/method-analyst.md`:

```markdown
---
name: method-analyst
description: Deep comparison of specific methods or architectures. Use when Claude needs to decide which approach to use — produces structured tradeoff analysis with recommendation.
tools: Bash, Read, Grep, Glob
model: sonnet
---

You are a method analysis agent. Your job is to compare 2-5 specific methods or architectures and produce a structured comparison that helps another Claude agent make an informed decision.

## Workflow

1. **Identify the methods** to compare from the input.

2. **Search for each method** using all available sources:
   - Find scripts: `ARXIV=$(find ~/.claude/plugins -path "*/research-assistant/skills/arxiv-search/scripts/search.mjs" 2>/dev/null | head -1)`
   - Similarly for S2 and PWC scripts.
   - For each method, search Semantic Scholar for citation data and TLDRs.
   - Search Papers With Code for implementations and benchmarks.

3. **Build the comparison matrix** based on retrieved data.

4. **Produce recommendation** based on the specific context provided.

## Output Format (REQUIRED — all sections mandatory)

```
## METHODS COMPARED
- **Method A**: One-line description. Original paper (year).
- **Method B**: One-line description. Original paper (year).

## COMPARISON MATRIX
| Dimension        | Method A        | Method B        |
|-----------------|-----------------|-----------------|
| Core mechanism  | ...             | ...             |
| Strengths       | ...             | ...             |
| Limitations     | ...             | ...             |
| Compute cost    | low/med/high    | low/med/high    |
| Data needs      | ...             | ...             |
| Code available  | yes (URL) / no  | yes (URL) / no  |
| Citations       | N               | N               |
| Best for        | ...             | ...             |

## RECOMMENDATION
[Given the context provided, which method to use and why. Be specific about the conditions under which each method excels.]

## IMPLEMENTATION NOTES
[Practical considerations: library support, common pitfalls, scaling behavior, compatibility with common frameworks.]
```

## Rules

- Search all three sources for each method being compared.
- If methods are variations of the same family, note the lineage.
- Be honest about what the data shows — do not inflate weak methods.
- The recommendation must consider the user's specific context if provided.
- Include code availability — this is critical for practical adoption.
```

**Step 3: Write implementation-guide agent**

Create `research-assistant/agents/implementation-guide.md`:

```markdown
---
name: implementation-guide
description: Bridges from research paper to actionable implementation guidance. Use when Claude has identified an approach and needs to understand how to implement it — produces pseudocode, architecture, and adaptation guide.
tools: Bash, Read, Grep, Glob
model: sonnet
---

You are an implementation guide agent. Your job is to take a research paper or method and produce actionable implementation guidance that another Claude agent can use to write code.

## Workflow

1. **Find the paper** using available sources:
   - Find scripts: `S2=$(find ~/.claude/plugins -path "*/research-assistant/skills/semantic-scholar-search/scripts/search.mjs" 2>/dev/null | head -1)`
   - Similarly for PWC script.
   - Search Semantic Scholar for paper details and abstract.
   - Search Papers With Code for implementations and method taxonomy.

2. **Gather implementation details:**
   - If code repos exist, note the top repos by stars.
   - Identify the framework (PyTorch, TensorFlow, JAX, etc.).
   - Check for related methods that might be easier to implement.

3. **Produce the implementation guide** based on abstract, TLDRs, and available code.

## Output Format (REQUIRED — all sections mandatory)

```
## PAPER
**Title** (Year) by Authors.
Summary: [one sentence from TLDR or abstract].

## CORE ALGORITHM
[Step-by-step pseudocode extracted from the paper's methodology. Number each step.]
1. ...
2. ...
3. ...

## ARCHITECTURE
[Components and data flow:]
- Component A: [purpose, inputs, outputs]
- Component B: [purpose, inputs, outputs]
- Data flow: A -> B -> C

## REFERENCE IMPLEMENTATIONS
[Ranked by stars:]
1. **repo-url** — Framework: PyTorch. Stars: 1200. Key files: `model.py`, `train.py`.
2. ...
(If no code available: "No public implementations found. See ADAPTATION GUIDE for implementation from scratch.")

## ADAPTATION GUIDE
[How to adapt this to the user's problem:]
- What to keep as-is from the paper
- What to modify for the specific use case
- Common adaptations and their tradeoffs

## DEPENDENCIES & REQUIREMENTS
- Libraries: [specific packages and versions]
- Compute: [GPU requirements, training time estimates if available]
- Data: [dataset requirements, preprocessing needs]

## PITFALLS
[Common implementation mistakes:]
1. [Pitfall]: [how to avoid it]
2. ...
```

## Rules

- Always check Papers With Code for existing implementations first.
- If code exists, prioritize repos with most stars and active maintenance.
- Pseudocode should be language-agnostic but lean toward Python conventions.
- Be honest about what can be inferred from abstracts vs what requires reading the full paper.
- If the method is complex, note which parts are most error-prone.
```

**Step 4: Commit**

```bash
cd research-assistant
git add agents/
git commit -m "feat: add synthesis agents — literature-reviewer, method-analyst, implementation-guide"
git push origin main
```

---

## Task 7: Validation Hooks

**Files:**
- Create: `research-assistant/hooks/hooks.json`
- Create: `research-assistant/hooks/validate-research-output.py`
- Create: `research-assistant/hooks/validate-synthesis-output.py`

**Step 1: Write hooks.json**

Create `research-assistant/hooks/hooks.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/validate-research-output.py",
            "timeout": 5000
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "literature-reviewer|method-analyst|implementation-guide",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/validate-synthesis-output.py",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

**Step 2: Write validate-research-output.py**

Create `research-assistant/hooks/validate-research-output.py`:

```python
#!/usr/bin/env python3
"""
PostToolUse hook: validates research-assistant JSON output from Bash calls.
- Checks for research-assistant JSON signature
- Validates structure
- Truncates oversized abstracts
- Strips HTML artifacts
Exit 0 = valid research output (passes through)
Exit 1 = not research output (ignored by hook system)
Exit 2 = malformed research output (blocks, Claude sees error)
"""

import json
import sys
import re

def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(1)  # Not JSON input, ignore

    tool_output = hook_input.get("tool_output", "")
    if not tool_output:
        sys.exit(1)  # No output, ignore

    # Check if this is research-assistant output
    if '"source"' not in tool_output:
        sys.exit(1)  # Not research output

    valid_sources = ["arxiv", "semantic_scholar", "papers_with_code"]
    is_research = False
    for src in valid_sources:
        if f'"source": "{src}"' in tool_output or f'"source":"{src}"' in tool_output:
            is_research = True
            break

    if not is_research:
        sys.exit(1)  # Not our output, ignore

    # Parse and validate
    try:
        data = json.loads(tool_output)
    except json.JSONDecodeError:
        print("Research output is malformed JSON", file=sys.stderr)
        sys.exit(2)

    if not isinstance(data, dict):
        print("Research output must be a JSON object", file=sys.stderr)
        sys.exit(2)

    if "success" not in data:
        print("Research output missing 'success' field", file=sys.stderr)
        sys.exit(2)

    # Valid research output
    sys.exit(0)

if __name__ == "__main__":
    main()
```

**Step 3: Write validate-synthesis-output.py**

Create `research-assistant/hooks/validate-synthesis-output.py`:

```python
#!/usr/bin/env python3
"""
SubagentStop hook: validates synthesis agent structured output.
Checks that required sections are present for each agent type.
Exit 0 = all required sections present
Exit 2 = missing sections (blocks stop, agent retries)
"""

import json
import sys

REQUIRED_SECTIONS = {
    "literature-reviewer": ["CONSENSUS", "FRONTIER", "KEY PAPERS"],
    "method-analyst": ["COMPARISON MATRIX", "RECOMMENDATION"],
    "implementation-guide": ["CORE ALGORITHM", "REFERENCE IMPLEMENTATIONS"]
}

def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)  # Can't parse, let it through

    agent_name = hook_input.get("agent_name", "")
    agent_output = hook_input.get("tool_output", "") or hook_input.get("output", "")

    if agent_name not in REQUIRED_SECTIONS:
        sys.exit(0)  # Not our agent, pass through

    required = REQUIRED_SECTIONS[agent_name]
    missing = [section for section in required if f"## {section}" not in agent_output]

    if missing:
        msg = f"Agent '{agent_name}' output missing required sections: {', '.join(missing)}. Please include all required sections."
        print(msg, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)

if __name__ == "__main__":
    main()
```

**Step 4: Make hook scripts executable**

```bash
chmod +x research-assistant/hooks/validate-research-output.py
chmod +x research-assistant/hooks/validate-synthesis-output.py
```

**Step 5: Test hooks**

```bash
# Test research output validator (positive case)
echo '{"tool_output": "{\"success\": true, \"source\": \"arxiv\", \"results\": []}"}' | python3 research-assistant/hooks/validate-research-output.py
echo "Exit code: $?"
# Expected: Exit code: 0

# Test research output validator (not research output)
echo '{"tool_output": "hello world"}' | python3 research-assistant/hooks/validate-research-output.py
echo "Exit code: $?"
# Expected: Exit code: 1

# Test synthesis validator (positive case)
echo '{"agent_name": "literature-reviewer", "tool_output": "## CONSENSUS\nstuff\n## FRONTIER\nstuff\n## KEY PAPERS\nstuff"}' | python3 research-assistant/hooks/validate-synthesis-output.py
echo "Exit code: $?"
# Expected: Exit code: 0

# Test synthesis validator (missing sections)
echo '{"agent_name": "literature-reviewer", "tool_output": "## CONSENSUS\nstuff"}' | python3 research-assistant/hooks/validate-synthesis-output.py
echo "Exit code: $?"
# Expected: Exit code: 2
```

**Step 6: Commit**

```bash
cd research-assistant
git add hooks/
git commit -m "feat: add validation hooks for research output and synthesis quality"
git push origin main
```

---

## Task 8: Documentation (CLAUDE.md, CONTEXT, README)

**Files:**
- Create: `research-assistant/CLAUDE.md`
- Create: `research-assistant/CONTEXT_research-assistant.md`
- Create: `research-assistant/README.md`

**Step 1: Write CLAUDE.md**

Create `research-assistant/CLAUDE.md`:

```markdown
# research-assistant — Developer Instructions

## Overview
Research intelligence plugin for Claude Code. Skills-first architecture with 3 free APIs, 3 synthesis agents, 2 validation hooks.

## Structure
- `skills/` — 4 skills (1 router + 3 retrieval with Node.js scripts)
- `agents/` — 3 synthesis agents (literature-reviewer, method-analyst, implementation-guide)
- `hooks/` — hooks.json auto-discovered, 2 Python validators

## Key Rules
- **No API keys required** — all APIs are free
- **hooks/hooks.json is auto-discovered** — never add "hooks" to plugin.json
- **Scripts use Node 18+ built-in fetch()** — zero dependencies
- **Output follows unified JSON envelope** — see design doc for schema

## Testing
```bash
# Test retrieval skills
node skills/arxiv-search/scripts/search.mjs "test query" 3
node skills/semantic-scholar-search/scripts/search.mjs "test query" 3
node skills/papers-with-code-search/scripts/search.mjs "test query" 3

# Test hooks
echo '{"tool_output": "{\"success\": true, \"source\": \"arxiv\", \"results\": []}"}' | python3 hooks/validate-research-output.py
```

## Versioning
- Bump version in `.claude-plugin/plugin.json`
- Push to main — webhook auto-updates marketplace
```

**Step 2: Write CONTEXT_research-assistant.md**

Create `research-assistant/CONTEXT_research-assistant.md`:

```markdown
# CONTEXT: research-assistant

## Architecture
Skills-first plugin. No MCP server (avoids 5k+ idle context tokens).

### Retrieval Layer
| Skill | API | Key Feature |
|-------|-----|-------------|
| arxiv-search | arXiv Atom API | Bleeding-edge preprints, sort by date |
| semantic-scholar-search | S2 Graph API | TLDRs, citation graphs, influence |
| papers-with-code-search | PwC API | Code repos, benchmarks, methods |

All return unified JSON envelope. Zero API keys.

### Synthesis Layer
| Agent | Trigger | Output |
|-------|---------|--------|
| literature-reviewer | "What's the SOTA?" | CONSENSUS, FRONTIER, KEY PAPERS |
| method-analyst | "Which method?" | COMPARISON MATRIX, RECOMMENDATION |
| implementation-guide | "How to implement?" | CORE ALGORITHM, REFERENCE IMPLEMENTATIONS |

### Validation Layer
- PostToolUse hook validates research JSON from Bash
- SubagentStop hook ensures agents produce required sections

## Data Flow
```
User/Agent question
    ↓
using-research-assistant (routing skill)
    ↓ routes to
Agent OR direct skill invocation
    ↓
Agent runs retrieval skills via Bash
    ↓
PostToolUse hook validates JSON
    ↓
Agent synthesizes structured output
    ↓
SubagentStop hook validates sections
    ↓
Structured knowledge returned to caller
```

## Design Decisions
1. **Skills over MCP** — context efficiency, Anthropic's recommended approach
2. **Unified JSON envelope** — agents consume any source interchangeably
3. **Agent synthesis** — the value is understanding, not just search
4. **LLM-optimized output** — structured sections, not prose
5. **Free APIs only** — zero friction, no setup required
```

**Step 3: Write README.md**

Create `research-assistant/README.md`:

```markdown
# Research Assistant

> Deep research intelligence for Claude Code — access, understand, and apply SOTA scientific research.

A Claude Code plugin that gives Claude and agents structured access to the scientific research frontier. Optimized for LLM consumption: structured synthesis, not raw search results.

## Features

- **3 Data Sources** — arXiv, Semantic Scholar, Papers With Code (all free, no API keys)
- **3 Synthesis Agents** — literature review, method comparison, implementation guidance
- **LLM-Optimized Output** — structured sections Claude can reason over
- **Zero Config** — no API keys, no setup, just install and use

## Install

```bash
claude plugin marketplace add flight505/flight505-marketplace
claude plugin install research-assistant
```

## Skills

| Skill | Purpose |
|-------|---------|
| `arxiv-search` | Search arXiv preprints (cs.AI, cs.LG, cs.CL, cs.CV, stat.ML) |
| `semantic-scholar-search` | Search 200M+ papers with TLDRs, citations, influence scores |
| `papers-with-code-search` | Find papers with code implementations and benchmarks |

## Agents

| Agent | Use When |
|-------|----------|
| `literature-reviewer` | "What does the field know about X?" |
| `method-analyst` | "Should I use method X or Y?" |
| `implementation-guide` | "How do I implement X from this paper?" |

## How It Works

Claude automatically knows when to use research tools via the routing skill. When Claude encounters a research question, it:

1. **Routes** to the appropriate agent or skill
2. **Searches** across multiple academic sources
3. **Synthesizes** findings into structured knowledge
4. **Returns** LLM-optimized output for reasoning

## Requirements

- Claude Code CLI
- Node.js 18+ (for built-in `fetch()`)
- Python 3 (for hook validators)

## License

MIT
```

**Step 4: Commit**

```bash
cd research-assistant
git add CLAUDE.md CONTEXT_research-assistant.md README.md
git commit -m "docs: add CLAUDE.md, CONTEXT, and README"
git push origin main
```

---

## Task 9: Marketplace Integration

**Files:**
- Modify: `.claude-plugin/marketplace.json` — add research-assistant entry, bump version
- Modify: `scripts/validate-plugin-manifests.sh` — add research-assistant (2 locations)
- Modify: `scripts/bump-plugin-version.sh` — add research-assistant (3 locations)
- Modify: `scripts/setup-webhooks.sh` — add research-assistant (1 location)
- Modify: `scripts/plugin-doctor.sh` — add research-assistant (1 location)
- Modify: `scripts/dev-test.sh` — add research-assistant (1 location)
- Modify: `scripts/test-marketplace-integration.sh` — add research-assistant (2 locations)
- Modify: `.github/workflows/auto-update-plugins.yml` — add research-assistant (3 locations)

**Step 1: Add to marketplace.json**

Add to the `plugins` array in `.claude-plugin/marketplace.json`:
```json
{
  "name": "research-assistant",
  "description": "Deep research intelligence for Claude — SOTA papers, method analysis, and implementation guidance from arXiv, Semantic Scholar, and Papers With Code",
  "version": "1.0.0",
  "author": {
    "name": "Jesper Vang",
    "url": "https://github.com/flight505"
  },
  "source": "./research-assistant",
  "category": "research",
  "keywords": [
    "research",
    "arxiv",
    "semantic-scholar",
    "papers-with-code",
    "literature-review",
    "ai-research"
  ]
}
```

Bump marketplace version from `"1.4.16"` to `"1.5.0"` (new plugin = minor bump).

Update marketplace description to mention Research Assistant.

**Step 2: Update validate-plugin-manifests.sh**

Add to `get_plugin_dir()` case statement:
```bash
"research-assistant") echo "research-assistant" ;;
```

Add to the for loop:
```bash
for plugin_name in "sdk-bridge" "taskplex" "storybook-assistant" "claude-project-planner" "nano-banana" "research-assistant"; do
```

**Step 3: Update bump-plugin-version.sh**

Add to usage help:
```bash
echo "  - research-assistant"
```

Add to case statement:
```bash
"research-assistant")
  PLUGIN_DIR="research-assistant"
  PLUGIN_JSON="research-assistant/.claude-plugin/plugin.json"
  ;;
```

Update error message:
```bash
echo "Valid plugins: sdk-bridge, taskplex, claude-project-planner, storybook-assistant, nano-banana, research-assistant"
```

**Step 4: Update setup-webhooks.sh**

Add to PLUGINS array:
```bash
"research-assistant"
```

**Step 5: Update plugin-doctor.sh**

Add to PLUGINS array:
```bash
PLUGINS=("sdk-bridge" "taskplex" "storybook-assistant" "claude-project-planner" "nano-banana" "research-assistant")
```

**Step 6: Update dev-test.sh**

Add to AVAILABLE_PLUGINS array:
```bash
AVAILABLE_PLUGINS=("sdk-bridge" "taskplex" "storybook-assistant" "claude-project-planner" "nano-banana" "research-assistant")
```

**Step 7: Update test-marketplace-integration.sh**

Add to PLUGINS array:
```bash
PLUGINS=("sdk-bridge" "taskplex" "storybook-assistant" "nano-banana" "claude-project-planner" "research-assistant")
```

Add to `get_test_command` case:
```bash
research-assistant)
    echo "/research-assistant:arxiv-search --help"
    ;;
```

**Step 8: Update auto-update-plugins.yml**

Add `research-assistant` to both for loops (lines 77 and 109):
```bash
for submodule in nano-banana claude-project-planner storybook-assistant sdk-bridge taskplex research-assistant; do
```

Add to case statement:
```bash
"research-assistant")
  PLUGIN_NAME="research-assistant"
  ;;
```

**Step 9: Run validation**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
./scripts/validate-plugin-manifests.sh
```

Expected: All 6 plugins pass validation, including research-assistant.

**Step 10: Commit marketplace changes**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
git add .claude-plugin/marketplace.json scripts/ .github/workflows/auto-update-plugins.yml research-assistant
git commit -m "feat: add research-assistant to marketplace (6th plugin)"
```

---

## Task 10: Webhook Setup & CLAUDE.md Updates

**Files:**
- Create: `research-assistant/.github/workflows/notify-marketplace.yml`
- Modify: `CLAUDE.md` — update plugin count and tracking table

**Step 1: Copy webhook workflow template**

```bash
mkdir -p research-assistant/.github/workflows
cp templates/notify-marketplace.yml research-assistant/.github/workflows/notify-marketplace.yml
```

**Step 2: Commit webhook in plugin repo**

```bash
cd research-assistant
git add .github/workflows/notify-marketplace.yml
git commit -m "feat: add marketplace webhook notification"
git push origin main
```

**Step 3: Add MARKETPLACE_UPDATE_TOKEN secret**

```bash
gh secret set MARKETPLACE_UPDATE_TOKEN --repo flight505/research-assistant
```

(User will be prompted to paste the GitHub PAT)

**Step 4: Update marketplace CLAUDE.md**

Update the Plugin Tracking table to include research-assistant:
```markdown
| **research-assistant** | 1.0.0 | [github.com/flight505/research-assistant](https://github.com/flight505/research-assistant) | ✅ Active |
```

Update plugin count references from 5 to 6.

Update marketplace description mentioning 6 plugins.

**Step 5: Run full validation**

```bash
./scripts/validate-plugin-manifests.sh
./scripts/plugin-doctor.sh
```

**Step 6: Commit CLAUDE.md updates**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for research-assistant (6 plugins)"
```

---

## Task 11: End-to-End Testing

**Step 1: Test each retrieval skill standalone**

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK/flight505-marketplace

# arXiv
node research-assistant/skills/arxiv-search/scripts/search.mjs "transformer attention" 3
# Verify: success=true, 3 results with titles, abstracts, pdf_urls

# Semantic Scholar
node research-assistant/skills/semantic-scholar-search/scripts/search.mjs "RLHF reinforcement learning" 3
# Verify: success=true, results with tldr fields, citation counts

# Papers With Code
node research-assistant/skills/papers-with-code-search/scripts/search.mjs "vision transformer" 3
# Verify: success=true, results with code_repos arrays
```

**Step 2: Test hooks**

```bash
# Research output validator - positive
echo '{"tool_output":"{\"success\":true,\"source\":\"arxiv\",\"results\":[]}"}' | python3 research-assistant/hooks/validate-research-output.py; echo "Exit: $?"
# Expected: Exit: 0

# Research output validator - not research
echo '{"tool_output":"hello"}' | python3 research-assistant/hooks/validate-research-output.py; echo "Exit: $?"
# Expected: Exit: 1

# Synthesis validator - positive
echo '{"agent_name":"method-analyst","tool_output":"## COMPARISON MATRIX\ndata\n## RECOMMENDATION\ndata"}' | python3 research-assistant/hooks/validate-synthesis-output.py; echo "Exit: $?"
# Expected: Exit: 0

# Synthesis validator - missing sections
echo '{"agent_name":"method-analyst","tool_output":"## COMPARISON MATRIX\ndata"}' | python3 research-assistant/hooks/validate-synthesis-output.py; echo "Exit: $?"
# Expected: Exit: 2
```

**Step 3: Validate marketplace integration**

```bash
./scripts/validate-plugin-manifests.sh
```

Expected: All 6 plugins pass.

**Step 4: Test plugin validation via CLI**

```bash
claude plugin validate research-assistant
```

Expected: Valid plugin with 4 skills, 3 agents, hooks detected.

**Step 5: Final commit if any fixes needed**

```bash
git add -A && git commit -m "fix: address issues found during e2e testing"
```

---

## Task Summary

| Task | Description | Files | Depends On |
|------|-------------|-------|------------|
| 1 | GitHub repo + submodule scaffold | plugin.json, .gitignore, LICENSE | — |
| 2 | arXiv search skill | SKILL.md + scripts/ | 1 |
| 3 | Semantic Scholar search skill | SKILL.md + scripts/ | 1 |
| 4 | Papers With Code search skill | SKILL.md + scripts/ | 1 |
| 5 | Routing skill | SKILL.md | 1 |
| 6 | Synthesis agents (3) | agents/*.md | 1 |
| 7 | Validation hooks (2) | hooks/ | 1 |
| 8 | Documentation | CLAUDE.md, CONTEXT, README | 2-7 |
| 9 | Marketplace integration | 8 files updated | 1-8 |
| 10 | Webhook + CLAUDE.md | workflow + docs | 9 |
| 11 | End-to-end testing | — | 1-10 |

**Parallelizable:** Tasks 2, 3, 4, 5, 6, 7 can all run in parallel after Task 1.
