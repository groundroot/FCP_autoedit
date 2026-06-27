# JaMak Feature and Validation Matrix

Last updated: 2026-06-27

## Launch Market Language Coverage

Public country-level sales data for the App Store Photo & Video / video editing category is not fully public. For the first Mac App Store localization scope, JaMak uses non-gaming app spend as the best public proxy for paid or subscription video editing apps, then adds extra video-editing-relevant markets.

Market evidence used:

- RevenueCat / data.ai list the top 20 countries by non-gaming app spend. The top 10 are the United States, China, Japan, United Kingdom, Germany, Canada, Australia, South Korea, France, and Brazil.
- Apple's App Store ecosystem report describes digital goods and services as including games, photo and video editing apps, and enterprise tools, which makes non-gaming app spend a closer proxy than total game-heavy app spend for JaMak.
- RevenueCat also notes Photo & Video as a top category in several high-growth markets, including South Korea, Brazil, and the United States.

Covered launch markets:

| Market | UI locale | Speech language |
| --- | --- | --- |
| United States | en | English |
| United Kingdom | en | English |
| Australia / New Zealand | en | English |
| Canada | en / fr | English / French |
| Mainland China | zh-Hans | Chinese |
| Taiwan / Hong Kong | zh-Hant | Chinese |
| Japan | ja | Japanese |
| South Korea | ko | Korean |
| Germany | de | German |
| France | fr | French |
| Spain | es | Spanish |
| Italy | it | Italian |
| Brazil | pt-BR | Portuguese |

App UI localizations now shipped:

- en
- ko
- ja
- zh-Hans
- zh-Hant
- de
- fr
- es
- it
- pt-BR

Speech recognition language choices now exposed:

- Korean
- English
- Japanese
- Chinese
- German
- French
- Spanish
- Italian
- Portuguese

## Feature List

### Media Import

- Import user-selected video files.
- Drag and drop video files into the preview area.
- Recognized document types include MP4, MOV, M4V, MKV.
- Import edited FCPXML / FCPXMLD for retranscription.
- File access is based on user-selected files and save locations.

### Local Runtime and Models

- Local Python bridge for audio analysis and export support.
- App Store build expects a bundled JaMak runtime instead of installing packages at runtime.
- Hugging Face model cache is redirected into JaMak app data.
- AI model manager for explicit model download.
- AI model availability refresh.
- AI model download retry state.
- Download progress display.
- Selectable ASR models:
  - Qwen3-ASR 0.6B
  - Whisper Small via faster-whisper
  - Qwen3-ASR 1.7B
- Whisper refuses analysis until the user explicitly downloads the model.
- Direct/development builds can rebuild the local Python environment.
- App menu exposes Python environment removal for development/direct builds.

### Audio and Speech Analysis

- Extract audio from the selected video.
- Detect speech regions with VAD.
- Configure VAD sensitivity.
- Configure minimum speech duration.
- Configure minimum silence duration.
- Configure speech padding before and after detected speech.
- Split long speech segments.
- Generate transcript text.
- Generate word-level timestamps.
- Korean orphan josa merge post-processing.
- Speaker count setting for subtitle/retranscription workflows.
- Analysis progress display.
- Analysis cancellation.
- Failure state display and retry entry points where applicable.

### Settings

- App language override.
- Speech language selection.
- ASR model selection.
- VAD sensitivity.
- Minimum silence duration.
- Minimum speech duration.
- Speech padding.
- Maximum segment length.
- Subtitle density.
- Subtitle line count.
- Speaker count.
- FCPXML subtitle font size.
- Reset to defaults.

### Text-Based Editing

- Transcript-based video editing surface.
- Word-level keep/remove state.
- Text deletion removes the corresponding timeline range non-destructively.
- Auto-scroll option for transcript playback.
- Timeline bar showing speech and silence regions.
- Current playback position overlay.
- Clip cards with kept/deleted state.
- Restore deleted clips.
- Split clips.
- Merge adjacent clips.
- Edit subtitle text.
- Find and replace transcript text.

