# Common Handoff Scenarios

This document describes common scenarios and patterns for using SDK Bridge in different contexts.

---

## Scenario 1: Fresh Project Start

**Context**: Starting a new project from scratch

**Workflow**:
```bash
# Create project
mkdir my-project && cd my-project
git init

# Plan comprehensively
/plan
# Describe full project vision
# Result: 40 features in feature_list.json

# Initialize and handoff immediately
/sdk-bridge:init
/sdk-bridge:handoff

# Go do other work
# Check back in 12-24 hours
```

**Best for**:
- Greenfield projects
- Clear requirements
- Standard tech stacks
- Projects with 20-50 features

**Tips**:
- Spend time on good planning upfront
- Order features by dependency
- Include test criteria for each feature
- Set `max_sessions` higher (25-30) for new projects

---

## Scenario 2: Existing Project - Feature Batch

**Context**: Adding a set of new features to existing codebase

**Workflow**:
```bash
# Navigate to existing project
cd existing-project

# Create feature list for new features only
cat > feature_list.json << 'EOF'
[
  {"description": "Add user profile editing", "passes": false, "test": "..."},
  {"description": "Add password change flow", "passes": false, "test": "..."},
  {"description": "Add account deletion", "passes": false, "test": "..."}
]
EOF

git add feature_list.json
git commit -m "Plan user account management features"

# Handoff
/sdk-bridge:init
/sdk-bridge:handoff

# Agent implements new features, integrating with existing code
```

**Best for**:
- Adding features to established codebases
- Incremental feature development
- When you want to preserve existing code

**Tips**:
- Create CLAUDE.md with coding standards for consistency
- Start with 5-10 features to test integration
- Review SDK's integration approach after first batch
- Use lower `max_sessions` (10-15) for smaller batches

---

## Scenario 3: Technical Debt Cleanup

**Context**: Refactoring, updating dependencies, fixing bugs

**Workflow**:
```bash
# Create technical debt checklist
cat > feature_list.json << 'EOF'
[
  {"description": "Update all dependencies to latest versions", "passes": false, "test": "npm outdated shows no outdated packages"},
  {"description": "Add TypeScript strict mode to all files", "passes": false, "test": "No type errors with strict mode enabled"},
  {"description": "Add missing JSDoc comments to public APIs", "passes": false, "test": "All exported functions have JSDoc"},
  {"description": "Replace deprecated API calls", "passes": false, "test": "No deprecation warnings in tests"}
]
EOF

# Commit current state
git add .
git commit -m "Pre-refactor state"

# Handoff for systematic cleanup
/sdk-bridge:handoff
```

**Best for**:
- Systematic refactoring
- Dependency updates
- Code quality improvements
- Adding missing documentation

**Tips**:
- Make each task atomic and testable
- Expect some manual review needed
- Use `reserve_sessions` generously (3-4)
- Review each commit carefully

---

## Scenario 4: Bug Fix Marathon

**Context**: Multiple known bugs to fix

**Workflow**:
```bash
# Convert GitHub issues to feature list
cat > feature_list.json << 'EOF'
[
  {"description": "Fix: Users can submit empty task titles (Issue #42)", "passes": false, "test": "POST /tasks with empty title returns 400"},
  {"description": "Fix: Task dates not saving in UTC (Issue #38)", "passes": false, "test": "Saved tasks have UTC timestamps"},
  {"description": "Fix: Delete confirmation dialog not showing (Issue #35)", "passes": false, "test": "Clicking delete shows confirmation"}
]
EOF

/sdk-bridge:handoff
```

**Best for**:
- Clear, reproducible bugs
- Bugs with known test cases
- When you have 5+ bugs backlog

**Tips**:
- Include reproduction steps in description
- Make tests very specific
- Review fixes carefully (bugs can be subtle)
- Consider starting with easiest bugs

---

## Scenario 5: Emergency Cancel and Recovery

**Context**: SDK agent going in wrong direction

**Scenario**:
```bash
# Handoff for 30 features
/sdk-bridge:handoff

# Check after 2 hours
/sdk-bridge:status
# Only 2/30 features passing after 8 sessions!

# Something's wrong - check logs
tail -100 .claude/sdk-bridge.log
# SDK keeps failing on Feature #1, trying same approach repeatedly

# Cancel to stop waste
/sdk-bridge:cancel

# Investigate
cat claude-progress.txt | grep "Feature #1"
# Shows: "Attempted to implement login but tests failing on JWT validation"
# Issue: Feature description didn't mention JWT library

# Fix the plan
vim feature_list.json
# Update Feature #1: "Implement login with passport-jwt middleware"
# Make it more specific about dependencies

git commit -m "Clarify authentication approach in feature list"

# Try again
/sdk-bridge:handoff
# Now succeeds with better guidance
```

**Best for**:
- When progress stalls
- When you realize plan needs adjustment
- When SDK makes wrong architectural choices

**Tips**:
- Cancel early if progress seems off
- Review logs to understand the issue
- Fix feature descriptions to be more explicit
- Consider adding CLAUDE.md with architectural guidance

---

## Scenario 6: Iterative Refinement

**Context**: Let SDK implement, then improve quality

