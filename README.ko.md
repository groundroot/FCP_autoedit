<div align="center">

# FCP_autoedit

**파이널 컷 프로용 AI 롱폼 자막 자동 생성 도구**

FCP에서 내보낸 FCPXML을 넣으면 → AI가 음성을 전사하고 정렬해 → 바로 임포트 가능한 자막 파일 2개를 만들어줍니다

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-최적화-FF6B35?style=flat-square&logo=apple&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat-square&logo=python&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

[English →](README.md)

</div>

---

## FCP_autoedit란?

자막이 없는 상태로 내보낸 파이널 컷 프로 프로젝트(`.fcpxmld`)를 입력받아, AI로 음성을 인식·정렬한 뒤 **자막이 삽입된 FCPXML 2개**를 자동으로 생성합니다.

인터뷰·설교·강의 등 **롱폼 영상**에 최적화되어 있습니다.  
자막은 의미 단위로 자연스럽게 끊어지며, 실제 음성 타이밍과 정확하게 일치합니다.

```
입력:  interview_edit.fcpxmld        ← 자막 없는 FCP 프로젝트

출력:  interview_edit_롱폼자막_공백메움.fcpxmld          ← 원본 편집 + 자막
       interview_edit_롱폼자막_공백메움_무음제거.fcpxmld  ← 무음 제거 + 자막
```

---

## 주요 기능

### 한 번 실행으로 결과물 2개

| 결과물 | 설명 |
|--------|------|
| **공백메움** | 원본 컷 편집·타임라인 그대로 유지. 자막은 실제 발화 타이밍을 따름. 문장 사이 침묵은 공백으로 남음(의도적). |
| **무음제거** | 설정 임계값 이상의 무음 구간이 제거되어 타임라인이 압축됨. 자막은 교집합 분배 방식으로 재배치되어 빈 프레임 없이 연속. |

---

### 등급제 자막 분할 — 의미 단위 기반

자막은 글자 수만이 아닌 **의미 단위 경계**에서 끊어집니다.  
세 가지 분할 등급이 우선순위 순서로 적용됩니다:

| 등급 | 조건 단어 예시 | 동작 |
|------|--------------|------|
| **Grade 3** — 종결어미 | `습니다` `합니다` `에요` `네요` `는데요` `거든요` `.` `!` `?` | 최소 글자(8자) 이상이면 **즉시 분할** |
| **Grade 2** — 접속어미 | `고` `서` `해서` `는데` `지만` `면서` `,` | 길이 초과 시 분할 기준으로 사용. 시청자는 "이어진다"는 느낌을 자연스럽게 받음 |
| **Grade 1** — 조사 뒤 | `을` `를` `은` `는` `에서` `로` `까지` | 마지막 수단. `은`·`는` 같은 단독 조사 단어로 끝나는 자막은 생성되지 않음 |

**길이 초과 처리:** 자막이 `max_chars`(기본 27자)를 초과하면, 지금까지 기록된 분할 후보 중 **head 길이가 max_chars 이내이면서 등급이 가장 높은 경계**를 선택해 분할합니다. 분할 후 `i`를 tail 첫 단어로 되돌려 tail이 정상 루프를 다시 거칩니다(tail 쪽 Grade 3 즉시분할 기회 보장).

**해결된 핵심 버그:**
> 음성: `"…나아가야겠다는 생각을 하였습니다 감사합니다"`
>
> ❌ 수정 전: `하였습니다`가 last_break만 기록. `감사합니다`가 마지막 단어이면 두 단어가 합쳐져 → `"하였습니다 감사합니다"` 한 장으로 표시
>
> ✅ 수정 후: `하였습니다` → Grade 3 즉시 분할 → `"생각을 하였습니다"` + `"감사합니다"` 각각 독립 자막 카드

---

### 강제 정렬 타임스탬프 — 시간 재분배 없음

자막의 시작·종료 시간은 **Qwen3-ForcedAligner 단어 타임스탬프를 그대로** 사용합니다.  
글자 수로 시간을 재분배하는 방식은 사용하지 않습니다.

- `--gap-bridge-sec` 이하(기본 0.4초) 미세 끊김은 이어 붙임 (읽기 편의)
- 실제 호흡·침묵은 공백으로 유지 — 자막이 발화 타이밍과 일치

