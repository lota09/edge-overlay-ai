#!/data/data/com.termux/files/usr/bin/bash
# =========================================================================
# System: Overlayd-AI Integrated Automation Framework
# Description: Installs and provisions a fully isolated, offline AI
#              agent environment within the Termux compatibility layer.
#              Links the Llama.cpp inference engine to both a Node.js 
#              Telegram interface and the OpenClaw execution environment.
# =========================================================================

# NOTE: set -e is intentionally NOT used.
# pkg and other Termux commands may return non-zero on minor warnings.
# Errors are handled explicitly where they matter.

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
# Bootstrap: Essential Tool Check
# ==========================================
echo ""
echo "Checking essential tools..."
MISSING_TOOLS=""
for cmd in clang cmake node python wget git make; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS $cmd"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo "⚠️  Missing tools:$MISSING_TOOLS — Installing all required packages..."
    pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || {
        echo "⚠️  pkg update had warnings (continuing...)"
    }
    pkg install -y clang cmake nodejs python wget git libandroid-spawn make </dev/null 2>&1 || {
        echo "⚠️  Some packages may have failed to install (continuing...)"
    }

else
    echo "✅ All essential tools present."
fi

# ==========================================
# GPU Acceleration Selection
# ==========================================
USE_GPU=false
echo ""
echo "========================================================"
echo "🎮 GPU Acceleration (Vulkan / Adreno)"
echo "========================================================"
echo "Offloads model layers to the GPU for faster inference."
read -p "Enable Vulkan GPU acceleration? (y/n): " GPU_CHOICE
if [ "$GPU_CHOICE" == "y" ]; then
    USE_GPU=true
    echo "✅ GPU acceleration enabled."
else
    echo "CPU-only mode selected."
fi

# ==========================================
# GPU Package Setup (runs only if GPU selected)
# ==========================================
if [ "$USE_GPU" = true ]; then
    echo ""
    echo "========================================================"
    echo "📦 Installing GPU Acceleration packages..."
    echo "========================================================"

    # Add tur-repo (provides mesa-zink, virglrenderer-mesa-zink)
    if ! pkg list-installed 2>/dev/null | grep -q "^tur-repo"; then
        echo "Adding tur-repo..."
        pkg install -y tur-repo </dev/null 2>&1 || true
    fi

    # Add x11-repo (provides Termux:X11 related packages)
    if ! pkg list-installed 2>/dev/null | grep -q "^x11-repo"; then
        echo "Adding x11-repo..."
        pkg install -y x11-repo </dev/null 2>&1 || true
    fi

    pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true

    # virgl renderer + Mesa Zink (OpenGL over Vulkan bridge)
    pkg install -y mesa-zink virglrenderer-mesa-zink vulkan-loader-android virglrenderer-android vulkan-headers vulkan-tools </dev/null 2>&1 || {
        echo "⚠️  Some GPU packages may have failed (continuing...)"
    }

    # Turnip: open-source Vulkan driver for Adreno 6xx/7xx
    apt install -y mesa-vulkan-icd-freedreno-dri3 </dev/null 2>&1 || {
        echo "⚠️  Turnip ICD install had issues (continuing...)"
    }

    # ninja (needed to build shaderc)
    pkg install -y ninja </dev/null 2>&1 || true

    echo "✅ GPU packages installed."
fi

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
    echo "1) Gemma-4-E2B-IT (unsloth UD_Q4_K_XL, Size: 3.17 GB )"
    echo "2) Gemma-4-E4B-IT (unsloth UD_Q4_K_XL, Size: 5.1 GB )"
    echo "3) Custom GGUF URL (Enter your own model link from HuggingFace)"
    read -p "Select corresponding index (1/2/3): " MODEL_INDEX

    case "$MODEL_INDEX" in
        1)
            PRIMARY_URL="https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-UD-Q4_K_XL.gguf"
            PRIMARY_FILE="gemma-4-E2B-it-UD-Q4_K_XL.gguf"
            VISION_URL="https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-BF16.gguf"
            VISION_FILE="mmproj-BF16.gguf"
            ;;
        2)
            PRIMARY_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/blob/main/gemma-4-E4B-it-UD-Q4_K_XL.gguf"
            PRIMARY_FILE="gemma-4-E4B-it-UD-Q4_K_XL.gguf"
            VISION_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/blob/main/mmproj-BF16.gguf"
            VISION_FILE="mmproj-BF16.gguf"
            ;;
        3)
            read -p "Input Model GGUF URL (HuggingFace): " PRIMARY_URL
            read -p "Save as filename (leave blank to use original name from URL): " PRIMARY_FILE

            read -p "Does this model require a Vision (mmproj) module? (y/n): " IS_VISION
            if [ "$IS_VISION" == "y" ]; then
                read -p "Input Vision mmproj URL: " VISION_URL
                read -p "Save vision file as (leave blank to use original name): " VISION_FILE
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

    # Normalize all HuggingFace URLs: /blob/ → /resolve/ (applies to all models including presets)
    PRIMARY_URL=$(echo "$PRIMARY_URL" | sed 's/\/blob\//\/resolve\//g')
    [ -n "$VISION_URL" ] && VISION_URL=$(echo "$VISION_URL" | sed 's/\/blob\//\/resolve\//g')

    # Derive filenames from URL if user left them blank
    if [ -z "$PRIMARY_FILE" ]; then
        PRIMARY_FILE=$(basename "$PRIMARY_URL" | cut -d'?' -f1)
        echo "Note: Model will be saved as: ${PRIMARY_FILE}"
    fi
    if [ -n "$VISION_URL" ] && [ -z "$VISION_FILE" ]; then
        VISION_FILE=$(basename "$VISION_URL" | cut -d'?' -f1)
        echo "Note: Vision module will be saved as: ${VISION_FILE}"
    fi
