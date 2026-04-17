# Termux Native GPU 가속 설정 가이드
> **대상 환경**: Termux native (proot/chroot 없음), Qualcomm Adreno 6xx/7xx (본 문서는 Adreno 650 / SM-N986N 기준)
> **최종 목표**: `GL_RENDERER: zink (Turnip Adreno (TM) 650)` 확인, FPS 향상

---

## ✅ 사전 요건

| 요건 | 확인 방법 |
|------|-----------|
| Termux (F-Droid 버전 권장) | - |
| Qualcomm Adreno 6xx/7xx GPU | `cat /proc/cpuinfo \| grep Hardware` |
| `/dev/kgsl-3d0` 접근 가능 | `ls -la /dev/kgsl-3d0` → `crw-rw-rw-` |
| Termux:X11 앱 설치 | Play Store 또는 GitHub Releases |

---

## 1단계: 패키지 저장소 추가 및 업데이트

`mesa-zink` 등 GPU 관련 패키지는 기본 저장소가 아닌 `tur-repo`에 있습니다.

```bash
# tur-repo 추가 (mesa-zink 등 제공)
pkg install -y tur-repo

# x11-repo 추가 (X11 관련 도구)
pkg install -y x11-repo

# 패키지 목록 업데이트
pkg update -y
```

---

## 2단계: GPU 관련 패키지 설치

```bash
# OpenGL-over-Vulkan 브릿지 (Mesa Zink + virgl)
pkg install -y mesa-zink virglrenderer-mesa-zink vulkan-loader-android virglrenderer-android

# Vulkan 도구 (vulkaninfo 포함)
pkg install -y vulkan-headers vulkan-tools

# Turnip ICD: Adreno GPU용 오픈소스 Vulkan 드라이버 (Mesa 26+)
apt install -y mesa-vulkan-icd-freedreno-dri3

# ICD 로더 등록 (vulkaninfo가 Turnip을 인식하게 함)
apt install -y vulkan-icd
```

---

## 3단계: Turnip 드라이버 인식 확인

```bash
# Vulkan 장치 목록 확인
vulkaninfo 2>/dev/null | grep -iE "deviceName|driverID|driverInfo"
```

**성공 시 출력 예시:**
```
deviceName        = Turnip Adreno (TM) 650
driverID          = DRIVER_ID_MESA_TURNIP
driverInfo        = Mesa 26.0.4
```

출력이 없으면:
```bash
# 디버그 모드로 ICD 탐색 실패 원인 확인
VK_LOADER_DEBUG=all vulkaninfo --summary 2>&1 | grep -iE "error|failed|icd"
```

---

## 4단계: X11 디스플레이 환경 설정

glmark2는 X11 디스플레이가 필요합니다. Termux:X11을 통해 세션을 시작하세요.

### 방법: Termux:X11 + XFCE4

```bash
# xfce4 및 Termux:X11 bridge 설치
pkg install -y xfce4 termux-x11-nightly

# Termux:X11 앱 실행 (Android 화면에서 앱 직접 열기)
# 앱이 실행된 후 Termux 터미널에서:
export DISPLAY=:0
```

또는 `termux_native.md` 가이드의 시작 스크립트를 사용합니다.

### DISPLAY 확인

```bash
echo "DISPLAY=$DISPLAY"
# 출력: DISPLAY=:0.0 (또는 :0)
```

---

## 5단계: virgl_test_server를 Zink(GPU) 모드로 시작

> ⚠️ `virgl_test_server_android` (Android용 기본 실행)와 다릅니다.
> GPU 가속을 위해서는 아래의 **Zink 모드** 실행이 필수입니다.

```bash
# 기존 인스턴스 정리
killall virgl_test_server 2>/dev/null || true

# Zink 모드로 시작 (OpenGL → Vulkan(Zink) → Turnip → Adreno 650)
MESA_NO_ERROR=1 \
MESA_GL_VERSION_OVERRIDE=4.3COMPAT \
MESA_GLES_VERSION_OVERRIDE=3.2 \
GALLIUM_DRIVER=zink \
ZINK_DESCRIPTORS=lazy \
virgl_test_server --use-egl-surfaceless --use-gles > /dev/null 2>&1 &

sleep 2
echo "virgl_test_server (Zink mode) started: PID $!"
```