---

### 생성 후 자동 검증

두 결과물 모두 생성 직후 자동으로 검증됩니다:

| 검사 항목 | 결과물 1 | 결과물 2 |
|-----------|----------|----------|
| caption 개수 > 0 | ✓ 필수 | ✓ 필수 |
| 자막 겹침 없음 | ✓ | ✓ |
| 줄바꿈 없음(한 줄) | ✓ | ✓ |
| 빈 자막 텍스트 없음 | ✓ | ✓ |
| 클립 경계 이탈 없음 | ✓ | ✓ |
| 자막 사이 공백 | ✅ 정상(실제 침묵) | ⚠️ 오류 — 연속이어야 함 |

출력 예시:

```
[검증:결과물1 공백메움] ✓ caption 47개, 겹침/줄바꿈/경계이탈 없음
                         (자막 4.3s~312.6s, 발화 사이 침묵 11곳(정상))
[silence] 음성 구간 8개 (min_silence=0.6s, pad=100ms)
[검증:결과물2 무음제거] ✓ caption 49개, 겹침/줄바꿈/경계이탈 없음
                         (자막 0.0s~271.4s)
```

---

### FCPXML 안전성 확보

| 문제 | 해결 방법 |
|------|-----------|
| 동일 UID → FCP가 임포트 조용히 무시 | 실행할 때마다 새 UUID 자동 생성 |
| NAS/SMB 북마크 참조 오류 → FCP 멈춤·충돌 | `<media-rep>`의 모든 `<bookmark>` 자식 요소 자동 제거 |
| 번들 임포트가 환경에 따라 실패 | `.fcpxmld`(번들)와 `.fcpxml`(평면 파일) 동시 출력. 임포트에는 평면 파일 사용 |
| 카메라 타임코드 ≠ 파일 오프셋 → 잘못된 오디오 구간 | `file_pos = clip_start_tc − asset_start_tc` 공식을 Python `Fraction`으로 정확 계산 |

---

## 설치

### 요구 사항

| 항목 | 최소 버전 | 비고 |
|------|-----------|------|
| macOS | 14.0 (Sonoma) 이상 | Intel Mac 미지원 |
| 칩셋 | Apple Silicon (M1 이상) | MLX 가속 필요 |
| Python | 3.11 | 3.10·3.12도 동작하나 3.11 권장 |
| ffmpeg | 최신 | `brew install ffmpeg` |
| 여유 디스크 | 5 GB 이상 | AI 모델 약 2.3 GB + 작업 공간 |

> macOS 버전 확인: 애플 메뉴 → **이 Mac에 관하여**  
> 칩셋 확인: 애플 메뉴 → **이 Mac에 관하여** → 칩 항목에 "Apple M…" 표시 여부

---

### 사전 준비

#### 1. Homebrew 설치 (없는 경우)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/homebrew/install/HEAD/install.sh)"
```

설치 후 터미널을 재시작하거나 아래 명령으로 경로를 즉시 적용합니다 (Apple Silicon 기준):

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

설치 확인:

```bash
brew --version
```

#### 2. Python 3.11 설치 (없는 경우)

```bash
brew install python@3.11
```

설치 확인:

```bash
python3.11 --version   # Python 3.11.x 출력되면 OK
```

#### 3. ffmpeg 설치 (없는 경우)

```bash
brew install ffmpeg
```

설치 확인:

```bash
ffmpeg -version        # ffmpeg version … 출력되면 OK
```

---

### 설치 — 방법 A: 자동 스크립트 (권장)

가장 간단한 방법입니다. 터미널에 아래 명령을 순서대로 입력하세요.

```bash
# 1. 레포지토리 복제
git clone https://github.com/groundroot/FCP_autoedit.git
cd FCP_autoedit

