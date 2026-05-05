#!/usr/bin/env bash
# Clone the appropriate autoresearch experiment target repo
# Usage: clone-target.sh <hardware_type> <destination>
#   hardware_type: "mlx" | "cuda-consumer" | "cuda-datacenter"

set -euo pipefail

HARDWARE="${1:?Usage: clone-target.sh <mlx|cuda-consumer|cuda-datacenter> <destination>}"
DEST="${2:?Usage: clone-target.sh <hardware_type> <destination>}"

case "$HARDWARE" in
    mlx)
        REPO="https://github.com/trevin-creator/autoresearch-mlx.git"
        DESC="autoresearch-mlx (Apple Silicon)"
        ;;
    cuda-consumer)
        REPO="https://github.com/flight505/autoresearch-blackwell.git"
        DESC="autoresearch-blackwell (Consumer NVIDIA: RTX 20xx-50xx)"
        ;;
    cuda-datacenter)
        REPO="https://github.com/karpathy/autoresearch.git"
        DESC="autoresearch (Datacenter: H100, A100 — Flash Attention 3)"
        ;;
    *)
        echo "ERROR: Unknown hardware type '${HARDWARE}'" >&2
        echo "Valid options: mlx, cuda-consumer, cuda-datacenter" >&2
        exit 1
        ;;
esac

if [ -d "$DEST" ]; then
    echo "Directory already exists: ${DEST}" >&2
    echo "Remove it first or choose a different destination." >&2
    exit 1
fi

echo "Cloning ${DESC}..."
echo "  From: ${REPO}"
echo "  To:   ${DEST}"

git clone "$REPO" "$DEST"

echo ""
echo "Cloned successfully."
echo "Next: cd ${DEST} && read program.md for setup instructions."
