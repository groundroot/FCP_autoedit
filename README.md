<div align="center">

# FCP_autoedit

**AI-powered longform subtitle generator for Final Cut Pro**

Drop an exported FCPXML → AI transcribes & aligns speech → Get two ready-to-import subtitle files

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-Optimized-FF6B35?style=flat-square&logo=apple&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat-square&logo=python&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)](LICENSE)

[한국어 문서 →](README.ko.md)

</div>

---

## What is FCP_autoedit?

FCP_autoedit is a command-line tool that takes a Final Cut Pro project (`.fcpxmld`) exported **without subtitles** and automatically generates **two subtitle-embedded FCPXML files** ready to import back into FCP.

It is purpose-built for **longform content** — interviews, sermons, lectures — where subtitles must be readable, meaning-unit aware, and precisely timed to actual speech.

```
Input:  interview_edit.fcpxmld        ← Your FCP project, no subtitles

Output: interview_edit_롱폼자막_공백메움.fcpxmld          ← Original edit + subtitles
        interview_edit_롱폼자막_공백메움_무음제거.fcpxmld  ← Silence-removed + subtitles
```

---

## Key Features

### Two outputs from one run

| Output | Description |
|--------|-------------|
| **Gap-filled** (`공백메움`) | Original cut structure preserved. Subtitles follow actual speech timing. Pauses between sentences are intentional — not forced to fill. |
| **Silence-removed** (`무음제거`) | Silence beyond the threshold is cut. Timeline is compressed. Subtitles redistributed via intersection mapping, covering every frame with no gaps. |

---

### Grade-based subtitle splitting

Subtitles split at **meaning-unit boundaries**, not by character count alone.  
Three grades of break points are evaluated in priority order:

| Grade | Triggers | Behavior |
|-------|----------|----------|
| **Grade 3** — sentence endings | `습니다` `합니다` `에요` `네요` `는데요` `거든요` `.` `!` `?` | **Immediate split** as soon as `min_chars` (default 8) is reached |
| **Grade 2** — connective endings | `고` `서` `해서` `는데` `지만` `면서` `,` | Used on overflow; viewer naturally reads "…continued" |
| **Grade 1** — particles | `을` `를` `은` `는` `에서` `로` `까지` | Last resort only; particle-only words (`은`, `는`, …) never split |

**Overflow handling:** When a subtitle exceeds `max_chars` (default 27), the algorithm looks back through all recorded break points, selects the **highest-grade boundary whose head fits within `max_chars`**, emits that head as a card, then **rolls `i` back to the first tail word** — allowing the tail to be processed through the normal loop (including Grade 3 immediate splits on tail-side sentence endings).

**Key bug this solves:**
> Speech: `"…나아가야겠다는 생각을 하였습니다 감사합니다"`
>
> ❌ Before: `하였습니다` only recorded `last_break`. Since `감사합니다` was `is_last`, both words merged → `"하였습니다 감사합니다"` displayed during `감사합니다` audio.
>
> ✅ After: `하였습니다` triggers Grade 3 immediate split → `"생각을 하였습니다"` + `"감사합니다"` each become their own card.

---

### Speech-timed subtitles — no redistribution

Subtitle start/end times are taken **directly from Qwen3-ForcedAligner word timestamps**.  
Character-count-based time redistribution is never used.

- Pauses ≤ `--gap-bridge-sec` (default 0.4 s) are bridged for readability
- Genuine silences remain as gaps — subtitle timing matches breath

---

### Automatic post-generation verification

Both files are verified immediately after generation:

| Check | Output 1 | Output 2 |
|-------|----------|----------|
| Caption count > 0 | ✓ required | ✓ required |
| No overlapping captions | ✓ | ✓ |
| No multi-line captions | ✓ | ✓ |
| No empty caption text | ✓ | ✓ |
| No clip-boundary violations | ✓ | ✓ |
| Gaps between captions | ✅ Normal (real silence) | ⚠️ Error — must be contiguous |

Sample log:

```
[검증:결과물1 공백메움] ✓ caption 47개, 겹침/줄바꿈/경계이탈 없음
                         (자막 4.3s~312.6s, 발화 사이 침묵 11곳(정상))
[silence] 음성 구간 8개 (min_silence=0.6s, pad=100ms)
[검증:결과물2 무음제거] ✓ caption 49개, 겹침/줄바꿈/경계이탈 없음
                         (자막 0.0s~271.4s)
```

---

### FCPXML-safe output

