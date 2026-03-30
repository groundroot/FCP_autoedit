# Silenci — Promotion Playbook

## 🎯 Key Message (30 seconds)

> **Silenci** removes silence from videos and generates word-level subtitles — all locally on your Mac, for free.
> Drop a video → AI cuts silence → Export to Final Cut Pro with perfectly synced subtitles.
> No cloud. No subscription. No mid-word cuts.

---

## 📋 Platform Posts

### 1. Reddit — r/finalcutpro

**Title:** I built a free macOS app that removes silence from videos and auto-generates subtitles for Final Cut Pro

**Body:**

Hey everyone! I've been working on **Silenci**, a free, open-source macOS app for video editors.

**What it does:**
- 🔇 Automatically detects and removes silence from your footage
- 🗣️ Generates word-level synced subtitles using AI (Qwen3-ASR)
- 📤 Exports FCPXML that you can import directly into Final Cut Pro

**What makes it different:**
- **Never cuts words in half** — uses a 2-pass ASR approach (transcribe first, then split at word boundaries)
- **100% local** — runs entirely on your Mac using Apple Silicon (MLX). No cloud upload, no API keys
- **Free and open source** — no subscription, no watermarks

**How it works:**
1. Drop a video file
2. AI analyzes speech (Silero VAD + Qwen3-ASR)
3. Edit words/clips in the built-in editor
4. Export FCPXML → import into FCP with subtitles

Built with SwiftUI + Python, supports English/Korean/Japanese/Chinese.

GitHub: https://github.com/leeyc09/Silence-Cutter

Would love your feedback! 🙏

---

### 2. Reddit — r/MacApps

**Title:** Silenci — Free AI silence remover & subtitle generator for macOS (Apple Silicon optimized)

**Body:**

Just released **Silenci**, a native macOS app that:

- Removes silence from video/audio files automatically
- Generates AI-powered subtitles with word-level timestamps
- Exports to FCPXML (Final Cut Pro), SRT, iTT

**Key features:**
- Native SwiftUI app (~2MB)
- Runs 100% locally on Apple Silicon via MLX — no cloud needed
- 4 language support: English, Korean, Japanese, Chinese
- Python venv auto-installs on first launch (~45 seconds)

Free & open source: https://github.com/leeyc09/Silence-Cutter

---

### 3. Hacker News — Show HN

**Title:** Show HN: Silenci – AI video silence removal with word-level subtitles, local on macOS

**Body:**

I built Silenci, a macOS app that removes silence from videos and generates subtitles with word-level timestamps. Everything runs locally on Apple Silicon.

The key insight: most silence-removal tools split audio by time, which cuts words in half. Silenci uses a 2-pass approach — first transcribe with Qwen3-ASR + ForcedAligner to get word boundaries, then split only at those boundaries.

Stack: SwiftUI frontend ↔ Python subprocess via JSON-RPC 2.0 over stdin/stdout. ASR uses MLX 8-bit quantized models for fast local inference.

- GitHub: https://github.com/leeyc09/Silence-Cutter
- No cloud, no subscription, Apache 2.0 license

---

### 4. X/Twitter

**Post 1 (launch):**

🎬 Introducing **Silenci** — AI silence removal + subtitle generator for Final Cut Pro

✂️ Auto-detect & remove silence
🗣️ Word-level synced subtitles (never cuts mid-word)
🍎 100% local on Apple Silicon
💰 Free & open source

GitHub → https://github.com/leeyc09/Silence-Cutter

#FinalCutPro #macOS #VideoEditing #AI #OpenSource

**Post 2 (technical):**

Most silence-removal tools split by time → words get chopped in half.

Silenci uses 2-pass ASR:
1️⃣ Transcribe → get word timestamps
2️⃣ Split at word boundaries only

Result: Clean cuts, perfect subtitle sync.

Try it free → https://github.com/leeyc09/Silence-Cutter

---

### 5. 한국 커뮤니티

#### 클리앙 팁&트릭

**제목:** [무료/오픈소스] Silenci — 영상 무음 자동 제거 + AI 자막 생성 macOS 앱

**본문:**

파이널컷 사용자분들께 유용할 것 같아 공유합니다.

**Silenci**는 영상에서 무음 구간을 자동으로 감지·제거하고, AI로 자막까지 생성해주는 무료 macOS 앱입니다.

주요 특징:
- 무음 구간 자동 감지 → 제거 → FCPXML로 내보내기
- AI 음성 인식 (Qwen3-ASR) → 단어 단위 정밀 자막
- 100% 로컬 실행 (Apple Silicon MLX) — 클라우드 업로드 없음
- 한국어/영어/일본어/중국어 지원
- 완전 무료, 오픈소스

다른 도구와의 차이점은 **단어 중간에서 절대 잘리지 않는다**는 것입니다.
2-Pass ASR 방식으로 먼저 단어 타임스탬프를 확보한 후, 단어 경계에서만 분할합니다.

GitHub: https://github.com/leeyc09/Silence-Cutter

---

#### 디스콰이엇

**제목:** Silenci — AI 무음 제거 + 자막 생성 (macOS, 무료 오픈소스)

**한줄 설명:** 영상 편집자를 위한 AI 무음 자동 제거 & 단어 단위 자막 생성 macOS 앱

---

### 6. Product Hunt

**Tagline:** AI-powered silence removal & subtitle generator for Final Cut Pro

**Description:**
Silenci automatically removes silence from your videos and generates word-level synced subtitles. Everything runs locally on your Mac — no cloud, no subscription.

**Key Features:**
- 🔇 Smart silence detection (Silero VAD)
- 🗣️ AI speech recognition with word timestamps (Qwen3-ASR)
- ✂️ Never cuts words in half (2-pass ASR)
- 📤 FCPXML, SRT, iTT export
- 🍎 Apple Silicon optimized (MLX 8-bit)
- 🌐 4 languages: EN, KO, JA, ZH

**Makers:** @leeyc09

---

## 📅 Launch Timeline

### Day 1 (Mon-Tue)
- [ ] Post to r/finalcutpro
- [ ] Post to r/MacApps  
- [ ] Tweet launch post with screenshots

### Day 2 (Tue-Wed)
- [ ] Submit to Hacker News (Show HN)
- [ ] Post to r/VideoEditing
- [ ] Post to r/SideProject

### Day 3 (Wed-Thu)
- [ ] 클리앙 팁&트릭 게시
- [ ] 디스콰이엇 프로덕트 등록
- [ ] 맥쓰사 게시

### Week 2
- [ ] Product Hunt 런칭
- [ ] awesome-macos PR 제출
- [ ] awesome-video PR 제출

---

## 💡 Tips
- Post screenshots with every share (app-main.jpg is the best hero image)
- Respond to every comment within 24 hours
- Be honest about limitations (macOS only, Apple Silicon only, first install takes 45s)
- Star History chart in README creates FOMO
- GitHub Trending tracks daily stars — concentrate posts in 24-48hr window
