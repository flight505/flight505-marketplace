# State Files Reference

SDK Bridge uses multiple state files to coordinate between CLI plugin and SDK agent. This reference documents each file's format, purpose, and lifecycle.

---

## Plugin-Managed Files

These files are created and managed by the SDK Bridge plugin.

### `.claude/sdk-bridge.local.md`

**Purpose**: Project-specific configuration for SDK Bridge

**Format**: Markdown with YAML frontmatter

**Created**: By `/sdk-bridge:init`

**Example**:
```markdown
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 20
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: false
---

# SDK Bridge Configuration

Custom notes about this project's configuration choices.

## Why 20 Sessions?
This project has 35 features, so 20 sessions provides...
```

**Fields**:
- `enabled` (boolean): Whether SDK bridge is active for this project
- `model` (string): Claude model for SDK sessions
- `max_sessions` (integer): Total sessions before stopping
- `reserve_sessions` (integer): Sessions to keep for manual recovery
- `progress_stall_threshold` (integer): Stop if no progress for N sessions
- `auto_handoff_after_plan` (boolean): Auto-handoff after `/plan`

**Lifecycle**:
1. Created by `/sdk-bridge:init`
2. Read by `launch-harness.sh` on handoff
3. Can be edited manually anytime
4. Committed to git (project-specific config)

---

### `.claude/handoff-context.json`

**Purpose**: Track handoff state and progress

**Format**: JSON

**Created**: By `launch-harness.sh` during handoff

**Example**:
```json
{
  "timestamp": "2025-12-15T10:00:00Z",
  "git_commit": "abc123def456",
  "features_total": 35,
  "features_passing": 12,
  "session_count": 8,
  "pid": 89234,
  "model": "claude-sonnet-4-5-20250929",
  "max_sessions": 20,
  "status": "running"
}
```

**Fields**:
- `timestamp` (ISO 8601): When handoff started
- `git_commit` (string): Git commit hash at handoff
- `features_total` (integer): Total features in feature_list.json
- `features_passing` (integer): Features passing at handoff start
- `session_count` (integer): SDK sessions completed (updated periodically)
- `pid` (integer): Process ID of SDK agent
- `model` (string): Model being used
- `max_sessions` (integer): Session limit
- `status` (string): "running", "completed", "cancelled"

**Lifecycle**:
1. Created by `launch-harness.sh` at handoff
2. Updated by `monitor-progress.sh` (if called)
3. Read by `/sdk-bridge:status` and `/sdk-bridge:resume`
4. NOT committed to git (ephemeral state)

**When to Update**:
- Manually: Call `monitor-progress.sh` to update session_count
- Automatically: Hooks can update on SessionStart (optional)

---

### `.claude/sdk-bridge.pid`

**Purpose**: Track running SDK agent process

**Format**: Plain text, single integer

**Created**: By `launch-harness.sh` during handoff

**Example**:
```
89234
```

**Lifecycle**:
1. Created by `launch-harness.sh` with process ID
2. Read by `/sdk-bridge:status` and `/sdk-bridge:cancel` to check if running
3. Deleted when SDK completes or is cancelled
4. NOT committed to git (ephemeral)

**Usage**:
```bash
# Check if SDK running
if [ -f ".claude/sdk-bridge.pid" ]; then
  PID=$(cat .claude/sdk-bridge.pid)
  if ps -p "$PID" > /dev/null 2>&1; then
    echo "SDK running"
  fi
fi
```

---

### `.claude/sdk-bridge.log`

**Purpose**: Capture SDK agent stdout/stderr

**Format**: Plain text log file

**Created**: By `launch-harness.sh` (nohup redirect)

**Example**:
```
Starting autonomous agent
Project directory: /Users/name/project
Model: claude-sonnet-4-5-20250929
Max iterations: 18

# Iteration 1
Reading feature_list.json...
Found 35 features, 0 passing
Implementing feature #1: Initialize Node.js project
... (SDK agent output) ...
Feature #1 complete
Committing changes

# Iteration 2
Implementing feature #2: Set up PostgreSQL connection
...
```