| Concern | Solution |
|---------|----------|
| Same project UID → FCP silently skips import | Fresh UUID generated on every run |
| Stale NAS/SMB bookmark → FCP hang or crash | All `<bookmark>` children of `<media-rep>` stripped automatically |
| Bundle import unreliable in some FCP versions | Both `.fcpxmld` (bundle) **and** `.fcpxml` (flat) are written; use flat for import |
| Camera timecode ≠ file offset → wrong audio seek | `file_pos = clip_start_tc − asset_start_tc` computed with Python `Fraction` |

---

## Installation

### Requirements

- macOS 14.0+ · Apple Silicon (M1 or later)
- Python 3.11
- ffmpeg (`brew install ffmpeg`)

### Setup

```bash
git clone https://github.com/groundroot/FCP_autoedit.git
cd FCP_autoedit

brew install ffmpeg
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e .
```

AI models download automatically on first run into `~/.cache/huggingface/hub/` (~2.3 GB total). No API key or internet connection required after download.

| Model | Size | Purpose |
|-------|------|---------|
| `mlx-community/Qwen3-ASR-1.7B-8bit` | ~1.7 GB | Speech-to-text |
| `mlx-community/Qwen3-ForcedAligner-0.6B-8bit` | ~600 MB | Word-level alignment |
| Silero VAD v5 | ~2 MB | Voice activity detection |

---

## Usage

### Basic

```bash
silence-cutter resub "My Interview.fcpxmld"
```

Outputs are written next to the input file.

### Interview

```bash
silence-cutter resub "김시은_인터뷰.fcpxmld" \
  --min-silence-sec 0.6
```

### Sermon / Lecture

```bash
silence-cutter resub "설교_230910.fcpxmld" \
  --min-silence-sec 0.8
```

### With proper-noun script correction

```bash
silence-cutter resub "interview.fcpxmld" \
  --script terms.md \
  --min-silence-sec 0.6
```

`terms.md` is any Markdown file containing proper nouns and domain vocabulary. Tokens with ≥ 85% similarity and equal length are corrected conservatively (no content substitution, only spelling/notation fixes).

---

## All `resub` Options

| Option | Default | Description |
|--------|---------|-------------|
| `--min-subtitle-chars` | `8` | Minimum characters per subtitle line |
| `--max-subtitle-chars` | `27` | Maximum characters per subtitle line |
| `--gap-bridge-sec` | `0.4` | Bridge pauses ≤ this value (s); longer silences stay as gaps |
| `--no-gap-fill` | — | Disable gap bridging; use pure word timestamps |
| `--min-silence-sec` | `0.7` | Minimum silence duration to remove (Output 2) |
| `--silence-pad-ms` | `100` | Padding around speech segments (Output 2) |
| `--no-remove-silence` | — | Skip Output 2 entirely |
| `--script` | — | Path to `.md` for conservative proper-noun correction |
| `--font-size` | `42` | Title overlay font size |
| `--language` | `Korean` | Speech language passed to ASR |
| `--asr-model` | `Qwen3-ASR-1.7B-8bit` | ASR model ID |
| `--aligner-model` | `Qwen3-ForcedAligner-0.6B-8bit` | Forced aligner model ID |

### `--min-silence-sec` by content type

| Content | Recommended | Notes |
|---------|-------------|-------|
| Interview | `0.6` | Natural pauses kept; hesitations removed |
| Lecture | `0.4` | Tighter pacing |
| Sermon | `0.8` | Deliberate pauses are part of the delivery |
| General | `0.7` | Default |

---

## How It Works — Pipeline

```
1. Parse FCPXML
   ├─ Extract asset-clip list from spine
   ├─ Build asset → file-start-timecode map
   │    file_offset = clip_start_tc − asset_start_tc
   └─ Strip stale <bookmark> from all <media-rep>

2. Extract audio
   └─ ffmpeg → 16 kHz mono WAV

3. For each clip (parallel across VAD segments):
   ├─ Silero VAD → speech segments in clip's file range
   ├─ Split any segment > 15 s (aligner stability)
   ├─ Qwen3-ASR-1.7B → transcript text + word list
   ├─ Qwen3-ForcedAligner-0.6B → absolute word timestamps
   └─ _split_subtitle_longform(min=8, max=27) → subtitle cards

4. Build Output 1 — Gap-filled
   ├─ _bridge_short_gaps(≤ 0.4 s) → stitch micro-pauses
   ├─ title (lane 1, Position "0 -440") + caption (lane 2)
   └─ New UID + project name suffix "_롱폼자막"

5. Build Output 2 — Silence-removed
   ├─ Silero VAD (min_silence_sec) → voice-only segments
   ├─ Rebuild spine with compressed clips, cursor accumulation
   ├─ Intersection subtitle mapping:
   │    for each voice clip [a, b]:
   │      chunks overlapping [a, b] → clipped to [a, b]
   │      first piece starts at a, last ends at b (edge-to-edge)
   └─ New UID + project name suffix "_무음제거"

6. Auto-verify both outputs → log ✓ / ⚠️
```

