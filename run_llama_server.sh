#!/usr/bin/env bash
set -euo pipefail

cd $HOME/llama.cpp || { echo "llama.cpp not found! Please build it first."; exit 1; }

echo "Cleaning up any zombie server processes..."
killall llama-server 2>/dev/null || true
pkill -9 -f llama-server 2>/dev/null || true

echo "========================================================"
echo "🚀 Termux Vulkan (Adreno/Turnip) LLM Server Runner"
echo "========================================================"

MODEL_DIR="models"

echo "Available model directories under '$MODEL_DIR':"
mapfile -t DIRS < <(find "$MODEL_DIR" -maxdepth 1 -mindepth 1 -type d | sort)

if [ ${#DIRS[@]} -eq 0 ]; then
    echo "No model subdirectories found in $MODEL_DIR."
    echo "Please download models using download_model.sh first."
    exit 1
fi

PS3="Select a directory: "
select CHOSEN_DIR in "${DIRS[@]}"; do
  if [ -n "$CHOSEN_DIR" ]; then TARGET_DIR="$CHOSEN_DIR"; break; fi
done

mapfile -t ALL_GGUF < <(find "$TARGET_DIR" -maxdepth 1 -type f -name "*.gguf" | sort)
if [ ${#ALL_GGUF[@]} -eq 0 ]; then
    echo "No .gguf files found in $TARGET_DIR."
    exit 1
fi

mapfile -t PROJ_CANDS < <(printf '%s\n' "${ALL_GGUF[@]}" | grep -i "mmproj" || true)

model_tmp=()
for f in "${ALL_GGUF[@]}"; do
  if ! printf '%s\n' "${PROJ_CANDS[@]}" | grep -qx "${f}" 2>/dev/null; then
    model_tmp+=("$f")
  fi
done
mapfile -t MODEL_CANDS < <(printf '%s\n' "${model_tmp[@]}")

MODEL_PATH=""
if [ ${#MODEL_CANDS[@]} -eq 1 ]; then
    MODEL_PATH="${MODEL_CANDS[0]}"
    echo "Auto-detected main model: $MODEL_PATH"
elif [ ${#MODEL_CANDS[@]} -gt 1 ]; then
    echo "Multiple candidate models found:"
    PS3="Select Model: "
    select m in "${MODEL_CANDS[@]}"; do
        if [ -n "$m" ]; then MODEL_PATH="$m"; break; fi
    done
else
    echo "Error: No main LLM .gguf files (excluding mmproj) found!"
    exit 1
fi

PROJ_PATH=""
if [ ${#PROJ_CANDS[@]} -eq 1 ]; then
    PROJ_PATH="${PROJ_CANDS[0]}"
    echo "Auto-detected vision projection: $PROJ_PATH"
elif [ ${#PROJ_CANDS[@]} -gt 1 ]; then
    echo "Multiple candidate vision matching found:"
    PS3="Select Vision (or 0 to skip): "
    select p in "${PROJ_CANDS[@]}" "Skip"; do
        if [ "$REPLY" -le ${#PROJ_CANDS[@]} ]; then PROJ_PATH="$p"; break; else break; fi
    done
fi

echo ""
echo "⚠️ Adreno GPUs can crash with '-ngl 99' on large models."
read -p "Enter GPU offload layers (-ngl) [Default: 20]: " NGL
NGL=${NGL:-20}
read -p "Enter Context Size (-c) [Default: 2048]: " CTX
CTX=${CTX:-2048}

ARGS=( --host 0.0.0.0 --port 8080 -m "$MODEL_PATH" -ngl "$NGL" -c "$CTX" -t 4)
if [ -n "$PROJ_PATH" ]; then ARGS+=( --mmproj "$PROJ_PATH" ); fi

echo ""
echo "Setting up Vulkan Environment..."
export VK_ICD_FILENAMES=${PREFIX}/share/vulkan/icd.d/freedreno_icd.aarch64.json
export TU_DEBUG=noconform

termux-wake-lock
echo "========================================================"
echo "Starting Llama.cpp Server..."
echo "Command: ./build/bin/llama-server ${ARGS[*]}"
echo "(To stop the server, press Ctrl+C)"
echo "========================================================"
./build/bin/llama-server "${ARGS[@]}"