**Workflow**:
```bash
# Round 1: Rapid implementation
/sdk-bridge:handoff
# ... completes 25/30 features ...
/sdk-bridge:resume

# Review code quality
# Notice: Some functions lack error handling, tests are basic

# Round 2: Quality improvements
cat > quality-improvements.json << 'EOF'
[
  {"description": "Add comprehensive error handling to all API endpoints", "passes": false},
  {"description": "Improve test coverage to 90%+", "passes": false},
  {"description": "Add input validation to all user inputs", "passes": false},
  {"description": "Add logging to all critical operations", "passes": false}
]
EOF

mv feature_list.json feature_list-done.json
mv quality-improvements.json feature_list.json

/sdk-bridge:handoff
# SDK improves quality of existing code
```

**Best for**:
- When speed is priority first, quality second
- Learning projects (iterate on implementation)
- When you want multiple passes

**Tips**:
- First pass: Get it working
- Second pass: Make it good
- Consider using Opus for quality improvements
- Archive completed feature lists for reference

---

## Scenario 7: Research then Implement

**Context**: SDK needs to explore libraries/patterns first

**Workflow**:
```bash
# Phase 1: Research (do this in CLI, not SDK)
# Research authentication libraries
# Research database ORMs
# Research testing frameworks

# Document decisions in CLAUDE.md
cat > .claude/CLAUDE.md << 'EOF'
# Project Decisions

## Tech Stack
- Auth: passport-jwt
- ORM: Prisma
- Testing: Jest + Supertest

## Architecture
- Layered: routes → controllers → services → database
- All async operations use promises
EOF

# Phase 2: Implementation (SDK)
/plan  # Create feature list using chosen stack
/sdk-bridge:handoff
```

**Best for**:
- Unfamiliar domains
- When architectural decisions needed first
- Complex tech stack choices

**Tips**:
- Do exploration in CLI (interactive)
- Document decisions for SDK
- SDK is better at implementation than research
- Use CLAUDE.md to guide SDK's approach

---

## Scenario 8: Parallel Development (Multiple Machines)

**Context**: Run SDK on server, develop locally

**Workflow**:
```bash
# On your local machine
git commit -m "Plan and initial setup"
git push origin feature/new-feature

# SSH to development server
ssh dev-server
cd project
git pull

# Start SDK on server
/sdk-bridge:handoff
# Logout, SDK continues running

# On your local machine (different feature)
# Work on something else manually
# SDK works on server, you work locally

# Later: Pull SDK's work
git pull  # Get SDK commits
# Review and integrate
```

**Best for**:
- When you need both automation and manual work
- Utilizing idle compute resources
- Working on complementary features

**Tips**:
- Use separate branches
- Regular pulls to stay in sync
- Server for SDK, local for interactive work
- Review SDK changes before merging

---

## Scenario 9: Teaching/Learning Mode

**Context**: Learning a new framework or language

**Workflow**:
```bash
# Create simple learning project
mkdir learn-react && cd learn-react

# Create progressive learning features
cat > feature_list.json << 'EOF'
[
  {"description": "Create basic React component with props", "passes": false},
  {"description": "Add useState hook for counter", "passes": false},
  {"description": "Add useEffect for data fetching", "passes": false},
  {"description": "Create custom hook for form handling", "passes": false},
  {"description": "Add Context API for global state", "passes": false}
]
EOF

# Let SDK implement
/sdk-bridge:handoff

# Review SDK's implementations
/sdk-bridge:resume
# Study the code SDK wrote
# Learn patterns and best practices
```

**Best for**:
- Learning new frameworks
- Understanding best practices
- Seeing working examples

**Tips**:
- Start with simple examples
- Review code carefully to learn
- Try modifying SDK's implementation
- Use as reference for your own code

---

## Scenario 10: Deadline Crunch

**Context**: Need to ship fast, polish later

**Workflow**:
```bash
# Create MVP feature list (only essentials)
# 15 core features, skip nice-to-haves

/sdk-bridge:init
# Set aggressive session count
# Edit .claude/sdk-bridge.local.md:
# max_sessions: 18

/sdk-bridge:handoff

# Monitor actively
while true; do
  sleep 1800  # Every 30 minutes
  /sdk-bridge:status
done

# As soon as complete
/sdk-bridge:resume
# Quick review, ship if passing tests
```

**Best for**:
- Tight deadlines
- MVP/prototype development
- When perfection isn't required

**Tips**:
- Focus on working > perfect
- Skip edge cases, nice-to-haves
- Monitor frequently
- Be ready to manually finish if needed
- Plan quality pass later

---

## Key Patterns Summary

| Scenario | Session Count | Monitoring | Model Choice |
|----------|--------------|------------|--------------|
| Fresh Project | 25-30 | Occasional | Sonnet |
| Feature Batch | 10-15 | Occasional | Sonnet |
| Tech Debt | 15-20 | Frequent | Sonnet |
| Bug Fixes | 10-15 | Frequent | Sonnet |
| Emergency Cancel | Any | Active | Any |
| Iterative Refinement | 15-20 per round | Occasional | Opus for quality |
| Research then Implement | 20-25 | Occasional | Sonnet |
| Parallel Development | 20-30 | Rare | Sonnet |
| Teaching/Learning | 10-15 | Study each commit | Either |
| Deadline Crunch | 15-20 | Very frequent | Sonnet (speed) |

Choose your pattern based on:
- **Project type** (new vs existing)
- **Time availability** (urgent vs patient)
- **Quality needs** (MVP vs production)
- **Learning goals** (ship vs learn)
