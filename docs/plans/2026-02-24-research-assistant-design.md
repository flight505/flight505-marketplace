# Research Assistant Plugin — Design Document

**Date:** 2026-02-24
**Author:** Jesper Vang (@flight505)
**Status:** Approved
**Plugin:** research-assistant v1.0.0
**Marketplace:** flight505-marketplace

---

## Problem

Claude and agents lack structured access to the scientific research frontier. When working on tasks involving SOTA methods (e.g., building a ReAct harness, implementing a new attention mechanism, choosing between training approaches), Claude has no way to:

1. Discover what the field currently knows and agrees on
2. Compare methods with structured tradeoff analysis
3. Bridge from paper to actionable implementation guidance

Perplexity provides general web search. This plugin provides **deep research intelligence** — structured, synthesized, LLM-optimized knowledge from academic literature.

## Philosophy

**The plugin's job is not "search for papers." It's "make Claude understand the frontier."**

Every skill and agent formats output for LLM consumption — structured sections, explicit relationships, clear hierarchies. Not human-readable prose, but information architecture Claude can reason over.

Three layers:

| Layer | Purpose | Mechanism |
|-------|---------|-----------|
| Retrieval | Get papers, metadata, code | Skills with scripts calling free APIs |
| Synthesis | Understand and contextualize | Agents doing multi-step research |
| Formatting | LLM-optimized presentation | Structured schemas in every prompt |

## Architecture: Skills + Scripts + Agents (No MCP)

**Why no MCP server:**

- MCP servers load tool definitions into context every request, even when idle (5k+ tokens)
- Skills load only frontmatter at session start; full content loads on-demand
- Anthropic's guidance: skills for 80% of needs, MCP only for deterministic external service integration
- Our APIs are simple HTTP calls — scripts handle them without MCP overhead

**Why agents, not just skills:**

- Search is commoditized. Synthesis is the value.
- Agents provide context isolation for multi-step research workflows
- Agent prompts enforce structured output formats
- Agents compose: literature review -> method analysis -> implementation guide

## Data Sources

### arXiv API
- **Access:** Free, no API key, Atom XML feed
- **Coverage:** cs.AI, cs.LG, cs.CL, cs.CV, stat.ML, cs.MA
- **Strengths:** Bleeding-edge preprints, newest work before peer review
- **Rate limit:** Reasonable use, no hard limit documented

### Semantic Scholar Academic Graph API
- **Access:** Free, no key for 100 req/sec
- **Coverage:** 200M+ papers across all fields
- **Strengths:** Citation graphs, influence scores, AI-generated TLDRs, related papers
- **Key endpoints:** `/paper/search`, `/paper/{id}`, `/paper/{id}/citations`, `/paper/{id}/references`

### Papers With Code API
- **Access:** Free, no key
- **Coverage:** ML/AI papers linked to code, benchmarks, datasets
- **Strengths:** Implementation bridge — links papers to GitHub repos, benchmark results, methods taxonomy

### No API Keys Required

All three APIs are free and keyless. Zero setup friction. Major advantage over paid alternatives.

## Retrieval Skills (4 total)

### `using-research-assistant` (routing skill)

Auto-loads at session start. Decision tree that tells Claude when and how to use research tools:

- "What's the SOTA for X?" -> literature-reviewer agent
- "Which method for X vs Y?" -> method-analyst agent
- "How to implement X from paper Y?" -> implementation-guide agent
- Quick paper lookup -> semantic-scholar-search skill
- Bleeding-edge preprints -> arxiv-search skill
- Find code for a method -> papers-with-code-search skill

Does NOT trigger for: API docs, library tutorials, debugging, common engineering knowledge.

### `arxiv-search`

Script-based skill. Node.js fetches arXiv Atom API, parses XML, returns structured JSON.

**Supports:** Natural language query, category filter, max results, sort by date or relevance.

### `semantic-scholar-search`

