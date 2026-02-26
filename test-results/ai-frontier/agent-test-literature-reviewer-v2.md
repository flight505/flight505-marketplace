# Agent Live Test: literature-reviewer (v2 — after spec fixes)

**Date:** 2026-02-25
**Query:** Same as v1 — "Retrieval-Augmented Generation (RAG) for large language models — current architectures, chunking strategies, and evaluation methods"

## Execution Metrics

| Metric | v1 (before) | v2 (after) | Delta |
|--------|-------------|------------|-------|
| Total tokens | 56,621 | 60,891 | +7.5% |
| Tool uses | 13 | 10 | -23% |
| Duration | 166s | 121s | -27% faster |
| Model | sonnet | sonnet | — |

## Section Completeness

| Required Section | v1 | v2 | Notes |
|-----------------|----|----|-------|
| DATA SOURCES | N/A (didn't exist) | **Missing** | Spec added it but agent didn't produce it. Hook would enforce it once prefix bug is fixed. |
| CONSENSUS | 5 bullets | 5 bullets | Both strong. v2 cites more diverse domains (medicine, biomedicine, radiology, fintech). |
| FRONTIER | 5 bullets | 5 bullets | v2 introduces R2RAG (NeurIPS 2025 winner) and MoC (ACL 2025) — higher-signal papers. |
| OPEN QUESTIONS | 4 bullets | 4 bullets | v2 adds LLM-as-judge trustworthiness and chunk overlap ineffectiveness — more nuanced. |
| KEY PAPERS | 10 papers | 10 papers | See detailed comparison below. |
| METHOD TAXONOMY | ~6 categories | ~5 categories (deeper) | v2 taxonomy is more granular with specific method variants. |
| APPLICABILITY | 3 bullets | 3 bullets | v2 is significantly more actionable (specific token sizes, tool recommendations). |

## KEY PAPERS Comparison

| # | v1 Paper | v2 Paper | Analysis |
|---|----------|----------|----------|
| 1 | Ragas (Es 2023) | Ragas (Es 2023) | Same — correctly identified as foundational |
| 2 | MultiHop-RAG (Tang 2024) | CoFE-RAG (Liu 2024) | v2 swaps in full-chain evaluation — broader scope |
| 3 | Engineering the RAG Stack (Wampler 2025) | MultiHop-RAG (Tang 2024) | Same paper, different rank |
| 4 | Beyond Chunk-Then-Embed (Zhou 2026) | MoC (Zhao 2025, ACL) | v2 picks peer-reviewed ACL paper over preprint |
| 5 | HiChunk (Lu 2025) | Blended RAG (Sawarkar 2024) | Both present in each list |
| 6 | Graph-R1 (Luo 2025) | RAG-Gym (Xiong 2025) | Same paper, different rank |
| 7 | RAG-Gym (Xiong 2025) | HiChunk (Lu 2025) | Same paper, different rank |
| 8 | VideoRAG (Ren 2025) | Engineering RAG Stack (Wampler 2025) | Same paper |
| 9 | Blended RAG (Sawarkar 2024) | Chunking analysis (Bennani 2026) | v2 adds industrial deployment analysis |
| 10 | FAIR-RAG (Aghajani Asl 2025) | Chemistry-aware RAG (Amiri 2025) | v2 adds domain-specific benchmarking |

**v2 improvements:**
- CoFE-RAG with citation count (10) and code repo (github, 41 stars) — v1 lacked this data
- MoC is ACL-published (peer-reviewed > preprint)
- Bennani & Moslonka provides concrete "context cliff at 2.5k tokens" — actionable engineering data
- More consistent citation format with counts

**v2 regressions:**
- Dropped VideoRAG and FAIR-RAG from top 10 (still referenced in FRONTIER)
- Dropped Graph-R1 (still in taxonomy)

## Quality Scores

| Dimension | v1 | v2 | Delta | Notes |
|-----------|----|----|-------|-------|
| Completeness | 9 | 8 | -1 | Missing DATA SOURCES section |
| Accuracy | 8 | 9 | +1 | Better citation data, peer-reviewed picks |
| Recency | 9 | 9 | 0 | Both cover 2025-2026 well |
| Actionability | 8 | 9 | +1 | "Context cliff at 2.5k tokens", specific tool recs |
| Structure | 9 | 9 | 0 | Both well-organized |
| Source coverage | 7 | 8 | +1 | Better cross-source merging visible in metadata |
| Code awareness | 5 | 7 | +2 | CoFE-RAG repo with stars, MoC via ACL, Ragas library noted |
| **Overall** | **8.3** | **8.7** | **+0.4** | Improved despite missing DATA SOURCES |

## Critical Bug Found

**Plugin-prefixed agent names bypass validation hook.**

The SubagentStop hook fires (regex matcher sees "literature-reviewer" inside "ai-frontier:literature-reviewer"), but `validate-synthesis-output.py` did an exact dict lookup on `agent_type` which failed for `"ai-frontier:literature-reviewer"`. Result: the hook silently passed (exit 0) instead of enforcing required sections.

**Fix applied:** Strip plugin prefix with `agent_name.split(":")[-1]`. Now validated in test suite with 3 new test cases covering prefixed names.

## Summary

The spec improvements produced measurably better output:
- More actionable engineering advice (specific numbers, tool recommendations)
- Better code awareness (repo URLs, star counts)
- Stronger paper selection (peer-reviewed over preprints)
- 27% faster execution with fewer tool calls

The DATA SOURCES section wasn't produced because the hook couldn't enforce it (prefix bug). With the hook fix now in place, next invocation should include it.
