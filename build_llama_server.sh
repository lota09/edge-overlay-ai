#!/usr/bin/env bash
set -e

# ==========================================
# 1. Essential Tool Check & Env
# ==========================================
echo "========================================================"
echo "🔨 Building llama.cpp server for Termux"
echo "========================================================"
MISSING_TOOLS=""
for cmd in clang cmake node python wget git make bison flex; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS $cmd"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo "⚠️  Missing tools:$MISSING_TOOLS — Installing all required packages..."
    pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true
    pkg install -y clang cmake nodejs python wget git libandroid-spawn make bison flex </dev/null 2>&1 || true
fi

# ==========================================
# 2. GPU Acceleration Configuration
# ==========================================
echo ""
echo "========================================================"
echo "🎮 GPU Acceleration (Vulkan / Adreno)"
echo "========================================================"
read -p "Enable Vulkan GPU acceleration? (y/n): " USE_GPU_CHOICE

USE_GPU=false
if [ "$USE_GPU_CHOICE" == "y" ]; then
    USE_GPU=true
    echo "✅ GPU acceleration enabled. Installing GPU packages..."
    
    if ! pkg list-installed 2>/dev/null | grep -q "^tur-repo"; then
        pkg install -y tur-repo </dev/null 2>&1 || true
    fi
    if ! pkg list-installed 2>/dev/null | grep -q "^x11-repo"; then
        pkg install -y x11-repo </dev/null 2>&1 || true
    fi
    pkg update -y </dev/null 2>&1 || true
    pkg install -y mesa-zink virglrenderer-mesa-zink virglrenderer-android vulkan-headers vulkan-tools spirv-headers spirv-tools </dev/null 2>&1 || true
    apt install -y mesa-vulkan-icd-freedreno-dri3 </dev/null 2>&1 || true
    pkg install -y ninja </dev/null 2>&1 || true
    echo "✅ GPU packages installed."
else
    echo "⏩ GPU acceleration skipped. Defaulting to CPU-only inference."
fi

# ==========================================
# 3. Source Procurement
# ==========================================
cd "$HOME"
if [ ! -d "llama.cpp" ]; then
    echo "Cloning Llama.cpp engine repository..."
    git clone https://github.com/ggerganov/llama.cpp
fi

# ==========================================
# 4. Engine Compilation
# ==========================================
cd "$HOME/llama.cpp"
BUILD_NEEDED=true
if [ -d "build" ]; then
    echo ""
    read -p "Existing build detected. Rebuild from scratch? (y/n): " REBUILD
    if [ "$REBUILD" == "y" ]; then
        rm -rf build
    else
        BUILD_NEEDED=false
    fi
fi

if [ "$BUILD_NEEDED" = true ]; then
    pkg install -y libexpat </dev/null 2>&1 || true

    _build_cpu_llama() {
        echo ""
        echo "========================================================"
        echo "🔨 Building llama_server (CPU Only)..."
        echo "========================================================"
        mkdir -p build && cd build
        cmake .. -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF
        if cmake --build . --config Release --target llama-server -j4; then
            echo "✅ CPU build complete!"
        else
            echo "❌ CRITICAL ERROR: CPU build failed."
            exit 1
        fi
        cd ..
    }

    export LDFLAGS="-landroid-spawn"
    GPU_FAILED=false

    # GPU Path 1: glslc dependencies
    if [ "$USE_GPU" = true ]; then
        if ! command -v glslc > /dev/null 2>&1; then
            echo ""
            echo "========================================================"
            echo "🔨 Building glslc (GLSL Shader Compiler) for GPU..."
            echo "   This is a one-time build (~15-30 min). Please wait."
            echo "========================================================"
            cd $HOME
            if [ ! -d "shaderc" ]; then
                git clone --recursive https://github.com/google/shaderc
            fi
            cd shaderc
            echo "Syncing third-party dependencies for shaderc..."
            ./utils/git-sync-deps
            rm -rf build && mkdir -p build && cd build
            cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON
            if ninja glslc_exe; then
                cp ~/shaderc/build/glslc/glslc $PREFIX/bin/glslc
                echo "✅ glslc installed."
            else
                echo "❌ glslc build failed."
                GPU_FAILED=true
                USE_GPU=false
            fi
            cd $HOME/llama.cpp
        fi
    fi

    # GPU Path 2: llama.cpp Vulkan compilation
    if [ "$USE_GPU" = true ]; then
        echo ""
        echo "========================================================"
        echo "🔨 Building llama_server (Vulkan GPU Acceleration)..."
        echo "========================================================"
        mkdir -p build && cd build
        cmake .. \
          -DLLAMA_BUILD_SERVER=ON \
          -DLLAMA_BUILD_TESTS=OFF \
          -DGGML_VULKAN=ON \
          -DVulkan_GLSLC_EXECUTABLE="$PREFIX/bin/glslc"
          
        if cmake --build . --config Release --target llama-server -j4; then
            echo "✅ Vulkan GPU build complete!"
        else
            echo ""
            echo "❌ Vulkan GPU build failed."
            rm -rf ./*  # clear failed GPU artifacts inside build dir
            cd ..
            GPU_FAILED=true
            USE_GPU=false
        fi
    fi

    # CPU Fallback Path
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
else
    echo "Skipping build phase."
fi

echo ""
echo "✅ Build script finished successfully. Executable is at ~/llama.cpp/build/bin/llama-server"
