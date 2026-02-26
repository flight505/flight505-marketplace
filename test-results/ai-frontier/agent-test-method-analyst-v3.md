# Method Analyst — Live Test v3

**Query:** Compare LoRA vs QLoRA vs full fine-tuning for LLMs. Context: 2x A100 80GB, 70B model, medical QA.
**Date:** 2026-02-26
**Agent version:** v3 (tightened DATA SOURCES placement, REQUIRED Perplexity, SOTA labels emphasis)
**Cache synced:** Both `cache/` and `marketplaces/` paths synced before test

## Sections Produced

| Required Section | Present | Quality |
|-----------------|---------|---------|
| DATA SOURCES | Yes (2nd, not 1st) | Excellent — 10-query table with per-source breakdown |
| METHODS COMPARED | Yes | Good — descriptions, arxiv IDs, S2 citations, but NO SOTA status labels |
| COMPARISON MATRIX | Yes | Outstanding — 10 dimensions, GraLoRA and Med42 evidence cited |
| RECOMMENDATION | Yes | Excellent — decisive, 3-tier ranking, memory math, "when to use BF16 LoRA" |
| IMPLEMENTATION NOTES | Yes | Outstanding — code sample, 7 pitfalls, exact library versions |
| LINEAGE | No | Missing (LoRA → QLoRA family tree not shown) |

## Scoring

| Criterion | Score | Notes |
|-----------|-------|-------|
| Factual accuracy | 9/10 | Memory math correct, real S2 counts, GraLoRA gradient entanglement finding cited |
| Source usage | 8.5/10 | 10 queries across 3 academic sources; S2+arXiv+HF all used per method |
| SOTA awareness | 7/10 | Cites recent papers (GraLoRA 2025, LoRA Land) but no Perplexity check, no status labels |
| Recommendation quality | 9.5/10 | Decisive 3-tier ranking, addresses hardware constraints with numbers |
| Practical utility | 9.5/10 | 7 pitfalls with library versions, Flash Attention advice, multi-task serving tip |
| Output format compliance | 8/10 | DATA SOURCES present (hook caught omission), but not first; no SOTA labels; no LINEAGE |

**Overall: 8.6/10**

## v1 → v2 → v3 Progression

| Aspect | v1 (old spec) | v2 (new spec, stale cache) | v3 (new spec, synced cache) |
|--------|--------------|---------------------------|----------------------------|
| DATA SOURCES | Missing | Present (bottom) | Present (2nd section) |
| Hook enforcement | Not tested | Hook caught DATA SOURCES | Hook caught DATA SOURCES |
| S2 citations | Estimated "~6,000+" | Exact: 3,931 | Exact: 3,931 + 16,470 |
| Multi-query sourcing | 1 total | 10 queries | 10 queries |
| Recent papers cited | None | Jeong et al. 2024 | GraLoRA 2025, LoRA Land, Med42 |
| SOTA status labels | None | None | None |
| Perplexity check | N/A | Not run | Not run |
| LINEAGE section | N/A | Missing | Missing |
| Code with stars | None | qlora: 10,839★ | PEFT, bitsandbytes, LOMO (988★) |
| Library versions | None | None | Full version table (7 packages) |

## Persistent Issues (across all 3 versions)
1. **SOTA status labels never produced** — spec says "REQUIRED for each method — do not omit" but agent consistently ignores this
2. **Perplexity never run** — despite $PPX being available and spec saying "REQUIRED when available"
3. **DATA SOURCES never first** — always added as afterthought after hook catches omission
4. **LINEAGE never produced** — despite LoRA → QLoRA being an obvious family

## Root Cause Analysis
The agent reads the spec but prioritizes producing high-quality CONTENT over following FORMAT precisely. It treats DATA SOURCES as a "nice to have" until the hook forces it. SOTA labels and LINEAGE have no hook enforcement, so they get dropped.

**Possible fixes:**
- Add METHODS COMPARED to hook required sections (would catch missing status labels IF we regex for "Status:")
- Make the hook check for "Perplexity" in DATA SOURCES (would catch skipped Perplexity)
- Accept that content quality is high and format compliance is "good enough" at 8/10