# 2. 자동 설치 스크립트 실행
bash setup_mac.sh
```

스크립트가 자동으로 수행하는 작업:
- Apple Silicon / macOS 환경 확인
- ffmpeg 설치 여부 확인 (없으면 자동 설치)
- Python 가상환경(`.venv`) 생성
- 필요한 패키지 전체 설치 (`pip install -e .`)

완료 메시지 예시:

```
[SUCCESS] Apple Silicon (arm64) 감지
[SUCCESS] ffmpeg / ffprobe 사용 가능
[SUCCESS] .venv 생성 완료
[SUCCESS] 설치 완료
```

---

### 설치 — 방법 B: 수동 설치

단계별로 직접 제어하고 싶은 경우에 사용합니다.

```bash
# 1. 레포지토리 복제
git clone https://github.com/groundroot/FCP_autoedit.git
cd FCP_autoedit

# 2. ffmpeg 설치
brew install ffmpeg

# 3. Python 가상환경 생성 및 활성화
python3.11 -m venv .venv
source .venv/bin/activate

# 4. pip 최신화
pip install --upgrade pip

# 5. 패키지 설치
pip install -e .
```

---

### 설치 확인

아래 명령으로 정상 설치 여부를 확인합니다:

```bash
# 가상환경이 활성화된 상태에서
source .venv/bin/activate

silence-cutter --help
```

다음과 같이 출력되면 설치 성공입니다:

```
usage: silence-cutter [-h] {cut,resub,...} ...
```

---

### AI 모델 — 첫 실행 시 자동 다운로드

AI 모델은 첫 실행 시 자동으로 `~/.cache/huggingface/hub/`에 다운로드됩니다. 이후에는 **인터넷 연결 없이 완전 로컬 실행**됩니다.

| 모델 | 크기 | 용도 |
|------|------|------|
| `mlx-community/Qwen3-ASR-1.7B-8bit` | ~1.7 GB | 음성 → 텍스트 변환 |
| `mlx-community/Qwen3-ForcedAligner-0.6B-8bit` | ~600 MB | 단어 수준 타임스탬프 정렬 |
| Silero VAD v5 | ~2 MB | 음성 구간 감지 |

다운로드는 한 번만 진행됩니다. Wi-Fi 환경에서 약 5~15분 소요됩니다.

---

### 설치 문제 해결

#### `python3.11: command not found`

```bash
brew install python@3.11
# 설치 후 경로 확인
ls /opt/homebrew/bin/python3.11
```

#### `pip install` 중 빌드 오류

```bash
# Xcode Command Line Tools 설치
xcode-select --install
# 설치 후 재시도
pip install -e .
```

#### `mlx-audio` 설치 실패

```bash
# pip 최신화 후 재시도
pip install --upgrade pip setuptools wheel
pip install mlx-audio
```

#### `torch` 설치가 느린 경우

`torch`는 용량이 크므로(~600 MB) 시간이 걸릴 수 있습니다. 별도 설치 후 진행하면 진행 상황을 확인할 수 있습니다:

```bash
pip install torch
pip install -e .
```

#### 가상환경 재활성화

터미널을 새로 열 때마다 아래 명령으로 가상환경을 활성화해야 합니다:

```bash
cd FCP_autoedit
source .venv/bin/activate
```

#### ZIP으로 다운로드한 경우

```bash
# 압축 해제 후 폴더 이동
cd ~/Downloads/FCP_autoedit-main
bash setup_mac.sh
```

---

## 사용법

### 기본

```bash
silence-cutter resub "My Interview.fcpxmld"
```

결과물은 입력 파일 옆에 생성됩니다.

### 인터뷰

```bash
silence-cutter resub "김시은_인터뷰.fcpxmld" \
  --min-silence-sec 0.6
```

### 설교 · 강의

```bash
silence-cutter resub "설교_230910.fcpxmld" \
  --min-silence-sec 0.8
```

### 대본 기반 고유명사 교정

```bash
silence-cutter resub "interview.fcpxmld" \
  --script terms.md \
  --min-silence-sec 0.6