fi

echo ""
echo "Note: Officially 'gated' models (Llama/Gemma) require a HuggingFace Access Token."
echo "If you selected Qwen or a public community model (Option 4), you can just press Enter to skip."
read -p "Input HuggingFace Token (hf_...): " HF_TOKEN


# ==========================================
# 4. Engine Procurement & Model Metadata
# ==========================================
if [ ! -d "$HOME/llama.cpp" ]; then
    echo "Cloning Llama.cpp engine repository..."
    cd "$HOME"
    git clone https://github.com/ggerganov/llama.cpp
fi

if [ "$PRIMARY_URL" != "local_skip" ]; then

    echo "Downloading target inference weights..."
    mkdir -p "$HOME/llama.cpp/models"
    cd "$HOME/llama.cpp/models"

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
else
    echo "Notice: Using existing model file. Skipping download step."
fi

# ==========================================
# 5. Engine Compilation (IRONCLAD GUARD)
# ==========================================
BUILD_NEEDED=false

if [ ! -f "$HOME/llama.cpp/build/bin/llama-server" ]; then
    BUILD_NEEDED=true
else
    echo ""
    echo "========================================================"
    echo "✅ ENGINE DETECTED: llama-server binary already exists."
    echo "========================================================"
    echo "1) Skip  - Use existing binary (Recommended)"
    echo "2) Rebuild - Delete existing build and recompile from source"
    read -p "Select option (1/2): " REBUILD_CHOICE
    if [ "$REBUILD_CHOICE" == "2" ]; then
        echo "Removing existing build directory..."
        rm -rf "$HOME/llama.cpp/build"
        BUILD_NEEDED=true
        echo "Build directory cleared. Proceeding with fresh compilation..."
    else
        echo "Skipping compilation. Using existing binary."
    fi
fi

