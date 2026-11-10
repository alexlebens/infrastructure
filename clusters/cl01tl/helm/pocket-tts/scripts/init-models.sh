#!/bin/sh
set -eu

MODEL_DIR="/models/huggingface"
HF_CACHE="/data/huggingface/hub"

KYUTAI_DIR="$HF_CACHE/models--kyutai--pocket-tts/snapshots/db04f0e653473e5c7333c69686ac92b7460b0c1d"
NO_VOICE_DIR="$HF_CACHE/models--kyutai--pocket-tts-without-voice-cloning/snapshots/a7056f505a4a8ca72d8b5fb1440071d6f1a35739"
TOK_DIR="$HF_CACHE/models--kyutai--pocket-tts-without-voice-cloning/snapshots/00eac05ed3d16bdc3f6b5d598874019c34a89214"

mkdir -p "$KYUTAI_DIR" "$NO_VOICE_DIR" "$TOK_DIR" /data/voices

if [ -d "$MODEL_DIR" ]; then
  echo "Syncing models from $MODEL_DIR to $HF_CACHE..."
  cp -r "$MODEL_DIR"/* "$KYUTAI_DIR/"
  if [ -d "$MODEL_DIR/languages" ]; then
    cp -r "$MODEL_DIR/languages" "$NO_VOICE_DIR/"
    cp -r "$MODEL_DIR/languages" "$TOK_DIR/"
  fi
fi

if [ -d "$MODEL_DIR/languages/english/embeddings" ]; then
  cp -n "$MODEL_DIR/languages/english/embeddings"/*.safetensors /data/voices/ 2>/dev/null || true
fi

if [ -d "/models/voices" ]; then
  echo "Syncing custom bundled voices from /models/voices to /data/voices..."
  cp -n /models/voices/* /data/voices/ 2>/dev/null || true
fi