---

## 6단계: glmark2 GPU 가속 실행

```bash
# Zink(GPU) 모드로 glmark2 실행
GALLIUM_DRIVER=zink MESA_GL_VERSION_OVERRIDE=4.0 glmark2
```

**성공 시 주요 출력:**
```
OpenGL Information
  GL_VENDOR:     Collabora Ltd
  GL_RENDERER:   zink (Turnip Adreno (TM) 650)   ← GPU 사용 확인!
  GL_VERSION:    4.0 (Compatibility Profile) Mesa 22.0.5
  Surface Size:  800x600 windowed

[build] use-vbo=false: FPS: 289 FrameTime: 3.462 ms
```

llvmpipe 대비 FPS 비교:

| 드라이버 | FPS | FrameTime |
|----------|-----|-----------|
| llvmpipe (CPU) | ~117 | ~8.5ms |
| **Turnip/Zink (GPU)** | **~289** | **~3.5ms** |

---

## 7단계: 커널 레벨 GPU 사용률 확인

Samsung의 GPUWatch 앱은 Turnip(KGSL 직접 접근)을 감지하지 못합니다.
실제 GPU 사용률은 커널 sysfs로 확인하세요:

```bash
# 현재 GPU 바쁨 비율 (%)
su -c "cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage"

# 실시간 모니터링 (glmark2 실행 중)
su -c "watch -n 0.5 cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage"
```

glmark2 실행 중 이 값이 0 이상 올라가면 GPU가 실제로 사용 중인 것입니다.

---

## 환경 변수 정리

| 변수 | 역할 | 값 |
|------|------|----|
| `GALLIUM_DRIVER=zink` | Mesa Gallium이 Zink 백엔드 사용 (OpenGL → Vulkan 변환) | Mesa OpenGL 클라이언트에 지정 |
| `MESA_GL_VERSION_OVERRIDE=4.0` | 앱에게 OpenGL 4.0 지원을 알림 | glmark2 등 구버전 GL 요구 앱 |
| `MESA_GL_VERSION_OVERRIDE=4.3COMPAT` | virgl 서버에서 호환 프로파일 4.3 제공 | virgl_test_server 시작 시 |
| `MESA_GLES_VERSION_OVERRIDE=3.2` | GLES 3.2 지원 선언 | virgl_test_server 시작 시 |
| `MESA_NO_ERROR=1` | Mesa 내부 오류 검사 비활성화 (성능 향상) | virgl_test_server 시작 시 |
| `ZINK_DESCRIPTORS=lazy` | Vulkan 디스크립터 풀 지연 생성 (안정성 향상) | virgl_test_server 시작 시 |
| `TU_DEBUG=noconform` | Turnip의 Vulkan 적합성 검사 비활성화 | Turnip 직접 Vulkan 사용 시 |

---

## ❌ 흔한 실수

### `MESA_LOADER_DRIVER_OVERRIDE=zink`를 쓰면 llvmpipe가 나옴
이 변수는 Turnip Vulkan ICD를 직접 호출하는 것이 아니라 Mesa의 GL 드라이버 프로세스를 로드하는 변수입니다. Termux native에서 OpenGL(glmark2)에는 `GALLIUM_DRIVER=zink`를 사용하세요.

### virgl_test_server를 Android 모드로 실행
```bash
# ❌ 잘못된 방법 (Android 소프트웨어 렌더러 사용)
virgl_test_server_android &

# ✅ 올바른 방법 (Zink/GPU 모드)
GALLIUM_DRIVER=zink virgl_test_server --use-egl-surfaceless --use-gles &
```

### DISPLAY 없이 실행
```bash
# ❌ DISPLAY 미설정 → Could not initialize canvas
glmark2

# ✅ X11 세션 시작 후 DISPLAY 설정
export DISPLAY=:0.0
glmark2
```

---

## 관련 파일

- `overlayd-ai.sh` — 위 GPU 설정을 자동화한 설치 스크립트
- `DEBUGGING_LOG.md` — GPU 가속 과정에서 발생한 오류 디버깅 기록
- `HardwareAcceleration.md` — Termux 하드웨어 가속 전반 레퍼런스