if [ "$BUILD_NEEDED" = true ]; then

    # Install build-specific dependencies
    pkg install -y libexpat </dev/null 2>&1

    # -------------------------------------------------------
    # Helper: CPU-only llama-server build.
    # Called by any failure path and the initial CPU (n) path.
    # -------------------------------------------------------
    _build_cpu_llama() {
        cd ~/llama.cpp
        rm -rf build
        mkdir -p build
        echo "Starting CPU-only compilation (this will take a while)..."
        cmake -B build -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF
        if cmake --build build --config Release --target llama-server; then
            echo "✅ CPU llama-server compilation successful."
        else
            echo "❌ ERROR: CPU build failed. Terminating."
            exit 1
        fi
    }

    export LDFLAGS="-landroid-spawn"
    GPU_FAILED=false  # Tracks whether a GPU path was attempted and failed

    # === GPU Path 1: Build glslc (GLSL shader compiler) ===
    if [ "$USE_GPU" = true ]; then
        if ! command -v glslc > /dev/null 2>&1; then
            echo ""
            echo "========================================================"
            echo "🔨 Building glslc (GLSL Shader Compiler)..."
            echo "   This is a one-time build (~15-30 min). Please wait."
            echo "========================================================"

            cd $HOME
            if [ ! -d "shaderc" ]; then
                git clone --recursive https://github.com/google/shaderc
            fi
            cd shaderc
            mkdir -p build
            cd build
            cmake .. -G Ninja \
              -DCMAKE_BUILD_TYPE=Release \
              -DSHADERC_SKIP_TESTS=ON
            if ninja glslc_exe; then
                cp ~/shaderc/build/glslc/glslc $PREFIX/bin/glslc
                echo "✅ glslc installed: $(glslc --version)"
            else
                echo "❌ glslc build failed."
                GPU_FAILED=true
                USE_GPU=false
            fi
        else
            echo "✅ glslc already available: $(glslc --version)"
        fi
    fi

    # === GPU Path 2: Vulkan cmake ===
    # (Separate block — correctly reads USE_GPU even if Path 1 changed it)
    if [ "$USE_GPU" = true ]; then
        cd ~/llama.cpp
        mkdir -p build
        echo "Starting GPU-accelerated compilation (Vulkan + Turnip)..."
        cmake -B build \
          -DLLAMA_BUILD_SERVER=ON \
          -DLLAMA_BUILD_TESTS=OFF \
          -DGGML_VULKAN=ON \
          -DVulkan_GLSLC_EXECUTABLE="$PREFIX/bin/glslc"
        if cmake --build build --config Release --target llama-server; then
            echo "✅ GPU (Vulkan) llama-server compilation successful."
        else
            echo ""
            echo "❌ Vulkan GPU build failed."
            echo "This may be caused by missing driver headers or an incompatible Vulkan ICD."
            rm -rf build   # clear failed GPU artifacts
            GPU_FAILED=true
            USE_GPU=false
        fi
    fi

    # === CPU Path ===
    # (a) GPU=n from start → GPU_FAILED=false → build directly
    # (b) glslc failed     → GPU_FAILED=true  → ask user
    # (c) Vulkan failed    → GPU_FAILED=true  → ask user
    if [ "$USE_GPU" = false ]; then
        if [ "$GPU_FAILED" = true ]; then
            echo ""
            echo "========================================================"
            echo "⚠️  GPU acceleration failed. Continue with CPU-only inference?"
            echo "   CPU inference is slower but fully stable."
            echo "========================================================"
            read -p "Continue with CPU-only build? (y/n): " COMPROMISE_CHOICE
            if [ "$COMPROMISE_CHOICE" == "y" ]; then
                _build_cpu_llama
            else
                echo "Terminating as requested."
                exit 1
            fi
        else
            _build_cpu_llama
        fi
    fi
fi


# ==========================================
# 6. OpenClaw Procurement
# ==========================================
echo "Installing OpenClaw Vision Processor framework..."

if command -v openclaw &>/dev/null || [ -d "$HOME/.openclaw/repo" ]; then
    echo "✅ Notice: OpenClaw already installed. Skipping installation."
else
    echo "Installing OpenClaw..."
    bash -c "$(curl -sSL https://myopenclawhub.com/install)" < /dev/tty && source ~/.bashrc 2>/dev/null
fi

# Self-Diagnostic
if command -v openclaw &>/dev/null; then
    echo "========================================================"
    echo "✅ OpenClaw successfully verified."
    echo "========================================================"
else
    echo "❌ ERROR: OpenClaw installation failed."
    exit 1
fi

# ==========================================
# 7. openclaw-local Wrapper (Local LLM Bridge)
# ==========================================
echo "Creating openclaw-local inference bridge..."
cat << 'EOF' > $PREFIX/bin/openclaw-local
#!/data/data/com.termux/files/usr/bin/bash
# openclaw-local: Wrapper that forces OpenClaw to use the local llama-server
# instead of external cloud APIs.
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="local-bypass"
export OPENAI_MODEL="local-model"

echo "Initializing OpenClaw mapped to local inference backbone (127.0.0.1:8080)..."
openclaw "$@"
EOF
chmod +x $PREFIX/bin/openclaw-local

# ==========================================
# 8. AI Brain: Phone Control & Memory Injection
# ==========================================
echo "Injecting AI phone control scripts and memory files..."

# Unified phone control script (rish -> adb -> su fallback chain)
cat > $HOME/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CMD="$1"
shift

run_cmd() {
  if command -v rish &>/dev/null; then
    rish -c "$@"
  elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
    adb shell "$@"
  elif command -v su &>/dev/null; then
    su -c "$@"
  else
    echo "❌ Error: No control method available. Please start Shizuku first."
    exit 1
  fi
}

