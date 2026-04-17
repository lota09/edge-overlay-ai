# OpenClaw 에이전트 향후 고도화 개발 계획 (Development Plan)

본 문서는 오픈클로 에이전트의 설치 안정화 이후, 스마트폰 UI 제어 능력과 에이전트의 지능을 극대화하기 위한 차세대 설계 로드맵을 정의합니다.

---

## 🚀 핵심 개선 사항

### 1. 지능형 UI 파서 (Intelligent UI Parser)
- **개념**: `phone_control.sh`와 Node.js를 결합한 UI 인식 엔진 구축.
- **상세**: `uiautomator dump`로 추출된 XML 데이터를 검색하여 특정 텍스트(예: "Settings", "Send")의 중앙 좌표를 자동으로 계산.
- **기대 효과**: AI가 수동 좌표 입력 대신 "무엇을 눌러라"는 명령만으로 폰을 제어 가능.

### 2. 에이전트 페르소나 강제 주입 (AI Persona Grounding)
- **개념**: `~/.openclaw/workspace/*.md` 파일을 통한 지식 전이.
- **상세**: `IDENTITY.md`, `TOOLS.md`를 자동 생성하여 AI가 자신의 조작 권한(Screenshot, Tap, Shell)을 명확히 인지하도록 세뇌.
- **기대 효과**: AI의 "권한이 없어서 조작할 수 없다"는 거절 반응(Refusal)을 원천 차단.

### 3. 서비스 구동 지속성 확보 (Persistence Support)
- **개념**: `termux-wake-lock` 및 백그라운드 최적화 적용.
- **상세**: 안드로이드 도즈(Doze) 모드나 메모리 관리자에 의해 에이전트가 종료되지 않도록 웨이크 락을 유지.
- **기대 효과**: 화면이 꺼져 있거나 백그라운드 상태에서도 실시간 에이전트 기능 유지.

### 4. 원클릭 환경 정규화 (Environment Normalization)
- **개념**: DNS 및 레거시 네트워크 인터페이스 모킹(Mocking).
- **상세**: `NODE_OPTIONS=--dns-result-order=ipv4first` 적용 및 가짜 `ifconfig` 주입으로 네트워크 에러 최소화.
- **기대 효과**: API 통신 오류 및 내부 게이트웨이 연결 실패율 0% 도전.

---

## 🛠 적용 시점
위 기능들은 기본 설치 무결성이 확인된 이후, 하이엔드 사용자를 위한 **'에이전트 고도화 옵션'**으로 순차 적용 예정입니다.
