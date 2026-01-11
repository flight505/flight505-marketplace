# Configuration Reference

Complete reference for configuring SDK Bridge for your project.

---

## Configuration File: `.claude/sdk-bridge.local.md`

### Location

```
.claude/sdk-bridge.local.md  # Project-specific configuration
```

### Format

Markdown file with YAML frontmatter:

```markdown
---
field: value
another_field: value
---

# Optional markdown content

Your notes about configuration choices...
```

---

## Configuration Fields

### `enabled`

**Type**: Boolean
**Default**: `true`
**Required**: No

Whether SDK bridge is enabled for this project.

```yaml
enabled: true   # SDK bridge active
enabled: false  # SDK bridge disabled (skip hooks, commands fail gracefully)
```

**When to disable**:
- Temporarily preventing SDK bridge usage
- Debugging without SDK bridge interference
- Project not ready for autonomous work

---

### `model`

**Type**: String
**Default**: `"claude-sonnet-4-5-20250929"`
**Required**: No

Which Claude model the SDK agent uses.

**Options**:
```yaml
model: claude-sonnet-4-5-20250929   # Sonnet 4.5 (recommended)
model: claude-opus-4-5-20251101     # Opus 4.5 (most capable)
model: claude-haiku-4-5-20250429    # Haiku 4.5 (fastest, cheapest)
```

**Comparison**:

| Model | Speed | Capability | Cost | Best For |
|-------|-------|------------|------|----------|
| Haiku | Fast | Good | Low | Simple features, repetitive tasks |
| Sonnet | Medium | Very Good | Medium | Most projects (recommended) |
| Opus | Slow | Excellent | High | Complex features, creative work |

**Recommendations**:
- **Default to Sonnet**: Best balance of capability and cost
- **Use Opus for**: Complex architectural decisions, creative UI work, novel algorithms
- **Use Haiku for**: Simple CRUD, repetitive patterns, well-defined tasks
- **Switch mid-project**: Complete complex features with Opus, simple ones with Sonnet

**Example: Multi-phase approach**:
```bash
# Phase 1: Complex features with Opus
# Edit .claude/sdk-bridge.local.md:
model: claude-opus-4-5-20251101

/sdk-bridge:handoff
# ... completes 10 complex features ...
/sdk-bridge:resume

# Phase 2: Simple features with Sonnet
model: claude-sonnet-4-5-20250929

/sdk-bridge:handoff
# ... completes 25 simple features ...
```

---

### `max_sessions`

**Type**: Integer
**Default**: `20`
**Range**: `1` to `100` (recommend `10-50`)

Total number of SDK sessions allowed before stopping.

```yaml
max_sessions: 20   # Stop after 20 sessions
```

**What is a session?**
- 1 session = 1 complete attempt to implement a feature
- Includes: reading, implementing, testing, committing
- Typically 5-15 minutes per session

**How to choose**:
```
max_sessions = (number_of_features / success_rate) + buffer
```

**Examples**:
- 10 simple features → `max_sessions: 15` (1.5x buffer)
- 30 moderate features → `max_sessions: 40` (1.3x buffer)
- 50 complex features → `max_sessions: 75` (1.5x buffer)

**Success rates**:
- Simple features (CRUD, standard patterns): 80-90% success
- Moderate features (business logic, integrations): 70-80%
- Complex features (algorithms, creative UI): 60-70%

**Guidelines**:
- **Minimum**: `features * 1.2` (tight, risk of incomplete)
- **Recommended**: `features * 1.5` (balanced)
- **Conservative**: `features * 2.0` (generous, allows retries)

**When to adjust**:
- **Increase** if features are complex or ill-defined
- **Decrease** for well-defined, simple features
- **Monitor** actual success rate and adjust next time

---

### `reserve_sessions`

**Type**: Integer
**Default**: `2`
**Range**: `0` to `10` (recommend `2-4`)

Number of sessions to reserve for manual intervention.

```yaml
reserve_sessions: 2   # Save last 2 sessions
```

**How it works**:
```
actual_stop = max_sessions - reserve_sessions
```

With `max_sessions: 20` and `reserve_sessions: 2`:
- SDK stops after session 18
- Sessions 19-20 available for manual recovery

**Why reserve sessions?**
- SDK might hit rate limits → manual finish needed
- Last features might need human insight
- Manual wrap-up and testing
- Recovery from unexpected issues

**Recommendations**:
- **2 sessions**: Minimum reasonable (default)
- **3-4 sessions**: Complex projects or tight timelines
- **0 sessions**: If you want SDK to use all sessions (not recommended)

**Example scenarios**:

```yaml
# Aggressive: Use all sessions
max_sessions: 20
reserve_sessions: 0
# SDK runs full 20 sessions

# Balanced: Reserve for wrap-up
max_sessions: 25
reserve_sessions: 3
# SDK runs 22, you have 3 for finishing

# Conservative: Reserve for manual work
max_sessions: 30
reserve_sessions: 5
# SDK runs 25, you have 5 for polish/fixes
```

---

### `progress_stall_threshold`

**Type**: Integer
**Default**: `3`
**Range**: `2` to `10` (recommend `3-5`)

Stop SDK if no features completed for N consecutive sessions.

```yaml
progress_stall_threshold: 3   # Stop after 3 failed attempts
```

**How it works**:
- SDK attempts Feature X
- Attempt fails (tests don't pass)
- SDK tries Feature X again
- Fails again (2nd attempt)
- Tries again (3rd attempt)
- Still fails → STOP (hit threshold)

**Why this matters**:
- Prevents wasting sessions on blocked features
- Indicates feature needs clarification
- Saves API costs on repeated failures

**When to adjust**:

```yaml
# Strict: Stop quickly
progress_stall_threshold: 2
# Use when: Features are clear, failures indicate real blockers

# Balanced: Allow retries (default)
progress_stall_threshold: 3
# Use when: Standard projects, occasional flaky tests

# Lenient: More attempts
progress_stall_threshold: 5
# Use when: Complex features, tests might be flaky, worth more tries
```

**Common failure reasons**:
- Feature description too vague
- External dependency missing (API keys, services)
- Tests are flaky or incorrect
- Feature genuinely too complex for autonomous implementation

**Response to stall**:
1. SDK stops and creates completion signal
2. You run `/sdk-bridge:resume`
3. Review logs: `grep "Feature #N" claude-progress.txt`
4. Fix issue: Clarify feature description or fix environment
5. Restart: `/sdk-bridge:handoff`

---

### `auto_handoff_after_plan`

**Type**: Boolean
**Default**: `false`

Automatically handoff to SDK after `/plan` creates feature_list.json.

```yaml
auto_handoff_after_plan: false   # Manual handoff
auto_handoff_after_plan: true    # Auto handoff
```

**Workflow with `false` (default)**:
```bash
/plan
# Review feature_list.json
# Edit if needed
/sdk-bridge:handoff  # Explicit command
```

**Workflow with `true`**:
```bash
/plan
# Automatically calls /sdk-bridge:handoff
# SDK starts immediately
```

**When to enable**:
- You trust plan quality
- Batch processing multiple projects
- Overnight/weekend automation
- Standard, repetitive projects

**When to keep disabled**:
- Want to review plan first
- Need to customize features
- First time with SDK bridge
- Complex/novel projects

---

## Complete Configuration Examples

### Example 1: Small Project (15 features)

```markdown
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 18
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: false
---

# Small API Project

15 features for a simple REST API.
Using conservative session count (1.2x features).
```

### Example 2: Large Project (50 features)

```markdown
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 70
reserve_sessions: 5
progress_stall_threshold: 4
auto_handoff_after_plan: false
---

# Full-Stack Web App

50 features including backend, frontend, and integrations.
Extra sessions and reserves for complexity.
Higher stall threshold due to integration tests.
```

### Example 3: Complex Features with Opus

```markdown
---
enabled: true
model: claude-opus-4-5-20251101
max_sessions: 40
reserve_sessions: 4
progress_stall_threshold: 5
auto_handoff_after_plan: false
---

# Creative Dashboard UI

20 complex UI features requiring design decisions.
Using Opus for better creative capability.
Higher stall threshold (features are genuinely hard).
```

### Example 4: Batch Processing with Auto-Handoff

```markdown
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 25
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: true
---

# Standardized Microservice

Auto-handoff enabled for overnight batch processing.
Standard patterns, well-defined features.
```

### Example 5: Learning/Exploration

```markdown
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 12
reserve_sessions: 2
progress_stall_threshold: 2
auto_handoff_after_plan: false
---

# Learning React

10 simple features for learning.
Lower sessions (want to review frequently).
Strict stall threshold (failures indicate I need to clarify).
```

---

## Advanced Configuration Patterns

### Pattern 1: Multi-Phase with Checkpoints

**Scenario**: Large project, want to review after each 10 features

```markdown
---
max_sessions: 15
reserve_sessions: 2
---
```

```bash
# Phase 1
jq '.[0:10]' all-features.json > feature_list.json
/sdk-bridge:handoff
# ... completes 10 ...
/sdk-bridge:resume

# Review, test, commit
git commit -m "Phase 1 complete"

# Phase 2
jq '.[10:20]' all-features.json > feature_list.json
/sdk-bridge:handoff
# ... continues ...
```

### Pattern 2: Dynamic Model Selection

**Scenario**: Use Opus for hard features, Sonnet for easy

```bash
# Separate feature lists
cat complex-features.json > feature_list.json

# Edit .claude/sdk-bridge.local.md:
model: claude-opus-4-5-20251101
/sdk-bridge:handoff

# After complex features done
/sdk-bridge:resume
cat simple-features.json > feature_list.json

# Switch to Sonnet
model: claude-sonnet-4-5-20250929
/sdk-bridge:handoff
```

### Pattern 3: Graduated Sessions

**Scenario**: Start conservative, increase if going well

```markdown
# Initial attempt
max_sessions: 15
```

```bash
/sdk-bridge:handoff
# Check after 5 sessions
/sdk-bridge:status
# Going well? Cancel and increase

/sdk-bridge:cancel
# Edit: max_sessions: 30
/sdk-bridge:handoff
```

---

## Environment Variables

SDK Bridge respects these environment variables:

### `ANTHROPIC_API_KEY`

API key for Claude API access.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### `CLAUDE_CODE_OAUTH_TOKEN`

OAuth token from `claude setup-token`.

```bash
# Set via command
claude setup-token

# SDK Bridge automatically uses it
```

**Precedence**: CLAUDE_CODE_OAUTH_TOKEN > ANTHROPIC_API_KEY

---

## Configuration Validation

### Validate Configuration

Check if configuration is valid:

```bash
# Parse YAML
cat .claude/sdk-bridge.local.md | sed -n '/^---$/,/^---$/{ /^---$/d; p; }'

# Check required fields
grep -q "^model:" .claude/sdk-bridge.local.md && echo "✓ model set"
grep -q "^max_sessions:" .claude/sdk-bridge.local.md && echo "✓ max_sessions set"
```

### Common Validation Errors

**Error**: `max_sessions` too low
```
# Fix
max_sessions: 30   # Increase from 10
```

**Error**: Invalid model name
```
# Fix
model: claude-sonnet-4-5-20250929   # Correct format
```

**Error**: Negative reserve_sessions
```
# Fix
reserve_sessions: 2   # Must be >= 0
```

---

## Configuration Best Practices

### 1. Start Conservative

First time? Use lower session counts:
```yaml
max_sessions: 15   # Start small
reserve_sessions: 3  # Reserve more
```

### 2. Document Decisions

Use markdown section to explain:
```markdown
---
max_sessions: 40
---

# Why 40 Sessions?

This project has 25 features, but they're complex integrations.
Past experience: 1.6x multiplier needed for integration work.
25 * 1.6 = 40 sessions
```

### 3. Adjust Based on Results

After first handoff:
```bash
/sdk-bridge:resume
# Actual: 25 features in 20 sessions (1.25x)

# Next time
max_sessions: 32   # Use observed 1.25x instead of 1.6x
```

### 4. Project-Specific Configuration

Commit `.claude/sdk-bridge.local.md` to git:
```bash
git add .claude/sdk-bridge.local.md
git commit -m "Configure SDK bridge for this project"
```

Team members get same configuration.

### 5. Use Comments for Team Context

```markdown
---
model: claude-opus-4-5-20251101
max_sessions: 50
---

# Configuration Rationale

## Why Opus?
Features 15-30 involve complex UI state management.
Opus performs 20% better on these types of features.

## Why 50 Sessions?
30 features * 1.5 (buffer) + 5 (integration complexity)

## Last Updated
2025-12-15 by @username
```

---

## Troubleshooting Configuration

### Issue: SDK Uses Wrong Model

**Check current config**:
```bash
cat .claude/sdk-bridge.local.md | grep "^model:"
```

**Fix**:
```bash
# Edit file
vim .claude/sdk-bridge.local.md
# Or sed
sed -i 's/model: .*/model: claude-sonnet-4-5-20250929/' .claude/sdk-bridge.local.md
```

### Issue: Configuration Not Read

**Verify file exists**:
```bash
[ -f ".claude/sdk-bridge.local.md" ] && echo "exists" || echo "missing"
```

**Recreate**:
```bash
/sdk-bridge:init
# Or manually create
```

### Issue: Session Limit Hit Too Early

**Analysis**:
```bash
# Sessions used
grep -c "^# Iteration" .claude/sdk-bridge.log

# Features completed
jq '[.[] | select(.passes==true)] | length' feature_list.json

# Success rate
# success_rate = features_completed / sessions_used
```

**Adjust**:
```yaml
# If success rate < 0.7, increase max_sessions
max_sessions: 40   # Increased from 25
```

---

## Default Configuration

If no `.claude/sdk-bridge.local.md` exists, these defaults apply:

```yaml
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 20
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: false
```

---

This configuration reference should help you optimize SDK Bridge for your specific project needs.