case "$CMD" in
  screenshot)
    run_cmd "screencap -p '${1:-/sdcard/screenshot.png}'"
    ;;
  open-app)
    run_cmd "monkey -p $1 -c android.intent.category.LAUNCHER 1" 2>/dev/null
    ;;
  youtube-search)
    QUERY=$(echo "$*" | sed 's/ /+/g')
    run_cmd "am start -a android.intent.action.VIEW -d 'https://www.youtube.com/results?search_query=$QUERY' com.google.android.youtube"
    ;;
  open-url)
    run_cmd "am start -a android.intent.action.VIEW -d '$1'"
    ;;
  wifi)
    if [ "$1" = "on" ]; then run_cmd "svc wifi enable"; else run_cmd "svc wifi disable"; fi
    ;;
  battery)
    run_cmd "dumpsys battery" | grep "level"
    ;;
  tap)
    run_cmd "input tap $1 $2"
    ;;
  swipe)
    run_cmd "input swipe $1 $2 $3 $4 ${5:-500}"
    ;;
  text)
    run_cmd "input text '$*'"
    ;;
  key)
    run_cmd "input keyevent $1"
    ;;
  home)       run_cmd "input keyevent 3" ;;
  back)       run_cmd "input keyevent 4" ;;
  recent)     run_cmd "input keyevent 187" ;;
  power)      run_cmd "input keyevent 26" ;;
  volume-up)  run_cmd "input keyevent 24" ;;
  volume-down) run_cmd "input keyevent 25" ;;
  screenon)   run_cmd "input keyevent 224" ;;
  ui-dump)
    run_cmd "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1"
    node -e "
      const fs = require('fs');
      try {
        const xml = fs.readFileSync('/sdcard/window_dump.xml', 'utf8');
        const regex = /(?:text|content-desc)=\\\"([^\\\"]+)\\\"[^>]*bounds=\\\"(\\[[0-9]+,[0-9]+\\]\\[[0-9]+,[0-9]+\\])\\\"/g;
        let match;
        while ((match = regex.exec(xml)) !== null) {
          if (match[1].trim() !== '') console.log(match[2] + ' ' + match[1]);
        }
      } catch(e) { console.log('Error reading UI dump'); }
    "
    ;;
  shell)
    run_cmd "$*"
    ;;
  *)
    echo "Usage: bash phone_control.sh [battery|wifi|open-url|open-app|youtube-search|screenshot|tap|swipe|text|key|home|back|recent|power|volume-up|volume-down|screenon|ui-dump|shell]"
    ;;
esac
EOF
chmod +x $HOME/phone_control.sh

# AI Memory & Behavior Configuration
mkdir -p $HOME/.openclaw/workspace 2>/dev/null || true

cat > $HOME/.openclaw/workspace/IDENTITY.md << 'EOF'
- **Name:** PhoneBot
I am an Autonomous AI Agent running natively on an Android phone via Termux + Shizuku.
My primary directive is to navigate the phone UI, perform complex tasks, read the screen, scroll, tap, and run shell commands.
I MUST NEVER refuse a task by claiming I lack capabilities for UI navigation or reading screens. I strictly possess these capabilities via my bash tools.
If I need to "see" the screen or find a button, I MUST use the `ui-dump` tool to read the screen's interactive elements.
EOF

cat > $HOME/.openclaw/workspace/TOOLS.md << 'EOF'
# TOOLS.md
I have full control over this Android phone using `~/phone_control.sh`.

CRITICAL RULES:
1. NEVER say "I cannot navigate UIs" or "I cannot read UIs". YOU CAN.
2. To read the screen or find buttons, ALWAYS run `bash ~/phone_control.sh ui-dump` first.
   Output format: `[x1,y1][x2,y2] ElementText`
3. Read the output, find your target, calculate the center X/Y of its bounds, then tap it.

Available Commands:
- `bash ~/phone_control.sh ui-dump`              - Read the screen. ALWAYS use this to find elements.
- `bash ~/phone_control.sh tap X Y`              - Tap screen at X/Y coordinates.
- `bash ~/phone_control.sh swipe X1 Y1 X2 Y2`   - Swipe (scroll down: swipe 500 1500 500 500).
- `bash ~/phone_control.sh text "string"`        - Type text into a focused field.
- `bash ~/phone_control.sh key KEYCODE`          - Send keycode (66=Enter, 4=Back, 3=Home).
- `bash ~/phone_control.sh open-app PKG_NAME`    - Launch an app by package name.
- `bash ~/phone_control.sh shell "COMMAND"`      - Run ANY arbitrary shell command.
- `bash ~/phone_control.sh screenshot /sdcard/s.png` - Take a screenshot.

EXAMPLE WORKFLOW (Settings -> Dark Mode):
1. `bash ~/phone_control.sh open-app com.android.settings`
2. `bash ~/phone_control.sh ui-dump`
3. Spot `[100,500][400,600] Display` -> center is (250, 550)
4. `bash ~/phone_control.sh tap 250 550`
5. `bash ~/phone_control.sh ui-dump` -> repeat until the task is done!
EOF