**Lifecycle**:
1. Created by `launch-harness.sh` via `nohup ... > log 2>&1`
2. Appended to by SDK agent during execution
3. Read by `/sdk-bridge:status` (tail -N lines)
4. Persists after completion
5. NOT committed to git (large, ephemeral)

**Usage**:
```bash
# View live
tail -f .claude/sdk-bridge.log

# Check for errors
grep -i error .claude/sdk-bridge.log

# Count sessions
grep -c "^# Iteration" .claude/sdk-bridge.log
```

---

### `.claude/sdk_complete.json`

**Purpose**: Signal SDK agent completion

**Format**: JSON

**Created**: By SDK harness or `monitor-progress.sh` on completion

**Example**:
```json
{
  "timestamp": "2025-12-15T14:30:00Z",
  "reason": "all_features_passing",
  "session_count": 15,
  "exit_code": 0,
  "features_completed": 35,
  "features_remaining": 0,
  "final_commit": "xyz789"
}
```

**Fields**:
- `timestamp` (ISO 8601): When SDK completed
- `reason` (string): Why SDK stopped
  - `"all_features_passing"`: All features done
  - `"max_iterations_reached"`: Hit session limit
  - `"progress_stalled"`: No progress for N sessions
  - `"manual_completion"`: Manually created
  - `"blocked_on_external_dependency"`: Hit blocker
- `session_count` (integer): Total sessions completed
- `exit_code` (integer): 0=success, 1=max sessions, 2=stalled, 3=error
- `features_completed` (integer): Features marked passing
- `features_remaining` (integer): Features still failing
- `final_commit` (string, optional): Last git commit hash
- `message` (string, optional): Human-readable message
- `blocking_features` (array, optional): Feature IDs that blocked progress

**Lifecycle**:
1. Created by harness when stopping OR by `monitor-progress.sh` on detection
2. Read by SessionStart hook to notify user
3. Read by `/sdk-bridge:resume` for completion report
4. Archived (renamed with timestamp) by `/sdk-bridge:resume`
5. NOT committed to git (ephemeral signal)

**Custom Completion Signals**:
SDK can create this file early to signal blockers:
```json
{
  "timestamp": "2025-12-15T12:00:00Z",
  "reason": "blocked_on_external_dependency",
  "session_count": 10,
  "exit_code": 2,
  "message": "Need Stripe API keys to continue with payment features",
  "blocking_features": [23, 24, 25]
}
```

---

## Harness-Managed Files

These files are part of the long-running-agent harness pattern and managed by the SDK agent.

### `feature_list.json`

**Purpose**: Source of truth for work to be done

**Format**: JSON array of feature objects

**Created**: By `/plan` or manually

**Example**:
```json
[
  {
    "id": 1,
    "description": "Initialize Node.js project with Express and TypeScript",
    "passes": true,
    "test": "package.json exists with express and typescript dependencies",
    "implementation_notes": "Used npm init, installed express@4.18 and typescript@5.0"
  },
  {
    "id": 2,
    "description": "Set up PostgreSQL database connection",
    "passes": false,
    "test": "Can connect to PostgreSQL and execute SELECT 1"
  }
]
```

**Fields** (per feature):
- `id` (integer, optional): Feature identifier
- `description` (string): What to implement
- `passes` (boolean): Whether feature is complete
- `test` (string): How to verify completion
- `implementation_notes` (string, optional): SDK adds notes after completing

**Lifecycle**:
1. Created by `/plan` or user manually
2. Read by SDK agent each session
3. Updated by SDK: sets `passes: true` when complete
4. Read by plugin for progress tracking
5. Committed to git (versioned plan)

