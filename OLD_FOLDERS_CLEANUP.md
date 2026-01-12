# Old Folders Cleanup Guide

## Current Situation

You have the **flight505-marketplace** with submodules, plus the original standalone repo folders outside the marketplace.

Since the marketplace now manages everything with submodules and real-time webhooks, these old standalone folders can be cleaned up.

---

## Folder Analysis

### 📁 Claude_SDK/ (Parent Directory)

```
Claude_SDK/
├── flight505-marketplace/          ✅ KEEP - Main marketplace with submodules
│   ├── sdk-bridge/                 (submodule - managed by marketplace)
│   ├── storybook-assistant/        (submodule - managed by marketplace)
│   ├── claude-project-planner/     (submodule - managed by marketplace)
│   └── nano-banana/                (submodule - managed by marketplace)
│
├── sdk-bridge-marketplace/         ⚠️  OLD - Now renamed to sdk-bridge
├── UX-UI_book/                     ⚠️  OLD - Now renamed to storybook-assistant
├── claude-project-planner/         ⚠️  OLD - Original standalone repo
├── nano-banana/                    ⚠️  OLD - Original standalone repo
├── storybook-plugin-test/          ⚠️  TEST - Test folder
└── sdk-bridge-test/                ⚠️  TEST - Test folder
```

---

## Folders Safe to Delete

### ✅ Can Delete (No uncommitted changes)

**1. UX-UI_book/**
- Not a git repo
- Old name for storybook-assistant
- **Action:** Delete immediately

**2. nano-banana/**
- Git repo but no uncommitted changes
- Duplicate of marketplace submodule
- **Action:** Delete immediately

**3. storybook-plugin-test/**
- Not a git repo
- Test folder
- **Action:** Delete if no longer needed

**4. sdk-bridge-test/**
- Not a git repo
- Test folder
- **Action:** Delete if no longer needed

### ⚠️ Check First (Uncommitted changes)

**5. sdk-bridge-marketplace/** (3 uncommitted files)
- `CLAUDE.md` - Modified (110+ lines changed)
- `plugins/sdk-bridge/commands/start.md` - Modified (483+ lines changed)
- `plugins/sdk-bridge/hooks/hooks.json` - Modified (2 lines changed)
- **Action:** Review changes, commit if needed, then delete

**6. claude-project-planner/** (1 uncommitted file)
- `README.md` - Modified (408+ lines changed)
- **Action:** Review changes, commit if needed, then delete

---

## Recommended Cleanup Steps

### Option A: Quick Clean (Discard uncommitted changes)

If the uncommitted changes aren't important:

```bash
cd /Users/jesper/Projects/Dev_projects/Claude_SDK

# Delete old folders immediately
trash UX-UI_book
trash nano-banana
trash storybook-plugin-test
trash sdk-bridge-test
trash sdk-bridge-marketplace
trash claude-project-planner
```

### Option B: Safe Clean (Preserve uncommitted changes)

If you want to preserve uncommitted work:

**Step 1: Handle sdk-bridge-marketplace**
```bash
cd sdk-bridge-marketplace

# Review changes
git diff CLAUDE.md
git diff plugins/sdk-bridge/commands/start.md
git diff plugins/sdk-bridge/hooks/hooks.json

# Option A: Commit and push (if changes are valuable)
git add -A
git commit -m "chore: save uncommitted work before cleanup"
git push origin main

# Option B: Create patch file (backup)
git diff > ~/Desktop/sdk-bridge-uncommitted.patch

cd ..
```

**Step 2: Handle claude-project-planner**
```bash
cd claude-project-planner

# Review changes
git diff README.md

# Option A: Commit and push
git add README.md
git commit -m "docs: update README"
git push origin main

# Option B: Create patch file
git diff > ~/Desktop/claude-project-planner-uncommitted.patch

cd ..
```

**Step 3: Delete all old folders**
```bash
trash UX-UI_book
trash nano-banana
trash storybook-plugin-test
trash sdk-bridge-test
trash sdk-bridge-marketplace
trash claude-project-planner
```

---

## Why These Can Be Deleted

**You have marketplace submodules now:**
- All work happens in `flight505-marketplace/` submodules
- Changes are synced to GitHub via webhooks
- Real-time updates (30 seconds)
- No need for standalone folders outside marketplace

**Workflow:**
```
1. Edit code in marketplace submodule:
   cd flight505-marketplace/sdk-bridge

2. Commit and push:
   git add .
   git commit -m "..."
   git push origin main

3. Webhook triggers:
   → Marketplace auto-updates in 30 seconds
   → All users get new version automatically
```

---

## After Cleanup

Your directory structure will be clean:

```
Claude_SDK/
├── flight505-marketplace/          ← Only this remains
│   ├── sdk-bridge/                 (submodule)
│   ├── storybook-assistant/        (submodule)
│   ├── claude-project-planner/     (submodule)
│   └── nano-banana/                (submodule)
│
├── claude-scientific-writer-main/  (other projects)
├── Speech_MCP/                     (other projects)
├── Hacker_News/                    (other projects)
└── ElevenLabs.data/                (other projects)
```

All plugin development happens inside `flight505-marketplace/` submodules.

---

## Verification

After deletion, verify everything works:

```bash
cd flight505-marketplace

# Check submodules
git submodule status

# All should show normal (no + or - prefix):
# 8ea1a64 claude-project-planner (v1.3.1)
# 96df2bf nano-banana (heads/main)
# 1afc1c2 sdk-bridge (v2.0.0)
# b1e1cfe storybook-assistant (v2.0.7)

# Test editing a plugin
cd sdk-bridge
# Make changes, commit, push
# Webhook should trigger in 30 seconds
```

---

## Summary

**Folders to delete:** 6 total
- ✅ Immediate: UX-UI_book, nano-banana, storybook-plugin-test, sdk-bridge-test
- ⚠️ After review: sdk-bridge-marketplace (3 uncommitted files), claude-project-planner (1 uncommitted file)

**Result:** Clean directory structure with only marketplace + submodules

**Benefits:**
- No confusion about which folder to work in
- Single source of truth (marketplace submodules)
- Cleaner filesystem
- Less disk space used
