#!/usr/bin/env bash
set -e

# ==========================================
# Native-binary linkage guard
# ==========================================
# Termux ships prebuilt ARM64 binaries (cmake, ninja, clang, ...) that are
# dynamically linked against Termux's own libc/libexpat/etc. `command -v`
# only checks that a file exists and is +x — it does NOT catch the very
# common Android/Termux failure mode where the binary is present but the
# dynamic linker can't resolve a dependency, e.g.:
#
#   CANNOT LINK EXECUTABLE "cmake": library "libexpat.so.1" not found:
#   needed by main executable
#
# This happens even when `pkg`/`dpkg` insist the library is installed:
#   1. A partial/interrupted `pkg upgrade` leaves version-skewed packages
#      (cmake rebuilt against a newer libexpat than what's on disk).
#   2. The .so file exists on disk but is unreadable in THIS session even
#      though `stat` on the concrete filename looks completely normal —
#      seen when Termux is reached over SSH / a chroot layer whose
#      SELinux or UID context differs from a plain foreground Termux
#      session (readlink() on the versioned symlink gets EACCES while a
#      direct stat of the target file still succeeds).
#
# ensure_native_binary_works <command> [package-name]
#   Actually *executes* the binary (not just checks its existence),
#   attempts a bounded self-heal via reinstall on failure, and — if that
#   doesn't fix it — fails loudly with a clear diagnosis instead of
#   silently ploughing into a 15-30 minute build that's doomed to fail.
# ==========================================
ensure_native_binary_works() {
    local bin="$1"
    local pkg="${2:-$1}"
    local out attempt=1

    if ! command -v "$bin" > /dev/null 2>&1; then
        echo "Installing $pkg (provides $bin)..."
        pkg install -y "$pkg" </dev/null 2>&1 || true
    fi

    for attempt in 1 2 3; do
        # NOTE: the version check must live inside the `if` condition itself
        # (not `out=$(...)` followed by a separate `[ $? -eq 0 ]`) — under
        # `set -e` a failing command substitution on its own line aborts the
        # whole script before we ever get to inspect the exit status.
        if out=$("$bin" --version 2>&1); then
            [ "$attempt" -gt 1 ] && echo "✅ $bin recovered after reinstalling $pkg."
            return 0
        fi

        if ! printf '%s\n' "$out" | grep -q "CANNOT LINK EXECUTABLE"; then
            echo "❌ '$bin --version' failed unexpectedly:"
            printf '%s\n' "$out" | sed 's/^/    /'
            return 1
        fi

        local missing_lib
        missing_lib=$(printf '%s\n' "$out" | sed -n 's/.*library "\([^"]*\)".*/\1/p')
        echo "⚠️  '$bin' can't dynamically link (attempt $attempt/3) — missing: ${missing_lib:-unknown}"
        echo "    Repairing package '$pkg'..."

        pkg update -y </dev/null >/dev/null 2>&1 || true
        apt install --reinstall -y "$pkg" </dev/null 2>&1 || true
    done

    echo ""
    echo "========================================================"
    echo "❌ '$bin' still cannot run after $attempt repair attempts."
    echo "========================================================"
    echo "This is usually NOT a missing package — apt/pkg reports the"
    echo "dependency as installed, but this process can't actually use it."
    echo "Known causes on Android/Termux:"
    echo "  • Running via SSH into a chroot / dual-app / second-space layer"
    echo "    whose SELinux or UID mapping differs from a plain foreground"
    echo "    Termux session — try running this script directly inside the"
    echo "    Termux app on-device instead of over SSH."
    echo "  • A background/foreground SELinux domain difference — fully"
    echo "    close and reopen the Termux app, then reconnect and retry."
    echo "  • Corrupted package cache — try:"
    echo "      pkg clean && rm -rf \$PREFIX/var/lib/apt/lists/* && pkg update -y"
    echo "========================================================"
    return 1
}

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

# Verify each tool actually RUNS (not just that the file exists and is +x).
# `command -v` can't catch Android's "CANNOT LINK EXECUTABLE" failure mode
# — see ensure_native_binary_works() above for why this matters.
BROKEN_TOOLS=""
for cmd in clang cmake node python wget git make bison flex; do
    pkg_for_cmd="$cmd"
    [ "$cmd" = "node" ] && pkg_for_cmd="nodejs"
    if ! ensure_native_binary_works "$cmd" "$pkg_for_cmd"; then
        BROKEN_TOOLS="$BROKEN_TOOLS $cmd"
    fi
done

if [ -n "$BROKEN_TOOLS" ]; then
    echo ""
    echo "❌ ERROR: These tools are broken and automatic repair didn't fix them:$BROKEN_TOOLS"
    echo "   Resolve the issue diagnosed above and re-run this script."
    echo "   Terminating now instead of wasting time on a doomed build."
    exit 1
fi
echo "✅ All essential tools verified working."

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
    # Install build-specific dependencies and verify the toolchain still
    # links correctly — the GPU package installs above can shift shared
    # library versions (e.g. cmake vs libexpat) even if the earlier check
    # passed.
    pkg install -y libexpat </dev/null 2>&1 || true
    if ! ensure_native_binary_works cmake cmake; then
        echo "❌ ERROR: cmake is broken and automatic repair failed. Aborting before build."
        exit 1
    fi

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

            # cmake/ninja can break between the earlier check and now —
            # GPU package installs above touch shared libs. Re-verify
            # before sinking 15-30 min into a build that's doomed to fail.
            if ! ensure_native_binary_works cmake cmake || ! ensure_native_binary_works ninja ninja; then
                echo "❌ glslc build aborted: cmake/ninja toolchain is broken (see diagnosis above)."
                GPU_FAILED=true
                USE_GPU=false
            else
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
