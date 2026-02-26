# ai-frontier Plugin Evaluation Report

**Date:** 2026-02-25
**Version:** 1.0.0
**Tester:** Automated + manual review

## Test Results Summary

| Category | Passed | Failed | Warned |
|----------|--------|--------|--------|
| File structure | 23 | 0 | 0 |
| Plugin manifest | 14 | 0 | 0 |
| Hooks config | 8 | 0 | 0 |
| API retrieval | 2 | 0 | 1 |
| JSON envelope | 26 | 0 | 0 |
| Hook validators | 13 | 0 | 0 |
| Agent specs | 16 | 0 | 4 |
| Skill quality | 16 | 0 | 0 |
| Special features | 3 | 0 | 0 |
| **TOTAL** | **121** | **0** | **5** |

**Overall: PASS**

---

## Issues Found

### BUG: CLAUDE.md test example uses wrong field name

**Severity:** Medium (misleading docs)
**File:** `CLAUDE.md` line 25

The testing example shows:
```bash
echo '{"tool_output": "{\"success\": true, ...}"}' | python3 hooks/validate-research-output.py
```

But the validator reads `tool_result` (line 19 of `validate-research-output.py`), not `tool_output`. The hook system passes the field as `tool_result`. This test silently exits 1 (pass-through) instead of actually validating, making developers think validation works when it's not being exercised.

**Fix:** Change `tool_output` to `tool_result` in the test example.

---

### ISSUE: Semantic Scholar API rate limiting (429)

**Severity:** Medium (affects reliability)
**File:** `skills/semantic-scholar-search/scripts/search.mjs`

S2 API returns HTTP 429 even with exponential backoff (1s, 2s, 4s). The script correctly retries on 429, but the backoff may be too aggressive for S2's rate window.

**Observations:**
- S2 claims 100 req/sec without API key, but real-world limits are tighter
- No `User-Agent` header is sent — S2 docs recommend including one for better rate treatment
- Adding an S2 API key (free, 1000 req/sec) would help but goes against "zero config" design

**Recommendations:**
1. Add `User-Agent: ai-frontier-plugin/1.0 (Claude Code)` header to all S2 requests
2. Consider longer backoff intervals (2s, 6s, 15s) for S2 specifically
3. Document that S2 API key can be optionally configured via env var for heavy users

---

### OBSERVATION: arXiv uses HTTP, not HTTPS

**Severity:** Low
**File:** `skills/arxiv-search/scripts/search.mjs` line 9

```js
const ARXIV_API = 'http://export.arxiv.org/api/query';
```

arXiv's API works over both HTTP and HTTPS. Using HTTPS would be marginally better (data integrity in transit, no mixed content warnings).

**Fix:** Change to `https://export.arxiv.org/api/query`

---

### OBSERVATION: Agent output format section not detected by test

**Severity:** Informational
**Files:** All 4 agent `.md` files

The test suite flags "no explicit output format section" for all agents. This is a test regex issue — the agents DO have detailed output format specs, they just use section headers like `## REQUIRED OUTPUT FORMAT` in varied patterns rather than a single `## OUTPUT FORMAT` header.

The agents are actually well-specified. The test regex can be improved.

---

## Code Quality Assessment

### Strengths

1. **Unified JSON envelope** — All 3 scripts produce identical top-level structure. Agents can consume any source interchangeably.

2. **Graceful degradation** — Every API call wraps in try/catch, returns `{ success: false, error: "..." }` instead of crashing. Agents can continue with partial data.

3. **Zero dependencies** — Node 18+ built-in `fetch()`, zero npm packages. No install step, no version conflicts.

4. **Hook validation is solid** — Exit code semantics (0=valid, 1=not-ours, 2=malformed) correctly handle all edge cases. The `stop_hook_active` guard prevents infinite retry loops.

5. **Agent specs are thorough** — Especially `architecture-evaluator` at 1079 words with a detailed 3-phase workflow covering code analysis + research + synthesis.

6. **Retry logic** — Exponential backoff on both network errors and 429/5xx responses.

### Areas for Improvement

1. **No `--detail` test for S2 or HF** — The test suite only covers search mode, not paper detail lookups.

2. **arXiv XML parsing with regex** — Works for Atom format but fragile. If arXiv changes their XML schema, parsing silently breaks. Consider a lightweight XML parser or at least add a format version check.

3. **No error output on arXiv API failures** — The `parseAtomXml` function silently returns empty array if XML structure changes. No validation that entries were actually found vs. malformed response.

4. **HF Papers `highlighted_title`/`highlighted_summary`** — These are HTML-like highlight objects that bloat output. Consider stripping to plain text to reduce context tokens.

5. **S2 `code_repos` always empty** — Semantic Scholar doesn't return code repos in search results. The field exists in the envelope but is never populated. Could enrich with a secondary lookup against Papers With Code or GitHub.

---

## Architecture Assessment

**Score: 8/10** — Clean, purpose-built, well-thought-out.

| Aspect | Rating | Notes |
|--------|--------|-------|
| Structure | 9/10 | Skills-first is the right call — no idle MCP context |
| APIs | 8/10 | All free, good coverage. S2 rate limits are a concern |
| Agents | 9/10 | Detailed specs, clear output formats, appropriate scoping |
| Hooks | 8/10 | Solid validation, correct exit codes, loop prevention |
| DX | 7/10 | CLAUDE.md has wrong test example, no automated test suite |
| Resilience | 7/10 | Good error handling, but S2 rate limits can block agents |

---

## Recommended Improvements (Priority Order)

1. **Fix CLAUDE.md test example** — `tool_output` → `tool_result` (5 min)
2. **Add User-Agent header to S2 requests** — Improves rate limit treatment (5 min)
3. **Switch arXiv to HTTPS** — One-line change (1 min)
4. **Strip HF highlighted fields** — Reduce context bloat (15 min)
5. **Add `--detail` tests to test suite** — Cover paper lookup modes (15 min)
6. **Optional S2 API key via env var** — `S2_API_KEY` env → auth header (10 min)
7. **Improve arXiv error detection** — Check for `<opensearch:totalResults>0` (10 min)