Script-based skill. Node.js fetches Semantic Scholar API, returns structured JSON with TLDRs, citation data, influence scores.

**Supports:** Natural language query, max results, fields filter, year range, open access filter.

### `papers-with-code-search`

Script-based skill. Node.js fetches Papers With Code API, returns structured JSON with code repos, benchmarks, methods.

**Supports:** Natural language query, max results.

### Unified Output Schema

All retrieval skills return the same envelope:

```json
{
  "query": "original query",
  "source": "arxiv|semantic_scholar|papers_with_code",
  "result_count": 10,
  "results": [
    {
      "title": "...",
      "authors": ["..."],
      "year": 2026,
      "abstract": "...",
      "tldr": "...",
      "url": "...",
      "pdf_url": "...",
      "citations": 42,
      "code_repos": [{"url": "...", "stars": 1200, "framework": "pytorch"}],
      "relevance_score": 0.95,
      "key_methods": ["ReAct", "chain-of-thought"],
      "source_specific": {}
    }
  ],
  "meta": {
    "timestamp": "...",
    "api_version": "..."
  }
}
```

Consistent envelope means agents consume results from any source interchangeably.

## Synthesis Agents (3 total)

### `literature-reviewer`

**Trigger:** Claude needs to understand what the field knows about a topic.

**Workflow:**
1. Runs all three retrieval skills in parallel
2. Deduplicates papers across sources (title similarity + DOI)
3. Ranks by composite signal: recency x citation influence x has-code
4. Reads top-N papers (abstracts + TLDRs), identifies themes
5. Produces structured synthesis

**Output format:**
```
## CONSENSUS
[What the field broadly agrees on]

## FRONTIER
[Most recent developments, not yet established consensus]

## OPEN QUESTIONS
[What remains unsolved, actively debated]

## KEY PAPERS
[Ranked: title, year, why-it-matters, citations, code-available]

## METHOD TAXONOMY
[Tree: family -> method -> variants]

## APPLICABILITY
[How this connects to practical implementation]
```

**Model:** sonnet | **Tools:** Bash, Read, Grep, Glob

### `method-analyst`

**Trigger:** Claude needs to decide which approach to use.

**Workflow:**
1. Takes 2-5 method names or paper references
2. Retrieves detailed information on each
3. Builds structured comparison matrix
4. Identifies tradeoffs, failure modes, optimal use cases

**Output format:**
```
## METHODS COMPARED
[List with one-line description each]

## COMPARISON MATRIX
| Dimension       | Method A | Method B | Method C |
|----------------|----------|----------|----------|
| Core mechanism | ...      | ...      | ...      |
| Strengths      | ...      | ...      | ...      |
| Limitations    | ...      | ...      | ...      |
| Compute cost   | ...      | ...      | ...      |
| Data needs     | ...      | ...      | ...      |
| Code available | yes/no   | yes/no   | yes/no   |
| Best for       | ...      | ...      | ...      |

## RECOMMENDATION
[Given context, which method and why]

## IMPLEMENTATION NOTES
[Practical considerations for adoption]
```

**Model:** sonnet | **Tools:** Bash, Read, Grep, Glob

### `implementation-guide`

**Trigger:** Claude has identified an approach and needs to understand how to implement it.

**Workflow:**
1. Takes a paper reference or method name
2. Finds paper + associated code repos
3. Maps methodology to implementation steps
4. If code exists: identifies key files, patterns, dependencies
5. Produces implementation guidance Claude can directly use

**Output format:**
```
## PAPER
[Title, authors, year, one-sentence summary]

## CORE ALGORITHM
[Step-by-step pseudocode from methodology]

## ARCHITECTURE
[Components, data flow, key abstractions]

## REFERENCE IMPLEMENTATIONS
[Repo URL, framework, stars, key files]

## ADAPTATION GUIDE
[How to adapt to user's specific problem]

## DEPENDENCIES & REQUIREMENTS
[Libraries, compute, data needed]

## PITFALLS
[Common implementation mistakes, known issues]
```

