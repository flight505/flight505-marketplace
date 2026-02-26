# Implementation Guide — Live Test v1 (post-upgrade)

**Query:** Switch Transformer MoE implementation guidance for PyTorch research project.
**Date:** 2026-02-26
**Cache synced:** Yes (both paths)

## Scoring

| Criterion | Score | Notes |
|-----------|-------|-------|
| Factual accuracy | 9.5/10 | 9-step pseudocode is precise, auxiliary loss formulation correct, capacity enforcement explained |
| Source usage | 8/10 | HF Papers + GitHub used well; S2 rate-limited (noted); no Perplexity SOTA check |
| SOTA awareness | 7/10 | No status label on Switch Transformer paper; no Perplexity check |
| Practical utility | 9.5/10 | 4 ranked repos with stars, 8 detailed pitfalls, adaptation table, specific library versions |
| Output format compliance | 8.5/10 | DATA SOURCES present (hook caught), all other sections present and well-structured |

**Overall: 8.5/10**

## Strengths
- Pseudocode is implementation-ready — numbered steps with shapes, formulas, and stability requirements
- 4 reference repos ranked by stars with key file paths
- 8 pitfalls with specific mitigations (routing collapse, L_aux formulation, float32 precision)
- Adaptation table with tradeoffs for 5 common variants
- Architecture section with clear data flow
