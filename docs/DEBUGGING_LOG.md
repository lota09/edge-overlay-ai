## 📝 디버깅 기록: Termux Native에서 glmark2 GPU 가속 활성화

---

### 🔴 문제 1: `glmark2` 실행 시 `Error: main: Could not initialize canvas`

#### 1️⃣ 어떤 문제가 있었나
- Termux native 환경에서 `glmark2`를 실행하면 `Could not initialize canvas` 에러로 즉시 종료.
- `MESA_LOADER_DRIVER_OVERRIDE=zink glmark2` 로 실행해도 동일하게 실패하거나, 성공해도 `GL_RENDERER: llvmpipe (LLVM 11.1.0)` — CPU 소프트웨어 렌더러가 사용됨.

#### 2️⃣ 어떤 시도를 해보았는가
- `MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform glmark2` 시도 → llvmpipe 출력.
- DISPLAY 변수 확인 → `DISPLAY=` (비어 있었음).
- `virgl_test_server_android &` 실행 후 glmark2 재시도 → canvas 오류 지속.

#### 3️⃣ 어느 순간 깨달았는가
- `DISPLAY` 환경 변수가 설정되어야 X11 기반 glmark2가 디스플레이를 찾을 수 있음.
- Termux:X11 앱을 통해 XFCE4 데스크탑 세션을 먼저 시작하면 `DISPLAY=:0.0`으로 설정됨.
- 단, `MESA_LOADER_DRIVER_OVERRIDE=zink` (Turnip용 변수)가 아니라 `GALLIUM_DRIVER=zink` (Mesa Gallium 드라이버 선택 변수)가 Termux native에서는 정확한 변수임.
- virgl_test_server도 단순히 Android용이 아닌 **Zink 모드(`--use-egl-surfaceless --use-gles`)** 로 시작해야 GPU 백엔드로 연결됨.

#### 4️⃣ 어떻게 해결했는가
- **해결책**:
  1. Termux:X11 + XFCE4로 X11 디스플레이 세션 활성화 (`DISPLAY=:0.0` 확인).
  2. virgl_test_server를 Zink 모드로 시작:
     ```bash
     MESA_NO_ERROR=1 MESA_GL_VERSION_OVERRIDE=4.3COMPAT \
     MESA_GLES_VERSION_OVERRIDE=3.2 GALLIUM_DRIVER=zink \
     ZINK_DESCRIPTORS=lazy \
     virgl_test_server --use-egl-surfaceless --use-gles &
     ```
  3. glmark2 실행: `GALLIUM_DRIVER=zink MESA_GL_VERSION_OVERRIDE=4.0 glmark2`
- **결과**: ✅ `GL_RENDERER: zink (Turnip Adreno (TM) 650)` 출력, FPS 약 289 (vs llvmpipe 117).

---

### 🔴 문제 2: `vulkaninfo` 로 Turnip이 안 보임 (설치 직후)

#### 1️⃣ 어떤 문제가 있었나
- `mesa-vulkan-icd-freedreno-dri3` 패키지 설치 후 `vulkaninfo 2>/dev/null | grep deviceName` 실행 시 아무 출력 없음.
- `/dev/kgsl-3d0` 는 `crw-rw-rw-` 권한으로 접근 가능했음.

#### 2️⃣ 어떤 시도를 해보았나
- `VK_LOADER_DEBUG=all vulkaninfo --summary` 실행 → loader가 ICD를 찾지 못하는 로그.
- `vulkan-icd` 패키지 설치 (`apt install vulkan-icd`) → 설치 성공.

#### 3️⃣ 어느 순간 깨달았는가
- `mesa-vulkan-icd-freedreno-dri3` 만으로는 Vulkan loader가 ICD JSON을 자동 등록하지 못하는 경우가 있음.
- `vulkan-icd` 패키지가 시스템 ICD 탐색 경로를 올바르게 구성해줌.

#### 4️⃣ 어떻게 해결했는가
- **해결책**: `apt install vulkan-icd` 추가 설치.
- **결과**: ✅ `vulkaninfo` 에서 `deviceName = Turnip Adreno (TM) 650`, `driverID = DRIVER_ID_MESA_TURNIP`, `driverInfo = Mesa 26.0.4` 확인.

---

### 🔴 문제 3: llama.cpp Vulkan 빌드 실패 — `Could NOT find Vulkan (missing: glslc)`