**Model:** sonnet | **Tools:** Bash, Read, Grep, Glob

## Hooks (2 total)

### PostToolUse — Research Output Validator

**File:** `hooks/validate-research-output.py`
**Trigger:** After Bash tool use
**Purpose:** Validates research JSON output, truncates oversized abstracts, strips HTML artifacts.
**Behavior:**
- Checks for research-assistant JSON signature (`"source": "arxiv|semantic_scholar|papers_with_code"`)
- Not research output -> exit 1 (ignored)
- Valid research output -> exit 0 (passes)
- Malformed -> exit 2 (blocks, Claude sees error)

### SubagentStop — Synthesis Quality Gate

**File:** `hooks/validate-synthesis-output.py`
**Trigger:** When literature-reviewer, method-analyst, or implementation-guide finishes
**Purpose:** Verifies agent produced expected structured sections.
**Behavior:**
- literature-reviewer must have: CONSENSUS, FRONTIER, KEY PAPERS
- method-analyst must have: COMPARISON MATRIX, RECOMMENDATION
- implementation-guide must have: CORE ALGORITHM, REFERENCE IMPLEMENTATIONS
- Missing sections -> exit 2 (blocks stop, agent retries)
- All present -> exit 0 (passes)

## File Tree

```
research-assistant/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── using-research-assistant/
│   │   └── SKILL.md
│   ├── arxiv-search/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── search
│   │       └── search.mjs
│   ├── semantic-scholar-search/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── search
│   │       └── search.mjs
│   └── papers-with-code-search/
│       ├── SKILL.md
│       └── scripts/
│           ├── search
│           └── search.mjs
├── agents/
│   ├── literature-reviewer.md
│   ├── method-analyst.md
│   └── implementation-guide.md
├── hooks/
│   ├── hooks.json
│   ├── validate-research-output.py
│   └── validate-synthesis-output.py
├── README.md
├── CLAUDE.md
├── CONTEXT_research-assistant.md
├── LICENSE
└── .gitignore
```

## Comparison: scientific-skills-main vs research-assistant

| Aspect | scientific-skills-main | research-assistant |
|--------|----------------------|-------------------|
| API keys | Valyu (paid, required) | None (all free APIs) |
| Domain | Drug discovery, biomedical | AI/ML, data science, foundation models |
| Architecture | 12 skills, no agents, no hooks | 4 skills + 3 agents + 2 hooks |
| Output | Raw JSON search results | Structured synthesis for LLM consumption |
| Intelligence | Search and return | Search, synthesize, compare, guide |
| Dependencies | Valyu API key + Node 18 | Node 18 only (zero config) |
| Context cost | 12 skill descriptions always loaded | 4 skill descriptions, agents on-demand |

## Implementation Notes

### From scientific-skills-main (reuse)
- Bash wrapper pattern (`scripts/search` delegating to `search.mjs`)
- Zero-dependency Node.js approach (built-in `fetch()` only)
- CLI argument pattern (query as first arg, max results as second)

### Completely rewritten
- All API implementations (Valyu -> arXiv/S2/PwC)
- All SKILL.md files (new domain, new guidance)
- Output schemas (unified envelope, LLM-optimized fields)
- Everything else is new (agents, hooks, routing skill)

### Marketplace integration
- Add as git submodule to flight505-marketplace
- Add entry to marketplace.json
- Set up webhook workflow (notify-marketplace.yml)
- Update all marketplace scripts (7 files reference plugin lists)
- Run validators to confirm integration

### Testing approach
- Each retrieval skill testable standalone: `scripts/search "transformer attention" 5`
- Agents testable via Claude Code: invoke agent, check output structure
- Hooks testable via pipe: `echo '...' | python3 hooks/validate-research-output.py`
- Integration: `./scripts/validate-plugin-manifests.sh` for marketplace sync

---

**Next step:** Create implementation plan via writing-plans skill.
