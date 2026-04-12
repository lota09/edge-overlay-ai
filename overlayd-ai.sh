#!/data/data/com.termux/files/usr/bin/bash
# =========================================================================
# System: Overlayd-AI Integrated Automation Framework
# Description: Installs and provisions a fully isolated, offline AI
#              agent environment within the Termux compatibility layer.
#              Links the Llama.cpp inference engine to both a Node.js 
#              Telegram interface and the OpenClaw execution environment.
# =========================================================================

set -e

# ==========================================
# 1. Environment & Hardware Diagnostics
# ==========================================
echo "Initiating Overlayd-AI Framework Installation..."
echo "Note: Setup might take up to 30 minutes depending on your phone's processor and internet speed."
echo "Securing critical storage permissions (Please accept the popup if it appears)..."
if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage
    sleep 2
else
    echo "Notice: Storage permissions already provisioned. Skipping step."
fi

echo "Running system diagnostics..."
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
ARCH=$(uname -m)

echo "Detected Architecture: ${ARCH}"
echo "Detected Total Memory: ${TOTAL_RAM} MB"

if [ "$TOTAL_RAM" -lt 6000 ]; then
    echo "Warning: System memory is below 6GB. Using large models may result in severe system degradation and memory thrashing."
fi

# ==========================================
# 2. Intelligent Shizuku Auto-Installer
# ==========================================
if [ ! -f "$PREFIX/bin/rish" ]; then
    echo ""
    echo "========================================================"
    echo "⚠️ CRITICAL REQUIREMENT: SHIZUKU (rish) ⚠️"
    echo "========================================================"
    echo "Your AI cannot physically control your phone without Shizuku."
    echo "Do you want to configure it right now, or skip and do it later?"
    echo "1) Setup Now (Recommended)"
    echo "2) Skip (Bot will lack phone control until manually configured)"
    read -p "Select option (1/2): " SHIZUKU_CHOICE

    if [ "$SHIZUKU_CHOICE" == "1" ]; then
        echo ""
        echo "--- SHIZUKU SETUP INSTRUCTIONS ---"
        echo "1. Install 'Shizuku' from the Play Store & start via Wireless Debugging."
        echo "2. Open Shizuku -> tap 'Use Shizuku in terminal apps' -> 'Export files'."
        echo "3. Create a new folder named 'Shizuku' in your phone's main storage."
        echo "4. Export the files strictly into that 'Shizuku' folder."
        echo ""
        read -p "Press [Enter] ONLY after you have successfully exported the files..."
        
        if ls /sdcard/Shizuku/rish* 1> /dev/null 2>&1; then
            cp /sdcard/Shizuku/rish* $PREFIX/bin/
            chmod +x $PREFIX/bin/rish
            echo "✅ Success! 'rish' was detected in the Shizuku folder and automatically installed!"
        else
            echo "⚠️Warning: 'rish' files were not found in /sdcard/Shizuku/."
            echo "You will need to manually copy them later. Proceeding with text-only setup..."
        fi
    else
        echo "Skipping Shizuku setup. Proceeding..."
    fi
fi