cat > $HOME/.openclaw/workspace/AGENTS.md << 'EOF'
I execute terminal commands directly and parse their output.
I am an autonomous agent. I must chain tool executions until the user's ultimate goal is fully achieved.

CRITICAL: DO NOT STOP AFTER ONE TOOL CALL!
Small models tend to open an app and immediately say "I opened it, please do the rest yourself." YOU MUST NOT DO THIS.

You must loop your tool calls continuously:
1. Call exec -> open app
2. WAIT FOR RESULT (Do not write a message to the user yet!)
3. Call exec -> ui-dump
4. WAIT FOR RESULT -> Parse the element list
5. Call exec -> tap X Y on the target element
6. Repeat steps 3-5 until the requested task is FULLY COMPLETE.

ONLY write a message to the user when the final goal is 100% achieved.
EOF

# ==========================================
# 9. Start-Sequence Architecting
# ==========================================
# Resolve GPU layer flag for start script (baked in at install time)
if [ "$USE_GPU" = true ]; then
    GPU_LAYERS_FLAG="-ngl 99"
else
    GPU_LAYERS_FLAG=""
fi

echo "Finalizing standard execution architecture..."
cat << EOF > $HOME/start-overlayd.sh
#!/data/data/com.termux/files/usr/bin/bash
echo "Initiating Overlayd-AI Systems..."

# Keep Termux alive in the background (prevents Android from killing processes)
termux-wake-lock

# Runtime environment: Node.js IPv4 DNS fix + local LLM endpoint
export NODE_OPTIONS=--dns-result-order=ipv4first
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="local-bypass"
export OPENAI_MODEL="local-model"

# ── GPU Runtime Setup ────────────────────────────────────────────────────────
if [ -n "${GPU_LAYERS_FLAG}" ]; then
    echo "Setting up Vulkan GPU backend (Turnip / Adreno)..."

    # Turnip ICD path
    export VK_ICD_FILENAMES=${PREFIX}/share/vulkan/icd.d/freedreno_icd.aarch64.json
    export TU_DEBUG=noconform

    # Start virgl_test_server in Zink mode (bridges OpenGL -> Vulkan -> Turnip)
    # Required for any GPU-accelerated display rendering.
    killall virgl_test_server 2>/dev/null || true
    MESA_NO_ERROR=1 \\
    MESA_GL_VERSION_OVERRIDE=4.3COMPAT \\
    MESA_GLES_VERSION_OVERRIDE=3.2 \\
    GALLIUM_DRIVER=zink \\
    ZINK_DESCRIPTORS=lazy \\
    virgl_test_server --use-egl-surfaceless --use-gles > /dev/null 2>&1 &
    sleep 2
    echo "✅ GPU backend ready."
fi
# ─────────────────────────────────────────────────────────────────────────────

cd ~/llama.cpp

# Intelligent Vision Detection: Gemma-4/Qwen-VL compatibility
if [ -n "$VISION_FILE" ] && [ -f "models/${VISION_FILE}" ]; then
    echo "========================================================"
    echo "🎥 MULTIMODAL MODE ACTIVATED: Loading ${VISION_FILE}"
    echo "========================================================"
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} --mmproj models/${VISION_FILE} ${GPU_LAYERS_FLAG} -t 4 -c 4096 --port 8080 > ~/overlayd_server.log 2>&1 &
else
    echo "========================================================"
    echo "📝 TEXT-ONLY MODE: No vision module detected."
    echo "========================================================"
    ./build/bin/llama-server --host 0.0.0.0 -m models/${PRIMARY_FILE} ${GPU_LAYERS_FLAG} -t 4 -c 2048 --port 8080 > ~/overlayd_server.log 2>&1 &
fi

OVERLAYD_PID=\$!

echo "Allocating inference model into system memory (15s)..."
sleep 15

echo "Starting OpenClaw Gateway via local inference bridge..."
cd ~
openclaw-local start > ~/openclaw.log 2>&1 &
CLAW_PID=\$!

echo ""
echo "✅ System active."
echo "   Web UI (local):   http://127.0.0.1:3000"
echo "   Web UI (network): http://PHONE_IP:3000"
echo "   To configure:     openclaw onboard"
echo ""

wait \$OVERLAYD_PID \$CLAW_PID
EOF
chmod +x $HOME/start-overlayd.sh

echo ""
source ~/.bashrc 2>/dev/null

echo "Installation structure successfully resolved."
echo "Execute the system sequence via the following command:"
echo "bash ~/start-overlayd.sh"
echo "Note: The OpenClaw execution environment can be triggered manually via 'openclaw onboard'."
echo ""
echo "System deployment finished."
