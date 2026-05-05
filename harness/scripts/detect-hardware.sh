#!/usr/bin/env bash
# Detect local hardware for the optimize subsystem
# Outputs JSON with detected hardware info

set -euo pipefail

detect_apple_silicon() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        return 1
    fi

    local chip
    chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")
    if [[ -z "$chip" ]]; then
        return 1
    fi

    local memory
    memory=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1073741824}' || echo "0")

    local mlx_available="false"
    if python3 -c "import mlx" 2>/dev/null; then
        mlx_available="true"
    fi

    cat <<EOF
{
  "type": "apple_silicon",
  "chip": "$chip",
  "memory_gb": $memory,
  "mlx_available": $mlx_available,
  "backend": "mlx",
  "description": "$chip ${memory}GB"
}
EOF
    return 0
}

detect_nvidia() {
    if ! command -v nvidia-smi &>/dev/null; then
        return 1
    fi

    local gpu_info
    gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "")
    if [[ -z "$gpu_info" ]]; then
        return 1
    fi

    local gpu_name
    gpu_name=$(echo "$gpu_info" | head -1 | cut -d',' -f1 | xargs)
    local gpu_memory
    gpu_memory=$(echo "$gpu_info" | head -1 | cut -d',' -f2 | xargs)

    cat <<EOF
{
  "type": "nvidia",
  "gpu": "$gpu_name",
  "memory": "$gpu_memory",
  "backend": "cuda",
  "description": "$gpu_name ($gpu_memory)"
}
EOF
    return 0
}

detect_cpu_only() {
    local os
    os=$(uname -s)
    local arch
    arch=$(uname -m)

    cat <<EOF
{
  "type": "cpu",
  "os": "$os",
  "arch": "$arch",
  "backend": "cpu",
  "description": "CPU only ($os $arch)"
}
EOF
}

# Try detection in order of preference
if detect_apple_silicon 2>/dev/null; then
    exit 0
fi

if detect_nvidia 2>/dev/null; then
    exit 0
fi

detect_cpu_only