---

## FCPXML Element Structure

Each subtitle card inserts **two sibling elements** into the parent `asset-clip`:

```xml
<!-- Lane 1: visible title overlay — positioned at bottom via param -->
<title ref="r2" lane="1" offset="34119/1001s" duration="320/1001s"
       name="감사합니다" start="3600s">
  <param name="Position"
         key="9999/999166631/999166633/1/100/101"
         value="0 -440"/>        <!-- matches iTT caption position in 1080p -->
  <text>
    <text-style ref="rts1">감사합니다</text-style>
  </text>
  <text-style-def id="rts1">
    <text-style font="Helvetica" fontSize="42" fontColor="1 1 1 1"
                bold="1" shadowColor="0 0 0 0.75" shadowOffset="3 315"
                alignment="center"/>
  </text-style-def>
</title>

<!-- Lane 2: iTT caption (Caption editor, export to .srt / .itt) -->
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

**Notes:**
- `<param>` must appear **before** `<text>` — required by FCPXML 1.14 DTD
- `start="3600s"` is FCP's internal anchor for title effects (do not change)
- `offset` = camera timecode of the subtitle's start (= file position + asset start TC)
- `duration` = frame-snapped subtitle duration using `Fraction` arithmetic

---

## Importing to Final Cut Pro

### Steps

1. Locate the flat `.fcpxml` file (same directory as your input `.fcpxmld`)
2. In FCP: **File → Import → XML…**
3. Select the `_롱폼자막_공백메움.fcpxml` file
4. Choose your library → click **OK**

> **Use the flat `.fcpxml`, not the `.fcpxmld` bundle.**
> The bundle requires the filesystem to treat it as a directory package; the flat file works in all environments.

### Troubleshooting import

| Symptom | Cause | Fix |
|---------|-------|-----|
| Import dialog opens but nothing appears | Bundle (`.fcpxmld`) opened instead of flat file | Use the `.fcpxml` flat file |
| File imports but no project appears | Library has existing project with same UID | Always use the latest run output — fresh UIDs every time |
| FCP freezes / crashes on import | Stale NAS `<bookmark>` in source FCPXML | FCP_autoedit strips these automatically |
| Subtitles appear at wrong frame | Source FCPXML has URL-encoded Korean path corruption | Check `src` attribute in `<media-rep>` for NFD encoding issues |

### DTD validation

```bash
DTD="/Applications/Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_14.dtd"
cp "$DTD" /tmp/FCPXMLv1_14.dtd
python3 -c "
src = open('output_롱폼자막_공백메움.fcpxml').read()
out = src.replace('<!DOCTYPE fcpxml>',
      '<!DOCTYPE fcpxml SYSTEM \"/tmp/FCPXMLv1_14.dtd\">')
open('/tmp/v.fcpxml', 'w').write(out)
"
xmllint --noout --valid /tmp/v.fcpxml && echo "✓ DTD valid"
```

---

## Project Structure

```
silence_cutter/
├── retranscribe.py      ← Core longform pipeline (resub)
│   ├── _split_subtitle_longform()   Grade-based subtitle splitting
│   ├── _bridge_short_gaps()         Micro-pause bridging
│   ├── _add_subtitle_elements()     title + caption element writer
│   ├── _build_silence_removed()     Output 2 (silence-removed) builder
│   └── _verify_fcpxml()             Post-generation verifier
├── transcribe.py        ASR + ForcedAligner + josa boundary merging
├── vad.py               Silero VAD, segment splitting
├── fcpxml.py            FCPXML helpers, frame snapping, cut-cmd subtitle split
├── __main__.py          CLI entry point (argparse)
└── itt.py               iTT subtitle export
```

---

## License

[Apache License 2.0](LICENSE)

Based on [Silenci / Silence-Cutter](https://github.com/leeyc09/Silence-Cutter) by leeyc09.  
Longform subtitle workflow, grade-based splitting, silence-removed output, and FCPXML safety fixes by [groundroot](https://github.com/groundroot).
