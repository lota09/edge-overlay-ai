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

# Detect Architecture & System Specs
ARCH=$(uname -m)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')

echo "Running system diagnostics..."
echo "Detected Architecture: ${ARCH}"
echo "Detected Total Memory: ${TOTAL_RAM} MB"

case "$ARCH" in
    aarch64) ARCH="aarch64" ;;
    armv7l|armv8l) ARCH="armv7l" ;;
    x86_64) ARCH="x86_64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ==========================================
# 0. Infrastructure Normalization (Networking & Patcher)
# ==========================================
echo "Applying system-level normalization..."

# Fix Node.js DNS issues on Android
export NODE_OPTIONS=--dns-result-order=ipv4first

# Mock ifconfig (Essential for OpenClaw networking modules)
if ! command -v ifconfig &>/dev/null; then
    cat << 'EOF' > $PREFIX/bin/ifconfig
#!/data/data/com.termux/files/usr/bin/sh
if [ "$1" = "wlan0" ]; then
    ip addr show wlan0 | grep -oE "inet [0-9.]+" | awk '{print "inet addr:"$2 " Bcast: Mask:"}'
else
    echo "Interface not found"
fi
EOF
    chmod +x $PREFIX/bin/ifconfig
fi

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
# 6. Model Procurement & Authentication (Ironclad Guard)
# ==========================================
echo "Downloading target inference weights..."
mkdir -p "$HOME/llama.cpp/models"
cd "$HOME/llama.cpp/models"

# Temporarily disable exit-on-error for 401 handling
set +e

echo "Validating payload permissions and downloading architecture..."
if [ -n "$HF_TOKEN" ] && [ "$HF_TOKEN" != "TOKEN_NOT_PROVIDED" ]; then
    wget --header="Authorization: Bearer $HF_TOKEN" -c "$PRIMARY_URL" -O "$PRIMARY_FILE"
else
    wget -c "$PRIMARY_URL" -O "$PRIMARY_FILE"
fi

if [ -n "$VISION_URL" ]; then
    echo "Downloading optical projector sub-module..."
    if [ -n "$HF_TOKEN" ] && [ "$HF_TOKEN" != "TOKEN_NOT_PROVIDED" ]; then
        wget --header="Authorization: Bearer $HF_TOKEN" -c "$VISION_URL" -O "$VISION_FILE"
    else
        wget -c "$VISION_URL" -O "$VISION_FILE"
    fi
fi

# Re-enable strict error catching
set -e

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
# 8. OpenClaw Procurement (Reference Method)
# ==========================================
echo "Installing OpenClaw Vision Processor framework..."

# Apply Network Normalization (Essential for OpenClaw)
export NODE_OPTIONS=--dns-result-order=ipv4first

if command -v openclaw &>/dev/null || [ -d "$HOME/.openclaw/repo" ]; then
    echo "✅ OpenClaw is already installed! Skipping installation."
else
    echo "📦 Installing OpenClaw via Reference Hub..."
    # Exact command from the provided reference files
    bash -c "$(curl -sSL https://myopenclawhub.com/install)" < /dev/tty && source ~/.bashrc 2>/dev/null
fi

# ==========================================
# 9. Local Inference Bridge (Origin Wrapper)
# ==========================================
# Exactly as seen in overlayd-ai_origin.sh line 198
cat << EOF > $PREFIX/bin/openclaw-local
#!/data/data/com.termux/files/usr/bin/bash
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="local-bypass"
export OPENAI_MODEL="local-model"

echo "Initializing OpenClaw Framework mapped to local inference backbone..."
openclaw "\$@"
EOF
chmod +x $PREFIX/bin/openclaw-local

# ==========================================
# 10. AI Identity & Tools (From Reference: auto_setup.sh)
# ==========================================
mkdir -p ~/.openclaw/workspace 2>/dev/null || true

cat > ~/.openclaw/workspace/IDENTITY.md << 'EOF'
- **Name:** PhoneBot
I am an Autonomous AI Agent running natively on an Android phone via Termux + Shizuku.
I strictly possess UI navigation capabilities via my bash tools.
EOF

cat > ~/.openclaw/workspace/TOOLS.md << 'EOF'
# TOOLS.md
I have full control over this Android phone using `~/phone_control.sh`.
- `bash ~/phone_control.sh ui-dump` - Read the screen.
- `bash ~/phone_control.sh tap X Y` - Tap the screen.
- `bash ~/phone_control.sh open-app PACKAGE_NAME` - Launch apps.
EOF

cat > ~/.openclaw/workspace/AGENTS.md << 'EOF'
I execute terminal commands directly and parse their output.
I must loop my tool calls continuously until the goal is achieved.
EOF

# ==========================================
# 11. Bridge Protocol: Telegram Bot Restoration (From Origin)
# ==========================================
echo "Configuring Node.js interaction logic (Telegram Bridge)..."
cd $HOME
if [ ! -f "package.json" ]; then
    npm init -y > /dev/null
fi
npm install node-telegram-bot-api > /dev/null

cat << 'EOF' > $HOME/telegram_bot.js
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');

const token = process.env.TELEGRAM_TOKEN || 'OVERLAYD_INJECT_TOKEN';
const bot = new TelegramBot(token, {polling: true});

bot.on('message', async (msg) => {
  const chatId = msg.chat.id;
  if (!msg.text || msg.text.startsWith('/')) return;
  
  const response = await fetch("http://127.0.0.1:8080/v1/completions", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
          prompt: `User: ${msg.text.trim()}\nPhoneBot:`,
          temperature: 0.1, max_tokens: 300, stop: ["\nUser:"]
      })
  });
  const data = await response.json();
  let reply = data.choices[0].text.trim();
  bot.sendMessage(chatId, reply);
});
console.log("Telegram Bridge active.");
EOF

sed -i "s/OVERLAYD_INJECT_TOKEN/$TELEGRAM_TOKEN/g" $HOME/telegram_bot.js

# ==========================================
# 12. Start-Sequence Architecting
# ==========================================
echo "Finalizing standard execution architecture..."
cat << EOF > $HOME/start-overlayd.sh
#!/data/data/com.termux/files/usr/bin/bash
echo "Initiating Overlayd-AI Systems..."
cd ~/llama.cpp

if [ -n "$VISION_FILE" ] && [ -f "models/${VISION_FILE}" ]; then
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} --mmproj models/${VISION_FILE} -t 4 -c 4096 --port 8080 > ~/overlayd_server.log 2>&1 &
else
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} -t 4 -c 2048 --port 8080 > ~/overlayd_server.log 2>&1 &
fi
OVERLAYD_PID=\$!
sleep 15

cd ~
openclaw start > ~/openclaw.log 2>&1 &
CLAW_PID=\$!

if [ "$TELEGRAM_TOKEN" != "TOKEN_NOT_PROVIDED" ]; then
    node telegram_bot.js > ~/telegram.log 2>&1 &
    TELE_PID=\$!
fi

echo "System active. Access Web UI at http://127.0.0.1:3000"
wait \$OVERLAYD_PID \$CLAW_PID \$TELE_PID
EOF
chmod +x $HOME/start-overlayd.sh

echo ""
echo "Installation complete. Run 'bash ~/start-overlayd.sh' to begin."
echo "If you found this useful, consider subscribing to 'orailnoor' on YouTube!"
