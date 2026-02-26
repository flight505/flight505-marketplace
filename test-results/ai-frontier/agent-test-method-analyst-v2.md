# Method Analyst — Live Test v2

**Query:** Compare LoRA vs QLoRA vs full fine-tuning for adapting LLMs to domain-specific tasks. Context: 2x A100 80GB, 70B model, medical QA.
**Date:** 2026-02-26
**Agent version:** v2 (Perplexity integration, DATA SOURCES, SOTA labels, 6-step workflow)
**Cache synced:** Yes (source → cache before test)

## Sections Produced

| Required Section | Present | Quality |
|-----------------|---------|---------|
| DATA SOURCES | Yes (bottom) | Good — lists all queries per source, notes S2 partial failure |
| METHODS COMPARED | Yes | Good — descriptions, arxiv IDs, but missing SOTA status labels |
| COMPARISON MATRIX | Yes | Outstanding — 12 dimensions, context-specific memory math |
| RECOMMENDATION | Yes | Excellent — decisive, cites Jeong et al. 2024, includes config |
| IMPLEMENTATION NOTES | Yes | Excellent — 4 QLoRA pitfalls, 2 LoRA/FSDP pitfalls, throughput |
| LINEAGE | No | Missing — LoRA → QLoRA lineage not shown |

## Scoring

| Criterion | Score | Notes |
|-----------|-------|-------|
| Factual accuracy | 9/10 | Memory math correct, real S2 citations (16,470 LoRA, 3,931 QLoRA), Jeong 2024 citation relevant |
| Source usage | 8.5/10 | All 3 academic sources used with multiple queries each; noted S2 HTTP 500 partial failure |
| SOTA awareness | 7/10 | No Perplexity SOTA check run; no status labels on methods (foundational/current/superseded) |
| Recommendation quality | 9.5/10 | Decisive, constraint-specific, includes QLoRA config and when-to-reconsider |
| Practical utility | 9.5/10 | Specific pitfalls at 70B scale, throughput expectations, medical-specific overfitting advice |
| Output format compliance | 8/10 | DATA SOURCES at bottom not top; missing SOTA status labels; missing LINEAGE |

**Overall: 8.6/10** (same as v1 numerically, but quality distribution shifted — better sourcing, weaker format compliance)

## v1 → v2 Comparison

| Aspect | v1 (old spec) | v2 (new spec) |
|--------|--------------|--------------|
| DATA SOURCES section | Missing | Present (bottom, needs reorder) |
| Real S2 citation counts | Estimated "~6,000+" | Exact: 3,931 from S2 |
| Multi-query per source | No (1 query total) | Yes (4 arXiv, 3 S2, 3 HF queries) |
| Source failure noted | No | Yes — S2 HTTP 500 on 3rd query |
| SOTA status labels | None | None (spec has them, agent didn't use) |
| Perplexity SOTA check | Not available | Available but not run |
| LINEAGE section | Not in spec | In spec but not produced |
| Code repo stars | Not reported | 10,839 stars for qlora repo |
| Medical-specific evidence | Med42 cited | Jeong et al. 2024 on limited medical adaptation impact |

## Key Improvements Needed
1. **SOTA status labels** — spec requires them on each method, agent omitted them
2. **DATA SOURCES placement** — should be first section, appeared last (hook caught on first try, agent added as afterthought)
3. **Perplexity SOTA validation** — agent didn't run `$PPX --sota` despite script being available
4. **LINEAGE section** — spec says "can be omitted if unrelated families" but LoRA → QLoRA is clearly same family
5. **Hook retry cost** — agent used extra turns fixing the missing DATA SOURCES instead of getting it right first time