#### 1️⃣ 어떤 문제가 있었나
- `cmake -DGGML_VULKAN=ON` 실행 시 아래 오류 발생:
  ```
  CMake Error: Could NOT find Vulkan (missing: Vulkan_LIBRARY glslc) (found version "1.4.349")
  ```
- `vulkan-headers` 는 설치되어 있었으나 `glslc` 바이너리가 없음.

#### 2️⃣ 어떤 시도를 해보았나
- `pkg install vulkan-tools` → `glslc` 미포함.
- `pkg search glslc` → Termux 공식 저장소에 패키지 없음.

#### 3️⃣ 어느 순간 깨달았는가
- `glslc`는 Google의 `shaderc` 프로젝트에 포함된 GLSL 셰이더 컴파일러로, Termux 저장소에 패키지화되어 있지 않음.
- 직접 소스에서 빌드해야 하며, `cmake -DVulkan_GLSLC_EXECUTABLE=<경로>` 로 경로를 cmake에 명시해야 함.

#### 4️⃣ 어떻게 해결했는가
- **해결책**:
  ```bash
  git clone --recursive https://github.com/google/shaderc
  cd shaderc && mkdir build && cd build
  cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON
  ninja glslc_exe
  cp ~/shaderc/build/glslc/glslc $PREFIX/bin/glslc
  ```
  cmake 실행 시 `-DVulkan_GLSLC_EXECUTABLE="$PREFIX/bin/glslc"` 추가.
- **결과**: ✅ cmake Vulkan 탐색 통과. (llama.cpp Vulkan 빌드는 이후 진행 예정)

---

### 🔴 문제 4: CMake가 llama.cpp 소스를 못 찾음 (`does not appear to contain CMakeLists.txt`)

#### 1️⃣ 어떤 문제가 있었나
- `cmake -B build` 실행 시:
  ```
  CMake Error: The source directory ".../llama.cpp" does not appear to contain CMakeLists.txt.
  ```
- `git clone`으로 정상 클론했음에도 발생.

#### 2️⃣ 어느 순간 깨달았는가
- 모델 다운로드 코드의 `mkdir -p "$HOME/llama.cpp/models"` 가 git clone **이전**에 실행됨.
- 이로 인해 `~/llama.cpp/` 디렉터리가 빈 상태로 먼저 생성되고, 이후 `if [ ! -d "llama.cpp" ]` 조건이 이미 존재한다고 판단하여 git clone을 건너뜀.
- 결과적으로 `CMakeLists.txt` 없는 빈 껍데기 디렉터리만 남음.

#### 4️⃣ 어떻게 해결했는가
- **해결책**: 존재 여부 확인 조건을 `[ ! -d "llama.cpp" ]` → `[ ! -f "$HOME/llama.cpp/CMakeLists.txt" ]` 로 변경.
- **결과**: ✅ cmake가 소스를 정상 인식.

---

## 🎯 핵심 교훈

| 항목 | 교훈 |
|------|------|
| **GALLIUM_DRIVER vs MESA_LOADER_DRIVER_OVERRIDE** | Termux native에서 OpenGL Zink 선택은 `GALLIUM_DRIVER=zink`. Turnip Vulkan 직접 ICD는 `MESA_LOADER_DRIVER_OVERRIDE=zink`. 혼용하면 llvmpipe 폴백. |
| **virgl_test_server 모드** | Android용(`virgl_test_server_android`)과 Zink 모드(`--use-egl-surfaceless --use-gles`)는 다름. GPU 가속에는 후자가 필수. |
| **Samsung GPUWatch 0%** | Turnip은 KGSL 커널 드라이버에 직접 접근. Samsung의 GPUWatch는 Android HAL 레이어를 통해 측정하기 때문에 Termux/Turnip 사용량을 감지하지 못함. `/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage` 로 실제 사용률 확인 필요. |
| **glslc 빌드** | Termux 저장소에 없으므로 shaderc 소스 빌드 필수. 빌드 시간 약 15~30분 소요. |
| **디렉터리 존재 검사** | `mkdir -p`가 실수로 선행되면 `[ ! -d dir ]` 조건이 깨짐. 실제 소스 파일(`CMakeLists.txt` 등)의 존재 여부로 검사해야 안전. |
