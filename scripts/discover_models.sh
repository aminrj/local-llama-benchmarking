#!/usr/bin/env bash
set -euo pipefail

# Discover Ollama models and create symlinks in ~/models/
# Usage: ./scripts/discover_models.sh [--sync]

MODELS_DIR="${HOME}/models"
OLLAMA_MODELS_DIR="/usr/share/ollama/.ollama/models"
SYNC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sync) SYNC=1; shift ;;
        *) shift ;;
    esac
done

mkdir -p "${MODELS_DIR}"

echo "=== Ollama Model Discovery ==="
echo "Models directory: ${MODELS_DIR}"
echo ""

# Find all model directories with GGUF files
found=0
for dir in "${OLLAMA_MODELS_DIR}"/Q*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")

    # Find GGUF files (excluding mmproj)
    for gguf in "$dir"/*.gguf; do
        [ -f "$gguf" ] || continue
        base=$(basename "$gguf")
        [[ "$base" == mmproj* ]] && continue

        link="${MODELS_DIR}/${base}"
        found=$((found + 1))

        if [ "$SYNC" -eq 1 ] || [ ! -L "$link" ]; then
            ln -sf "$gguf" "$link"
            echo "  ✓ $name -> $base"
        else
            echo "  - $name -> $base (already linked)"
        fi
    done
done

if [ "$found" -eq 0 ]; then
    echo "  No GGUF models found in Ollama's model store."
    echo "  Models stored as blobs may need manual extraction."
fi

echo ""
echo "Found ${found} model(s) with accessible GGUF files."
echo ""
echo "To add more models, place GGUF files in ${MODELS_DIR}/"
echo "Then update config/models.yaml with the model entries."
