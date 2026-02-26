# Agent Live Test: literature-reviewer (v3 — hook prefix fix confirmed)

**Date:** 2026-02-25
**Query:** Same — "RAG for LLMs — architectures, chunking, evaluation"

## Execution Metrics

| Metric | v1 | v2 | v3 | Notes |
|--------|----|----|----|----|
| Tokens | 56,621 | 60,891 | 52,344 | v3 lowest tokens |
| Tool uses | 13 | 10 | 30 | v3 ran many parallel background searches |
| Duration | 166s | 121s | 292s | v3 slower due to S2 retry + multi-query strategy |
| Model | sonnet | sonnet | sonnet | — |

## Section Completeness

| Section | v1 | v2 | v3 |
|---------|----|----|-----|
| DATA SOURCES | N/A | Missing | **Present** — per-source status with result counts, S2 retry noted |
| CONSENSUS | 5 bullets | 5 bullets | 5 bullets |
| FRONTIER | 5 bullets | 5 bullets | 5 bullets |
| OPEN QUESTIONS | 4 bullets | 4 bullets | 4 bullets |
| KEY PAPERS | 10 papers | 10 papers | 10 papers |
| METHOD TAXONOMY | Good | Good | Most detailed (8 top-level categories) |
| APPLICABILITY | 3 bullets | 3 bullets | 3 bullets |

## DATA SOURCES Section (new — confirmed working)

The agent reported:
- arXiv: 15 results (noted sort=date returned irrelevant papers, switched to relevance)
- Semantic Scholar: 15 results + supplementary chunking (10) and GraphRAG (5) searches
- HF Papers: 10 results
- Deduplication: explicitly noted MultiHop-RAG appeared in all 3 sources

This is exactly what we designed the section for — transparency on source quality and coverage.

## Citation Quality (major improvement)

| Paper | v1 citations | v2 citations | v3 citations |
|-------|-------------|-------------|-------------|
| Lewis et al. 2020 (original RAG) | not cited | not cited | **11,445** |
| Gao et al. 2023 (survey) | not cited | not cited | **2,887** |
| RAGAs (Es 2023) | "widely cited" | "widely adopted" | **470** |
| MIRAGE (Xiong 2024) | not cited | not cited | **404** |
| MultiHop-RAG | "widely used" | — | **206** |
| Agentic RAG Survey | not cited | not cited | **202** |
| LightRAG | not cited | not cited | **192** |

v3 has concrete citation counts for all 10 papers — v1 and v2 had "widely cited" or missing.

## Code Availability (major improvement)

| Paper | v1 | v2 | v3 |
|-------|----|----|-----|
| RAGAs | "Code: yes" | "Code: yes (ragas Python library)" | "Code: yes (github.com/explodinggradients/ragas)" |
| CoFE-RAG | not cited | "Code: yes (github, 41 stars)" | not cited (different paper set) |
| Lewis 2020 | not cited | not cited | "Code: yes (HuggingFace)" |
| LightRAG | not cited | not cited | "Code: yes (open-source)" |
| MIRAGE | not cited | not cited | "Code: yes" |
| MultiHop-RAG | "425 GH stars" (inline) | not cited | "Code: yes" |

v3 consistently reports code availability with repo links where found.

## Quality Scores

| Dimension | v1 | v2 | v3 | Notes |
|-----------|----|----|-----|-------|
| Completeness | 9 | 8 | **10** | All sections including DATA SOURCES |
| Accuracy | 8 | 9 | **9** | Rich citation data from S2 |
| Recency | 9 | 9 | **9** | 2024-2025 coverage strong |
| Actionability | 8 | 9 | **9** | Specific recommendations with evidence |
| Structure | 9 | 9 | **9** | Clean, consistent formatting |
| Source coverage | 7 | 8 | **10** | Multi-query strategy, dedup noted, S2 retry |
| Code awareness | 5 | 7 | **8** | Repo links, HuggingFace integration noted |
| **Overall** | **8.3** | **8.7** | **9.1** | |

## Key Findings

1. **DATA SOURCES section confirmed working** — hook prefix fix enforces it
2. **Multi-query strategy** — agent crafted separate queries for chunking and GraphRAG subtopics
3. **S2 retry resilience** — initial S2 call failed (429), agent retried and got data
4. **Foundational papers surfaced** — Lewis 2020 (11K cites) and Gao 2023 survey (2.9K cites) now anchor the review
5. **Trade-off: more tool calls = slower but richer** — 30 calls vs 10-13, but much better data

## Remaining Improvement Opportunities

- Duration increased to 292s — multi-query is valuable but expensive. Could optimize by limiting supplementary queries.
- v3 missed some v2 papers (CoFE-RAG, MoC from ACL) — different query strategies surface different papers. This is inherent variability, not a regression.
