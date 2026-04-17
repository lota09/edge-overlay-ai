#!/usr/bin/env bash
set -euo pipefail

echo "========================================================"
echo "📥 Termux Model Downloader /w HuggingFace Support"
echo "========================================================"

read -p "Model directory name (will create ~/llama.cpp/models/<name>/): " DIR_NAME
DIR_NAME="${DIR_NAME%%/}"
if [ -z "$DIR_NAME" ]; then echo "Directory name is required."; exit 1; fi

TARGET_DIR="$HOME/llama.cpp/models/$DIR_NAME"
mkdir -p "$TARGET_DIR"

read -p "Model GGUF URL (HuggingFace): " MODEL_URL
read -p "Save as filename (leave blank to auto-detect): " MODEL_FILE

read -p "Does this model require a Vision (mmproj) module? (y/n): " IS_VISION
if [ "$IS_VISION" == "y" ]; then
    read -p "Input Vision mmproj URL: " PROJ_URL
    read -p "Save vision file as (leave blank to auto-detect): " PROJ_FILE
else
    PROJ_URL=""
    PROJ_FILE=""
fi

echo ""
echo "Note: Officially 'gated' models (Llama/Gemma) require a HuggingFace Access Token."
read -p "Input HuggingFace Token (hf_...) [leave blank if public]: " HF_TOKEN

# Normalize URLs (/blob/ -> /resolve/)
MODEL_URL=$(echo "$MODEL_URL" | sed 's/\/blob\//\/resolve\//g')
[ -n "$PROJ_URL" ] && PROJ_URL=$(echo "$PROJ_URL" | sed 's/\/blob\//\/resolve\//g')

if [ -z "$MODEL_FILE" ]; then MODEL_FILE=$(basename "$MODEL_URL" | cut -d'?' -f1); fi
if [ -n "$PROJ_URL" ] && [ -z "$PROJ_FILE" ]; then PROJ_FILE=$(basename "$PROJ_URL" | cut -d'?' -f1); fi

AUTH_HEADER=""
if [ -n "$HF_TOKEN" ]; then AUTH_HEADER="--header=Authorization: Bearer $HF_TOKEN"; fi

echo ""
echo "Downloading main LLM to $TARGET_DIR/$MODEL_FILE..."
if [ -n "$AUTH_HEADER" ]; then
    wget $AUTH_HEADER -q --show-progress -O "$TARGET_DIR/$MODEL_FILE" "$MODEL_URL"
else
    wget -q --show-progress -O "$TARGET_DIR/$MODEL_FILE" "$MODEL_URL"
fi

if [ -n "$PROJ_URL" ]; then
    echo ""
    echo "Downloading Vision module to $TARGET_DIR/$PROJ_FILE..."
    if [ -n "$AUTH_HEADER" ]; then
        wget $AUTH_HEADER -q --show-progress -O "$TARGET_DIR/$PROJ_FILE" "$PROJ_URL"
    else
        wget -q --show-progress -O "$TARGET_DIR/$PROJ_FILE" "$PROJ_URL"
    fi
fi

echo ""
echo "✅ All downloads complete! Saved to $TARGET_DIR/"
ls -lh "$TARGET_DIR" | grep ".gguf" || true
