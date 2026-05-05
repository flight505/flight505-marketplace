---
name: setup
description: "Configure harness optimize-subsystem hardware targets — Apple Silicon (MLX), NVIDIA server (CUDA), or RunPod cloud GPU. One-time setup stored persistently. Use when user mentions hardware setup, SSH targets, GPU configuration, or says 'configure optimization targets'."
user-invocable: true
---

# Harness: Optimize Setup

Guide the user through configuring hardware targets for the optimization loop. This is the ONE interactive entry point for the optimize subsystem — everything else is headless.

Config persists across sessions at `${CLAUDE_PLUGIN_DATA}/config.json` (fallback: `~/.harness/config.json`).

## Step 1: Check existing config

```bash
cat "${CLAUDE_PLUGIN_DATA:-${HOME}/.harness}/config.json" 2>/dev/null || echo "NO_CONFIG"
```

If config exists, show current targets and ask if the user wants to update or start fresh.

## Step 2: Auto-detect local hardware

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-hardware.sh"
```

This detects Apple Silicon (MLX), NVIDIA GPU (CUDA), or CPU-only.

## Step 3: Configure targets

### Local

If Apple Silicon or NVIDIA GPU detected, ask for the path to an experiment repo (or any project to optimize). Validate:

```bash
[ -d "<path>" ] && echo "VALID" || echo "INVALID"
```

For ML training repos, also check:
```bash
[ -f "<path>/program.md" ] && [ -f "<path>/train.py" ] && echo "ML_REPO" || echo "GENERIC"
```

### Remote NVIDIA Server

Ask if they have an SSH-accessible NVIDIA GPU server. If yes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-ssh.sh" "<ssh_host>"
```

Collect:
- SSH hostname (e.g., `ml-server`, `user@192.168.1.50`)
- Remote working directory

Identify the installed fork:
```bash
ssh -o ConnectTimeout=3 "<ssh_host>" "cd <path> && git remote get-url origin 2>/dev/null && head -5 train.py" 2>/dev/null
```

Repo recommendations:
- Consumer NVIDIA (RTX 20/30/40/50): [flight505/autoresearch-blackwell](https://github.com/flight505/autoresearch-blackwell)
- Datacenter (H100, A100): [karpathy/autoresearch](https://github.com/karpathy/autoresearch)

### RunPod (Cloud GPU)

Ask if the user wants RunPod cloud GPU access. If yes:
- Collect API key. No account: "Sign up at https://runpod.io?ref=wjm4q5bw"
- Pod provisioning is manual for now; API key stored for future automation.

## Step 4: Clone experiment target (optional)

If the user doesn't have an experiment repo yet, offer to clone one:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/clone-target.sh" "<hardware>" "<destination>"
```

This clones the appropriate autoresearch fork based on hardware.

## Step 5: Write config

```bash
cat << 'CONFIGEOF' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-config.sh"
{
  "version": 1,
  "targets": {
    "local": {
      "enabled": true/false,
      "path": "<path>",
      "backend": "mlx" | "cuda" | "cpu",
      "description": "<auto-detected hardware>"
    },
    "server": {
      "enabled": true/false,
      "ssh_host": "<hostname>",
      "path": "<remote path>",
      "backend": "cuda",
      "gpu_type": "<detected GPU>",
      "repo": "<git remote URL>",
      "description": "<GPU name + fork>"
    },
    "runpod": {
      "enabled": true/false,
      "api_key": "<key>",
      "gpu_type": "NVIDIA RTX 4090",
      "description": "RunPod cloud GPU"
    }
  }
}
CONFIGEOF
```

## Step 6: Verify

Read back and summarize:
```bash
cat "${CLAUDE_PLUGIN_DATA:-${HOME}/.harness}/config.json"
```

Then explain next steps:
- The orchestrator can now use `loop` phases in workflows
- Direct agent spawn: the optimizer agent reads this config for server targets
- The advisor agent can analyze projects against these targets