### Video Preview

- AVFoundation video preview.
- Placeholder state when no video is loaded.
- Preview subtitle overlay.
- FCPXML drop target.
- Timeline duration support for retranscribed/edited timelines.

### Subtitle and Caption Controls

- Subtitle density setting.
- One-line or two-line subtitle mode.
- Maximum subtitle characters per line.
- FCPXML subtitle font size setting.
- Speaker count selection from Auto to 4 speakers.

### Export

Mac App Store surface:

- FCPXML export.
- SRT export.
- Free-version export clamping behavior is covered by tests, but PRO purchase UI is hidden in the App Store approval build.
- User-selected save location.
- Original video is not modified.

Development / non-App Store surface in code:

- MP4 render export.
- iTT export.
- EDL export.
- Premiere XML export.

Retranscription workflow:

- Read edited FCPXML.
- Re-run ASR on edited clip boundaries.
- Export retranscribed FCPXML.
- Optional iTT generation in retranscription sheet.
- Retranscription progress display.
- Retranscription cancellation.
- Retranscription retry after errors.
- Show output in Finder.

### Store and Product Gating

- StoreKit 2 service exists for a single PRO non-consumable.
- Free export limit tests exist.
- App Store approval build currently hides PRO purchase UI.

### App Store Approval Structure

- App Sandbox entitlement enabled.
- User-selected read/write file entitlement enabled.
- Network client entitlement retained for explicit model downloads.
- App Store build hides MP4 export.
- App Store build disables external runtime installation.
- Local App Store inspection target builds, bundles, ad-hoc signs, and verifies the app.

## Validation Started

Commands run:

```bash
find SilenciApp/Sources/Resources -maxdepth 2 -name 'Localizable.strings' -print -exec plutil -lint {} \;
plutil -lint SilenciApp/Info.plist
swift build
swift run SilenciTestDriver
.venv/bin/python -m py_compile silence_cutter/transcribe.py silence_cutter/pipeline.py silence_cutter/__main__.py silence_cutter/server.py
make inspect-appstore
```

Current automated results:

- Localizable.strings syntax: passed for 10 locales.
- Info.plist syntax: passed.
- Swift debug build: passed.
- Swift test driver: passed, 50 tests in 5 suites.
- Python syntax compile: passed.
- MAS release build / bundle / ad-hoc signing / codesign verify: passed.

New automated checks added:

- App language enum must match localization resource folders.
- Info.plist `CFBundleLocalizations` must match app language enum.
- Every locale must have the same string keys as English.
- Speech language catalog must include the launch-market languages.
- Every speech language must have a localized UI label.
- Top non-gaming App Store spend markets must have UI locale coverage.
- Additional video-editing-relevant markets must have UI locale coverage.

## Sources

- RevenueCat, "Is localization the next great growth opportunity for subscription apps?" — top non-gaming app spend countries and high-growth category notes: https://www.revenuecat.com/blog/growth/is-localization-the-next-great-growth-opportunity-for-subscription-apps/
- Apple / Analysis Group, "Apple's Global App Store Ecosystem and Its Growth 2025" — App Store ecosystem and photo/video editing app context: https://www.apple.com/newsroom/pdfs/Apples_Global_App_Store_Ecosystem_and_Its_Growth_2025.pdf

## Remaining Manual QA

- Run actual short-video analysis for each speech language.
- Validate Whisper Small transcription after explicit model download.
- Validate Qwen3-ASR behavior for German, French, Spanish, Italian, and Portuguese.
- Check UI clipping for the longest German/French/Portuguese strings.
- Verify App Store build with the fully bundled JaMak runtime and signed native Python dependencies.
- Test SRT and FCPXML output with non-ASCII filenames and paths.
- Test external drive and iCloud Drive files through user-selected file access.