```

`terms.md`는 고유명사·전문 용어가 포함된 마크다운 파일입니다.  
유사도 85% 이상이고 길이가 같은 토큰만 보수적으로 교정합니다(내용 변경 없음, 표기 교정만).

---

## resub 전체 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--min-subtitle-chars` | `8` | 자막 한 줄 최소 글자 수 |
| `--max-subtitle-chars` | `27` | 자막 한 줄 최대 글자 수 |
| `--gap-bridge-sec` | `0.4` | 이 값 이하의 끊김만 이어 붙임(초). 그보다 긴 침묵은 공백 유지 |
| `--no-gap-fill` | — | 끊김 메움 비활성화. 순수 단어 타임스탬프 사용 |
| `--min-silence-sec` | `0.7` | 제거할 최소 무음 길이(초, 결과물 2) |
| `--silence-pad-ms` | `100` | 음성 구간 앞뒤 패딩(ms, 결과물 2) |
| `--no-remove-silence` | — | 결과물 2(무음제거) 생성 생략 |
| `--script` | — | 대본 `.md` 경로 (고유명사 보수 교정) |
| `--font-size` | `42` | 타이틀 오버레이 폰트 크기 |
| `--language` | `Korean` | ASR에 전달할 음성 언어 |
| `--asr-model` | `Qwen3-ASR-1.7B-8bit` | ASR 모델 ID |
| `--aligner-model` | `Qwen3-ForcedAligner-0.6B-8bit` | 강제 정렬 모델 ID |

### 콘텐츠 유형별 권장 `--min-silence-sec`

| 콘텐츠 | 권장값 | 비고 |
|--------|--------|------|
| 인터뷰 | `0.6` | 자연스러운 호흡은 유지, 긴 망설임만 제거 |
| 강의 | `0.4` | 빠른 템포 |
| 설교 | `0.8` | 의도적 침묵을 전달의 일부로 보존 |
| 일반 | `0.7` | 기본값 |

---

## 동작 원리 — 파이프라인

```
1. FCPXML 파싱
   ├─ spine에서 asset-clip 목록 추출
   ├─ 에셋 → 파일 시작 타임코드 맵 구성
   │    file_offset = clip_start_tc − asset_start_tc
   └─ <media-rep>의 stale <bookmark> 전부 제거

2. 오디오 추출
   └─ ffmpeg → 16 kHz 모노 WAV

3. 클립별 처리(VAD 구간 단위 병렬):
   ├─ Silero VAD → 클립 파일 범위 내 음성 구간 감지
   ├─ 15초 초과 구간 분할(정렬기 안정성)
   ├─ Qwen3-ASR-1.7B → 텍스트 + 단어 목록
   ├─ Qwen3-ForcedAligner-0.6B → 절대 단어 타임스탬프
   └─ _split_subtitle_longform(min=8, max=27) → 자막 카드

4. 결과물 1 구성 — 공백메움
   ├─ _bridge_short_gaps(≤ 0.4초) → 미세 끊김 이어 붙이기
   ├─ title(lane 1, Position "0 -440") + caption(lane 2) 삽입
   └─ 새 UID + 프로젝트명 접미사 "_롱폼자막"

5. 결과물 2 구성 — 무음제거
   ├─ Silero VAD(min_silence_sec) → 음성 전용 구간 감지
   ├─ spine 재구성: 압축 클립 순서대로 cursor 누적
   ├─ 교집합 기반 자막 분배:
   │    각 음성 클립 [a, b]에 대해:
   │      [a, b]와 겹치는 모든 자막 chunk 수집
   │      [a, b]로 클램핑, 첫 조각은 a부터·마지막은 b까지(빈틈 없음)
   └─ 새 UID + 프로젝트명 접미사 "_무음제거"

6. 두 결과물 자동 검증 → ✓ / ⚠️ 로그 출력
```

---

## FCPXML 요소 구조

자막 한 장마다 **두 개의 형제 요소**가 부모 `asset-clip` 안에 삽입됩니다:

```xml
<!-- Lane 1: 화면 표시용 타이틀 오버레이 — param으로 하단 배치 -->
<title ref="r2" lane="1" offset="34119/1001s" duration="320/1001s"
       name="감사합니다" start="3600s">
  <param name="Position"
         key="9999/999166631/999166633/1/100/101"
         value="0 -440"/>        <!-- 1080p 기준 iTT 캡션과 동일 위치 -->
  <text>
    <text-style ref="rts1">감사합니다</text-style>
  </text>
  <text-style-def id="rts1">
    <text-style font="Helvetica" fontSize="42" fontColor="1 1 1 1"
                bold="1" shadowColor="0 0 0 0.75" shadowOffset="3 315"
                alignment="center"/>
  </text-style-def>
</title>

<!-- Lane 2: iTT 캡션 (캡션 편집기·SRT/ITT 내보내기에 사용) -->
<caption lane="2" offset="34119/1001s" duration="320/1001s"
         role="iTT?captionFormat=ITT.ko" start="3600s">
  <text placement="bottom">
    <text-style ref="rcts1">감사합니다</text-style>
  </text>
  <text-style-def id="rcts1">
    <text-style font=".AppleSystemUIFont" fontSize="13" fontFace="Regular"
                fontColor="1 1 1 1" backgroundColor="0 0 0 1"/>
  </text-style-def>
</caption>
```