**SDK Agent Behavior**:
- Each session: Find first `passes: false` feature
- Implement that feature
- Test implementation
- If tests pass: Update `passes: true`
- If tests fail: Log issue, leave `passes: false`, try again next session
- NEVER edit `description` or `test` fields (user's specification)

---

### `claude-progress.txt`

**Purpose**: Session-to-session memory log

**Format**: Plain text, human-readable

**Created**: By SDK initializer agent or manually

**Example**:
```
# SDK Agent Progress Log

## Session 1 - 2025-12-15 10:00 UTC
Implemented Feature #1: Initialize Node.js project
Created package.json with Express and TypeScript
All tests passing
Committed: abc123

## Session 2 - 2025-12-15 10:15 UTC
Attempted Feature #2: PostgreSQL connection
Issue: PostgreSQL not installed locally
Added note to require PostgreSQL in README
Marked feature as blocked

## Session 3 - 2025-12-15 10:30 UTC
Skipped Feature #2 (blocked)
Implemented Feature #3: User model
Created users table migration
Tests passing
Committed: def456

## Failed Approaches
- Feature #2: Tried to use SQLite instead - not compatible with production
```

**Structure**:
- Session entries: Chronological log of each session
- Failed approaches: Documents what didn't work (prevent repeating)
- Context: Anything that helps next session understand state

**Lifecycle**:
1. Created by initializer or manually
2. Appended to by SDK agent after each session
3. Read by SDK agent at start of each session (memory)
4. Read by completion-reviewer for analysis
5. Committed to git (valuable history)

**Why It's Critical**:
- SDK has fresh context each session (no memory)
- Progress log provides continuity
- Prevents repeating failed approaches
- Documents reasoning for future reference

---

### `CLAUDE.md`

**Purpose**: Session protocol and project-specific guidance

**Format**: Markdown

**Created**: By `/plan`, SDK initializer, or manually

**Example**:
```markdown
# Project Protocol

## Tech Stack
- Backend: Node.js 18 + Express 4.18 + TypeScript 5.0
- Database: PostgreSQL 14
- ORM: Prisma 5.0
- Testing: Jest + Supertest

## Code Standards
- Use TypeScript strict mode
- All functions must have JSDoc comments
- Tests required for all public APIs
- Use async/await, never callbacks

## Testing
- Run `npm test` after each feature
- Feature passes only if all tests pass
- Add tests before implementation (TDD)

## Git
- Commit after each passing feature
- Use conventional commits format
- Never force push

## Architecture
- Layered: routes → controllers → services → database
- Dependency injection for services
- Keep route handlers thin (< 10 lines)
```

**Lifecycle**:
1. Created by plan agent or manually
2. Read by SDK agent before each session
3. Guides SDK's implementation approach
4. Can be updated between handoffs
5. Committed to git (project rules)

**What to Include**:
- Tech stack choices and versions
- Code standards and conventions
- Testing requirements
- Git workflow
- Architecture patterns
- Project-specific constraints

---

### `init.sh`

**Purpose**: Environment bootstrap script

**Format**: Bash shell script

**Created**: By SDK initializer agent

**Example**:
```bash
#!/bin/bash
# Environment setup for feature implementation

set -euo pipefail

# Install dependencies
npm install

# Set up database
docker-compose up -d postgres
sleep 5

# Run migrations
npx prisma migrate dev

# Verify environment
npm test -- --testNamePattern="health check"

echo "Environment ready"
```

**Lifecycle**:
1. Created by initializer agent
2. Executed by coding agent before each feature
3. Ensures environment is ready
4. Can be updated as project evolves
5. Committed to git (reproducible setup)

**Purpose**:
- Start services (databases, caches)
- Install dependencies
- Run migrations
- Verify environment health
- Provide clean slate for each session

---

## File Location Summary

```
project/
├── feature_list.json              # [harness] Work to do
├── claude-progress.txt            # [harness] Session memory
├── CLAUDE.md                      # [harness] Project rules
├── init.sh                        # [harness] Environment setup
├── .git/                          # [standard] Version control
└── .claude/
    ├── sdk-bridge.local.md        # [plugin] Configuration
    ├── handoff-context.json       # [plugin] Handoff state
    ├── sdk-bridge.pid             # [plugin] Process ID
    ├── sdk-bridge.log             # [plugin] SDK output
    └── sdk_complete.json          # [plugin] Completion signal
```

**Git Committed**:
- ✅ `feature_list.json` (plan)
- ✅ `claude-progress.txt` (history)
- ✅ `CLAUDE.md` (rules)
- ✅ `init.sh` (reproducibility)
- ✅ `.claude/sdk-bridge.local.md` (project config)

**Git Ignored** (ephemeral):
- ❌ `.claude/handoff-context.json`
- ❌ `.claude/sdk-bridge.pid`
- ❌ `.claude/sdk-bridge.log`
- ❌ `.claude/sdk_complete.json`

**Suggested .gitignore**:
```gitignore
.claude/handoff-context.json
.claude/sdk-bridge.pid
.claude/sdk-bridge.log
.claude/sdk_complete*.json
```

---

## State File Interactions

### During Handoff

1. User runs `/sdk-bridge:handoff`
2. Handoff-validator reads:
   - `feature_list.json` (check work exists)
   - `.claude/sdk-bridge.pid` (check no conflict)
3. `launch-harness.sh` reads:
   - `.claude/sdk-bridge.local.md` (get config)
4. `launch-harness.sh` creates:
   - `.claude/sdk-bridge.pid` (process ID)
   - `.claude/handoff-context.json` (initial state)
   - `.claude/sdk-bridge.log` (output redirect)
5. SDK agent reads:
   - `feature_list.json` (work to do)
   - `claude-progress.txt` (memory)
   - `CLAUDE.md` (rules)
   - Executes `init.sh` (environment)
6. SDK agent writes:
   - `feature_list.json` (update passes)
   - `claude-progress.txt` (append log)
   - `.git/` (commits)

### During Monitoring

1. User runs `/sdk-bridge:status`
2. Command reads:
   - `.claude/sdk-bridge.pid` (check running)
   - `.claude/handoff-context.json` (start time, config)
   - `feature_list.json` (current progress)
   - `.claude/sdk-bridge.log` (recent activity)
   - `.claude/sdk_complete.json` (check completion)

### During Completion

1. SDK agent or monitor creates:
   - `.claude/sdk_complete.json` (signal)
2. SessionStart hook reads:
   - `.claude/sdk_complete.json` (detect completion)
   - `feature_list.json` (quick progress)
3. User runs `/sdk-bridge:resume`
4. Completion-reviewer reads:
   - `.claude/sdk_complete.json` (completion info)
   - `feature_list.json` (final progress)
   - `.claude/handoff-context.json` (original state)
   - `claude-progress.txt` (session history)
   - `.claude/sdk-bridge.log` (error detection)
   - `.git/log` (commits made)
5. Resume command:
   - Archives `.claude/sdk_complete.json`
   - Removes `.claude/sdk-bridge.pid`

---

## Debugging State Issues

### Issue: Status shows wrong progress

```bash
# Force refresh handoff-context.json
./scripts/monitor-progress.sh

# Or manually fix
jq '.features_passing = 12 | .session_count = 8' \
  .claude/handoff-context.json > tmp.json
mv tmp.json .claude/handoff-context.json
```

### Issue: PID file stale

```bash
# Check if process actually running
cat .claude/sdk-bridge.pid
ps -p $(cat .claude/sdk-bridge.pid)

# If not running, remove
rm .claude/sdk-bridge.pid
```

### Issue: Completion not detected

```bash
# Manually create completion signal
cat > .claude/sdk_complete.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "manual_completion",
  "session_count": $(grep -c "Iteration" .claude/sdk-bridge.log)
}
EOF

# Then resume
/sdk-bridge:resume
```

---

This comprehensive reference should help you understand and debug any state file issues.
