#!/usr/bin/env bash
set -e

echo "=== Step 0: Speed optimizations for Hugging Face ==="
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HUB_DOWNLOAD_THREADS=12

echo "=== Step 1: Create or reuse venv ==="
if [ ! -d "$HOME/.venvs/hf" ]; then
    python3 -m venv ~/.venvs/hf
    echo "Venv created"
else
    echo "Venv already exists, reusing it"
fi

source ~/.venvs/hf/bin/activate

echo "=== Step 2: Install dependencies (cached install) ==="
pip install -q -U huggingface_hub hf_transfer

echo "=== Step 3: Download HF model into cache (FAST MODE) ==="
python - << 'EOF'
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="unsloth/gemma-4-E2B-it"
)
print("HF model cached successfully.")
EOF

echo "=== Step 4: Pull Ollama model ==="
ollama pull qwen3:0.6b

echo "=== Done ==="