**주의 사항:**
- FCPXML 1.14 DTD 규정상 `<param>`은 `<text>` **앞**에 위치해야 합니다
- `start="3600s"`는 FCP 타이틀 효과의 내부 앵커값입니다(변경 불가)
- `offset` = 자막 시작 시점의 카메라 타임코드 (파일 위치 + 에셋 시작 TC)
- `duration` = `Fraction` 연산으로 프레임 단위 스냅된 자막 길이

---

## 파이널 컷 프로에 임포트하기

### 절차

1. 출력 폴더에서 **평면 `.fcpxml` 파일**을 찾습니다
2. FCP에서 **파일 → 가져오기 → XML…**
3. `_롱폼자막_공백메움.fcpxml` 파일 선택
4. 라이브러리 선택 → **확인**

> **`.fcpxmld` 번들이 아닌 `.fcpxml` 평면 파일을 사용하세요.**  
> 번들은 파일시스템·Finder 설정에 따라 패키지로 인식되지 않아 임포트에 실패할 수 있습니다.

### 임포트 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| 임포트 대화상자에 아무것도 없음 | `.fcpxmld` 번들을 선택함 | `.fcpxml` 평면 파일 사용 |
| 파일은 임포트됐지만 프로젝트가 안 보임 | 라이브러리에 동일 UID 프로젝트 이미 존재 | 가장 최신 출력 파일 사용(매 실행마다 새 UID 생성) |
| 임포트 시 FCP 멈춤·충돌 | 소스 FCPXML에 NAS stale `<bookmark>` 존재 | FCP_autoedit가 자동 제거함 |
| 자막이 잘못된 프레임에 표시 | 소스 FCPXML의 `src` 경로 한글 NFD 인코딩 오류 | `<media-rep>`의 `src` 속성 바이트 직접 교정 필요 |

### DTD 유효성 검사

```bash
DTD="/Applications/Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_14.dtd"
cp "$DTD" /tmp/FCPXMLv1_14.dtd
python3 -c "
src = open('output_롱폼자막_공백메움.fcpxml').read()
out = src.replace('<!DOCTYPE fcpxml>',
      '<!DOCTYPE fcpxml SYSTEM \"/tmp/FCPXMLv1_14.dtd\">')
open('/tmp/v.fcpxml', 'w').write(out)
"
xmllint --noout --valid /tmp/v.fcpxml && echo "✓ DTD 통과"
```

---

## 프로젝트 구조

```
silence_cutter/
├── retranscribe.py      ← 롱폼 파이프라인 핵심 (resub 명령)
│   ├── _split_subtitle_longform()   등급제 자막 분할
│   ├── _bridge_short_gaps()         미세 끊김 이어 붙이기
│   ├── _add_subtitle_elements()     title + caption 요소 작성
│   ├── _build_silence_removed()     결과물 2 (무음제거) 구성
│   └── _verify_fcpxml()             생성 후 검증
├── transcribe.py        ASR + ForcedAligner + 조사 경계 병합
├── vad.py               Silero VAD, 구간 분할
├── fcpxml.py            FCPXML 헬퍼, 프레임 스냅, cut 명령 분할
├── __main__.py          CLI 진입점 (argparse)
└── itt.py               iTT 자막 내보내기
```

---

## 라이선스

[Apache License 2.0](LICENSE)

원본 프로젝트: [Silenci / Silence-Cutter](https://github.com/leeyc09/Silence-Cutter) by leeyc09  
롱폼 자막 워크플로우, 등급제 분할, 무음제거 출력, FCPXML 안전성 수정: [groundroot](https://github.com/groundroot)
