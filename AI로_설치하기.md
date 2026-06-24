# AI 도우미로 쉽게 설치하기

> Claude Code나 Gemini CLI 같은 AI 도우미에게 설치를 부탁하면<br>
> 터미널 명령어를 몰라도 5분 안에 끝납니다.

---

## 1단계 — 레포 복사하기 (Clone)

### 방법 A: 터미널 명령어로 복사

터미널(Terminal.app)을 열고 아래를 그대로 붙여넣으세요.

```bash
git clone https://github.com/groundroot/FCP_autoedit.git
cd FCP_autoedit
```

### 방법 B: ZIP으로 받기

1. [https://github.com/groundroot/FCP_autoedit](https://github.com/groundroot/FCP_autoedit) 접속
2. 초록색 **`< > Code`** 버튼 클릭
3. **`Download ZIP`** 선택
4. 다운로드된 ZIP 파일을 더블클릭해 압축 해제
5. 터미널에서 해당 폴더로 이동

```bash
cd ~/Downloads/FCP_autoedit-main
```

---

## 2단계 — AI 도우미에게 설치 부탁하기

### Claude Code 로 설치하기

**Claude Code**는 터미널에서 실행하는 Anthropic의 AI 코딩 도우미입니다.

#### Claude Code 설치 (처음 한 번만)

```bash
npm install -g @anthropic-ai/claude-code
```

#### 프로젝트 폴더에서 실행

```bash
cd FCP_autoedit          # 또는 FCP_autoedit-main
claude
```

#### Claude에게 이렇게 말하면 됩니다

```
이 프로젝트를 내 맥에 설치해줘.
Python 가상환경 만들고 필요한 패키지 다 설치해줘.
```

또는 더 간단하게:

```
setup_mac.sh 실행해서 설치해줘
```

Claude가 알아서 환경을 확인하고, ffmpeg 설치 여부를 체크하고, Python 가상환경을 만들어 패키지까지 설치해줍니다.

---

### Gemini CLI 로 설치하기

**Gemini CLI**는 Google의 AI 도우미를 터미널에서 사용하는 도구입니다.

#### Gemini CLI 설치 (처음 한 번만)

```bash
npm install -g @google/gemini-cli
```

#### 프로젝트 폴더에서 실행

```bash
cd FCP_autoedit          # 또는 FCP_autoedit-main
gemini
```

#### Gemini에게 이렇게 말하면 됩니다

```
이 프로젝트를 내 맥에 설치해줘.
setup_mac.sh 파일을 실행하거나 README를 보고 설치 방법을 안내해줘.
```

---

## 3단계 — 설치가 끝나면 이렇게 쓰면 됩니다

```bash
# 가상환경 활성화
source .venv/bin/activate

# FCP에서 내보낸 FCPXML에 자막 자동 생성
silence-cutter resub "내_영상.fcpxmld"
```

처음 실행할 때 AI 모델(약 2.3 GB)이 자동 다운로드됩니다. 잠깐 기다리면 됩니다.

---

## AI에게 물어볼 수 있는 예시 질문

설치 후에도 막히는 부분이 있으면 AI에게 바로 물어보세요:

| 상황 | AI에게 할 말 |
|------|-------------|
| 설치가 안 됨 | "설치 중 에러가 났어. 로그 보고 고쳐줘" |
| 사용법 모름 | "인터뷰 영상 자막 만들려면 어떻게 하면 돼?" |
| 오류 발생 | "실행하면 이런 에러가 나. 어떻게 하면 돼?" |
| 결과물 임포트 | "FCP에 어떻게 불러오면 돼?" |

---

## 잘 안 될 때 체크리스트

- [ ] macOS 14 이상인지 확인 (`애플 메뉴 → 이 Mac에 관하여`)
- [ ] Apple Silicon(M1/M2/M3/M4) Mac인지 확인
- [ ] Homebrew가 설치돼 있는지 확인 → 없으면 [brew.sh](https://brew.sh) 참고
- [ ] Python 3.11이 있는지 확인 → `python3.11 --version` 터미널에서 실행
- [ ] ffmpeg가 있는지 확인 → `ffmpeg -version` 터미널에서 실행

모두 확인했는데도 안 되면 `setup_mac.sh` 파일을 실행하면 자동으로 해결됩니다:

```bash
bash setup_mac.sh
```

---

## 도움이 필요하면

- 이슈: [GitHub Issues](https://github.com/groundroot/FCP_autoedit/issues)
- 자세한 사용법: [README.ko.md](README.ko.md)