# ==========================================
# 3. Configuration Prompts
# ==========================================
# ==========================================
# 3. Intelligent Model Configuration
# ==========================================
echo ""
EXISTING_MODELS=$(ls $HOME/llama.cpp/models/*.gguf 2>/dev/null | head -n 1)

if [ -f "$EXISTING_MODELS" ]; then
    FOUND_NAME=$(basename "$EXISTING_MODELS")
    echo "========================================================"
    echo "🔍 EXISTING MODEL DETECTED: ${FOUND_NAME}"
    echo "========================================================"
    read -p "Do you want to use this existing model? (y/n): " USE_EXISTING
    if [ "$USE_EXISTING" == "y" ]; then
        PRIMARY_FILE="$FOUND_NAME"
        PRIMARY_URL="local_skip"
        MODEL_INDEX="4"
        echo "Selected existing model. Skipping URL prompts."
    fi
fi

if [ "$PRIMARY_URL" != "local_skip" ]; then
    echo "Select Target Inference Model:"
    echo "1) Qwen2-VL-2B (Target: Vision-capable. Recommended for <8GB Memory)"
    echo "2) Llama-3.2-1B (Target: Lightweight text processing) [GATED]"
    echo "3) Gemma-2-2B-IT(Target: High-end reasoning) [GATED]"
    echo "4) Custom GGUF URL (Enter your own model link from HuggingFace)"
    read -p "Select corresponding index (1/2/3/4): " MODEL_INDEX

    case "$MODEL_INDEX" in
        1)
            PRIMARY_URL="https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf"
            PRIMARY_FILE="qwen2-vl-2b-q4.gguf"
            VISION_URL="https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-f16.gguf"
            VISION_FILE="qwen2-vl-mmproj.gguf"
            ;;
        2)
            PRIMARY_URL="https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
            PRIMARY_FILE="llama-3.2-1b-q4.gguf"
            VISION_URL=""
            VISION_FILE=""
            ;;
        3)
            PRIMARY_URL="https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-UD-Q4_K_XL.gguf"
            PRIMARY_FILE="gemma-4-E2B-it-UD-Q4_K_XL.gguf"
            VISION_URL="https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-BF16.gguf"
            VISION_FILE="mmproj-BF16.gguf"
            ;;
        4)
            read -p "Input Model GGUF URL (HuggingFace): " PRIMARY_URL
            PRIMARY_URL=$(echo "$PRIMARY_URL" | sed 's/\/blob\//\/resolve\//')
            read -p "Save as filename (e.g. custom_model.gguf): " PRIMARY_FILE
            if [ -z "$PRIMARY_FILE" ]; then PRIMARY_FILE="custom_model.gguf"; fi
            
            read -p "Does this model require a Vision (mmproj) module? (y/n): " IS_VISION
            if [ "$IS_VISION" == "y" ]; then
                read -p "Input Vision mmproj URL: " VISION_URL
                VISION_URL=$(echo "$VISION_URL" | sed 's/\/blob\//\/resolve\//')
                read -p "Save vision file as (e.g. custom_mmproj.gguf): " VISION_FILE
            else
                VISION_URL=""
                VISION_FILE=""
            fi
            ;;
        *)
            echo "Error: Invalid model index selected. Terminating sequence."
            exit 1
            ;;
    esac
fi

echo ""
echo "Note: Officially 'gated' models (Llama/Gemma) require a HuggingFace Access Token."
echo "If you selected Qwen or a public community model (Option 4), you can just press Enter to skip."
read -p "Input HuggingFace Token (hf_...): " HF_TOKEN

# ==========================================
# 4. Environment Preparation
# ==========================================
echo ""
echo "Updating and downloading compilation dependencies..."
pkg update -y
pkg install clang cmake nodejs python wget git libandroid-spawn make -y

# ==========================================
# 5. Core Engine Procurement
# ==========================================
echo "Cloning Llama.cpp engine repository..."
cd $HOME
if [ ! -d "llama.cpp" ]; then
    git clone https://github.com/ggerganov/llama.cpp
fi

# ==========================================
# 6. Model Procurement & Authentication
# ==========================================
if [ "$PRIMARY_URL" != "local_skip" ]; then
    echo "Downloading target inference weights..."
    mkdir -p "$HOME/llama.cpp/models"
    cd "$HOME/llama.cpp/models"

    # Temporarily disable exit-on-error so we can catch wget 401s gracefully
    set +e
    if [ -n "$HF_TOKEN" ] && [ "$HF_TOKEN" != "TOKEN_NOT_PROVIDED" ]; then
        wget --header="Authorization: Bearer $HF_TOKEN" -c "$PRIMARY_URL" -O "$PRIMARY_FILE"
        WGET_STATUS=$?
    else
        wget -c "$PRIMARY_URL" -O "$PRIMARY_FILE"
        WGET_STATUS=$?
    fi

    if [ $WGET_STATUS -ne 0 ]; then
        echo "❌ ERROR: Model download failed. Check token/URL."
        exit 1
    fi

    if [ -n "$VISION_URL" ]; then
        echo "Downloading optical projector sub-module..."
        if [ -n "$HF_TOKEN" ] && [ "$HF_TOKEN" != "TOKEN_NOT_PROVIDED" ]; then
            wget --header="Authorization: Bearer $HF_TOKEN" -c "$VISION_URL" -O "$VISION_FILE"
        else
            wget -c "$VISION_URL" -O "$VISION_FILE"
        fi
    fi
    set -e
else
    echo "Notice: Using existing model file. Skipping download step."
fi

# ==========================================
# 4-7. System Preparation & Engine Compilation (IRONCLAD GUARD)
# ==========================================
if [ ! -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
    echo "Notice: Valid engine binary not detected. Initiating one-time system preparation and build..."
    
    # 4. Environment Preparation
    echo "Updating system packages..."
    pkg update -y
    pkg install clang cmake nodejs python wget git libandroid-spawn make -y

    # 5. Core Engine Procurement
    echo "Cloning Llama.cpp engine repository..."
    cd $HOME
    if [ ! -d "llama.cpp" ]; then
        git clone https://github.com/ggerganov/llama.cpp
    fi

    # 7. Compilation Process
    echo "Installing build-specific dependencies..."
    pkg install libexpat -y
    cd ~/llama.cpp
    echo "Starting compilation of llama-server..."
    mkdir -p build
    export LDFLAGS="-landroid-spawn"
    cmake -B build -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF
    cmake --build build --config Release --target llama-server
else
    echo "========================================================"
    echo "✅ ENGINE DETECTED: llama-server is ready."
    echo "Skipping all system updates and compilation steps for speed."
    echo "========================================================"
fi

# ==========================================
# 8. OpenClaw Procurement (Verified Hub Method)
# ==========================================
echo "Installing OpenClaw Vision Processor framework..."

# Apply Network Normalization (From Development Plan)
export NODE_OPTIONS=--dns-result-order=ipv4first

if command -v openclaw &>/dev/null; then
    echo "✅ Notice: OpenClaw already installed. Skipping installation."
else
    echo "Installing Android-optimized OpenClaw distribution (AidanPark/Codex)..."
    # Using the verified hub installer with non-interactive pipeline
    yes | bash -c "$(curl -sSL https://myopenclawhub.com/install)" 2>/dev/null
    
    # Final verification guard
    if ! command -v openclaw &>/dev/null; then
        echo "⚠️  Primary installer failed. Attempting fallback Node package..."
        npm install -g @mmmbuto/codex-cli-termux --force 2>/dev/null
    fi
fi

# Success Verification (Self-Diagnostic)
if command -v openclaw &>/dev/null; then
    echo "========================================================"
    echo "✅ OpenClaw successfully verified: $(openclaw --version 2>/dev/null || echo 'Ready')"
    echo "========================================================"
else
    echo "❌ ERROR: OpenClaw installation failed. Please check your internet connection."
    exit 1
fi

# Pre-creating Skill Directory
mkdir -p $HOME/.openclaw/skills

# ==========================================
# 9. OpenClaw Skill: Android System Control (rish)
# ==========================================
echo "Injecting Android System Control skill into OpenClaw..."
cat << 'EOF' > $HOME/.openclaw/skills/android_system.md
# Android System Control

This skill allows the AI to control Android system settings and perform actions using the rish shell bridge.

## Tools

### execute_android_command
Executes a bash command on the Android system.

- command (string): The shell command to execute (e.g., 'svc wifi disable' or 'input keyevent 3').

## Execution
Run: `bash /data/data/com.termux/files/usr/bin/rish -c "<command>"`
EOF

# Pre-seeding OpenClaw configuration for local LLM
cat << EOF > $HOME/.openclaw/config.yml
gateway:
  host: 0.0.0.0
  port: 3000
  enabled: true

providers:
  local-llm:
    type: openai
    baseUrl: http://127.0.0.1:8080/v1
    apiKey: local-bypass

agents:
  phone-assistant:
    provider: local-llm
    model: local-model
    skills:
      - android_system
EOF

# ==========================================
# 10. Start-Sequence Architecting
# ==========================================
echo "Finalizing standard execution architecture..."
cat << EOF > $HOME/start-overlayd.sh
#!/data/data/com.termux/files/usr/bin/bash
echo "Initiating Overlayd-AI Systems..."
cd ~/llama.cpp

# Start LLM Engine with external access (0.0.0.0)
# Intelligent Vision Detection: Added for Gemma-4/Qwen-VL compatibility
if [ -n "$VISION_FILE" ] && [ -f "models/${VISION_FILE}" ]; then
    echo "========================================================"
    echo "🎥 MULTIMODAL MODE ACTIVATED: Loading ${VISION_FILE}"
    echo "========================================================"
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} --mmproj models/${VISION_FILE} -t 4 -c 4096 --port 8080 > ~/overlayd_server.log 2>&1 &
else
    echo "========================================================"
    echo "📝 TEXT-ONLY MODE: No vision module detected."
    echo "========================================================"
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} -t 4 -c 2048 --port 8080 > ~/overlayd_server.log 2>&1 &
fi

OVERLAYD_PID=\$!

echo "Allocating inference model into system memory (15s)..."
sleep 15

echo "Starting OpenClaw Gateway..."
cd ~
openclaw start > ~/openclaw.log 2>&1 &
CLAW_PID=\$!

echo "System active. Access Web UI at http://127.0.0.1:3000 (Local) or http://PHONE_IP:3000 (Network)"
echo "To configure Discord/others, run: openclaw onboard"

wait \$OVERLAYD_PID \$CLAW_PID
EOF
chmod +x $HOME/start-overlayd.sh

echo ""
# Final validation of environment variables
source ~/.bashrc 2>/dev/null

echo "Installation structure successfully resolved."
echo "Execute the system sequence via the following command:"
echo "bash ~/start-overlayd.sh"
echo "Note: The OpenClaw execution environment can be triggered manually via 'openclaw onboard'."
echo ""
echo "System deployment finished."
echo "If you found this setup useful, please consider subscribing to 'orailnoor' on YouTube!"
