#!/usr/bin/env bash
# Test SSH connectivity and detect remote GPU for the optimize subsystem
# Usage: test-ssh.sh <ssh_host> [remote_path]

set -euo pipefail

SSH_HOST="${1:?Usage: test-ssh.sh <ssh_host> [remote_path]}"
REMOTE_PATH="${2:-}"

echo "Testing SSH connectivity to ${SSH_HOST}..."

# Test basic connectivity
if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "$SSH_HOST" "echo 'connected'" 2>/dev/null; then
    cat <<EOF
{
  "connected": false,
  "error": "Cannot reach ${SSH_HOST} (timeout or auth failure)"
}
EOF
    exit 1
fi

# Detect GPU
GPU_INFO=$(ssh -o ConnectTimeout=3 "$SSH_HOST" "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null" || echo "")

# Check remote path if provided
REPO_INFO=""
if [[ -n "$REMOTE_PATH" ]]; then
    REPO_INFO=$(ssh -o ConnectTimeout=3 "$SSH_HOST" "
        if [ -d '$REMOTE_PATH' ]; then
            echo 'path_exists=true'
            cd '$REMOTE_PATH'
            git remote get-url origin 2>/dev/null || echo 'no_git_remote'
            [ -f program.md ] && echo 'has_program_md=true' || echo 'has_program_md=false'
            [ -f train.py ] && echo 'has_train_py=true' || echo 'has_train_py=false'
        else
            echo 'path_exists=false'
        fi
    " 2>/dev/null || echo "path_check_failed")
fi

GPU_NAME=""
GPU_MEMORY=""
if [[ -n "$GPU_INFO" ]]; then
    GPU_NAME=$(echo "$GPU_INFO" | head -1 | cut -d',' -f1 | xargs)
    GPU_MEMORY=$(echo "$GPU_INFO" | head -1 | cut -d',' -f2 | xargs)
fi

cat <<EOF
{
  "connected": true,
  "ssh_host": "${SSH_HOST}",
  "gpu": "${GPU_NAME:-none}",
  "gpu_memory": "${GPU_MEMORY:-}",
  "remote_path": "${REMOTE_PATH}",
  "repo_info": "$(echo "$REPO_INFO" | tr '\n' ' ')"
}
EOF
