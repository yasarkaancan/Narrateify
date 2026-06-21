# Narrateify — Feature Plan

This document records the features implemented in this round and a curated set
of recommended future features with implementation notes. It's a living plan;
update it as items ship.

---

## Part 1 — Implemented this round

### 1. Voice demos in Models selection ✅
**What:** A **Preview voice** button at the top of *Settings → Models → Voice
settings* plays a short sample of the currently selected voice without saving it
to History.

**How it works:**
- `AppState.previewVoice()` synthesizes a fixed sample sentence with the active
  engine and plays it via `AudioController.load(data:)` (no history write).
- **ElevenLabs** uses the voice's free hosted `preview_url` when available
  (added `previewURL` to `ElevenLabsClient.Voice`), falling back to synthesis.
- **OpenAI** synthesizes a brief sample (tiny cost).
- **Kokoro / Chatterbox** synthesize locally when their server is running;
  otherwise the status line prompts the user to start it.
- `isPreviewing` drives a spinner and disables the button while in flight.

**Files:** `AppState.swift`, `ElevenLabsClient.swift`, `SettingsView.swift`.

### 2. Menu-bar animations ✅
**What:** Menu rows now highlight on hover with an animated rounded background
and a subtle press scale, giving the previously static panel some life.

**How it works:** New `MenuRowButtonStyle` (a `ButtonStyle`) tracks hover via
`onHover` and animates an accent-tinted background. Applied to all menu actions;
the transport controls keep their borderless style. A `destructive` variant
tints Quit red on hover.

**Files:** `MenuContent.swift`.

### 3. Share narrations from History ✅
**What:** Each History row has a **Share** button that opens the native macOS
share sheet (AirDrop, Messages, Mail, Save to Files, …) for the recording.

**How it works:** SwiftUI `ShareLink(item: fileURL, preview:)` pointing at the
stored audio file, with a `SharePreview` titled from the narration text.

**Files:** `HistoryView.swift`.

### 4. Settings-aware menu ✅
**What:** When the Settings window is already open, the menu's Settings row
shows **"Settings (open)"** with a filled icon and a persistent highlight, and
selecting it brings the existing window back to the front (no duplicate window).

**How it works:** `SettingsView` reports open/close via `onAppear`/`onDisappear`
to `AppState.settingsWindowOpen`; `MenuContent` renders the highlighted row and
relies on `SettingsLink` (which focuses the existing Settings scene) plus
`NSApp.activate` to surface it.

**Files:** `SettingsView.swift`, `AppState.swift`, `MenuContent.swift`.

---

## Part 1b — Quick wins (second round) ✅

### 5. Playback rate control ✅
**What:** A speed menu (0.75×–2×) in the player transport. The selected rate is
persisted and applied live to the current and future playback.

**How it works:** `AudioController.rate` (a `@Published Float`, persisted in
`UserDefaults`) is pushed to `AVAudioPlayer.rate` (with `enableRate` already on)
both on change and when a new file loads. A new `SpeedMenu` in `PlayerControls`
binds to it.

**Files:** `AudioController.swift`, `MenuContent.swift`.

### 6. Global play/pause hotkey ✅
**What:** A new editable **Play / pause** shortcut (default `⌃⌥Space`) toggles
playback from anywhere, alongside the existing capture/stop hotkeys.

**How it works:** Added `ShortcutAction.togglePlayback` to the existing editable-
shortcut system; it calls `AppState.shared.audio.togglePlayPause()`. It appears
automatically in *Settings → General → Shortcuts* and persists like the others.

**Files:** `Shortcuts.swift`.

### 7. History search ✅
**What:** A search field in the History toolbar filters records by their text (and
voice name), composing with the existing sort and provider/model filters.

**How it works:** A `searchText` state feeds `passesFilter()` via
`localizedCaseInsensitiveContains`; results animate in/out.

**Files:** `HistoryView.swift`.

### 8. Friendly export filenames ✅
**What:** Sharing a recording now offers a human-readable filename like
`Narrateify 2026-06-20 — first words.mp3` instead of the raw `<uuid>.mp3`.

**How it works:** `NarrationHistory.exportURL(for:)` lazily copies the audio into
a per-record temp subfolder under a sanitized, dated, preview-based name (reused
across renders), and the History **Share** button points at it.

**Files:** `NarrationHistory.swift`, `HistoryView.swift`.

### 9. Apple built-in TTS provider ✅
**What:** A fifth engine, **Apple (built-in)**, using macOS's on-device
`AVSpeechSynthesizer` — free, offline, no API key, nothing to install. The
Models page lists every installed system voice (with a ✦ for Premium/Enhanced)
and points users to *System Settings → Accessibility → Spoken Content* to add
more.

**How it works:** `AppleTTSClient` conforms to `TTSProvider`; it drives
`AVSpeechSynthesizer.write(_:toBufferCallback:)`, streams the PCM buffers into an
`AVAudioFile` (WAV), and returns the bytes so Apple audio flows through the same
play/save/share/history pipeline as every other provider. Speed maps onto Apple's
rate scale; cost/credits are 0.

**Files:** `AppleTTS.swift`, `TTSProvider.swift`, `AppState.swift`,
`SettingsView.swift`.

---

## Part 1c — Feature round (third round) ✅

All thirteen recommended items implemented and building; the logic helpers are
covered by unit tests (`Tests/LogicTests.swift`).

1. **Inline voice audition** — `VoiceListPicker` rows have a ▶ to preview any
   Apple/ElevenLabs voice without selecting it (`AppState.auditionApple/
   auditionElevenLabs`). Files: `VoiceListPicker.swift`, `AppState.swift`,
   `SettingsView.swift`.
2. **Quick Narrate window** — type/paste text → narrate or read; opened from the
   menu or `⌃⌥N`. Files: `QuickNarrate.swift`, `Shortcuts.swift`, `MenuContent.swift`.
3. **Apple default + onboarding** — new installs default to the Apple engine; a
   first-run wizard handles permissions and shows the hotkeys. Files:
   `Onboarding.swift`, `AppDelegate.swift`, `AppState.swift`.
4. **Watch-clipboard auto-narrate** — opt-in mode that reads newly copied text,
   with loop/duplicate guards. Files: `AppState.swift`, `SettingsView.swift`.
5. **Animated menu-bar icon** — the waveform animates (variable symbol value)
   while synthesizing/playing. Files: `NarrateifyApp.swift`.
6. **Now Playing + media keys** — `MPNowPlayingInfoCenter` /
   `MPRemoteCommandCenter` integration. Files: `NowPlaying.swift`, `AppState.swift`,
   `AudioController.swift`.
7. **Voice presets** — save/apply named engine+voice+model+slider combos. Files:
   `Presets.swift`, `AppState.swift`, `SettingsView.swift`.
8. **Usage & cost dashboard** — today/month/all-time spend, per-engine breakdown,
   and a monthly budget warning. Files: `Usage.swift`, `AppState.swift`,
   `SettingsView.swift`.
9. **Live sentence highlighting (Apple)** — a reader window highlights the spoken
   word via `willSpeakRange`. Files: `LiveReader.swift`, `AppState.swift`,
   `QuickNarrate.swift`, `MenuContent.swift`.
10. **Streaming playback** — opt-in; plays chunk 1 while later chunks synthesize
    (additive `AVQueuePlayer` mode in `AudioController`). Files:
    `AudioController.swift`, `AppState.swift`, `NowPlaying.swift`, `SettingsView.swift`.
11. **Unit tests** — `TextChunker`, `Pricing`, `UpdateChecker`, `Keychain`,
    `AppleTTSClient`. Files: `Tests/LogicTests.swift`, `project.yml`.
12. **In-app update download** — fetches the release `.dmg` asset and opens it.
    Files: `UpdateChecker.swift`, `SettingsView.swift`.
13. **File narration + reading queue** — narrate PDF/txt/rtf/md files; queue
    multiple items to play back-to-back. Files: `FileNarration.swift`,
    `AppState.swift`, `AudioController.swift`, `MenuContent.swift`.

> Note on #10 (Sparkle): rather than add the Sparkle dependency, #12 implements a
> transparent download-and-open of the notarized DMG. Full silent auto-update via
> Sparkle remains a future option.

---

## Part 1d — Reliability & refinement round (fourth round) ✅

Fourteen items: one real bug fix, several "it read the wrong thing" fixes, and
quality-of-life refinements. All build green; new logic helpers are unit-tested
(`Tests/LogicTests.swift`, now 25 cases).

1. **Multi-chunk WAV fix** *(bug)* — long text on the WAV engines (Apple/Kokoro/
   Chatterbox) used to truncate to the first chunk, because raw WAV files were
   naively concatenated (each carries its own header). `AudioJoiner` now PCM-merges
   WAV chunks into one valid file; MP3 still concatenates. Files: `AudioJoiner.swift`,
   `AppState.swift`.
2. **Synthesis retry** — one automatic retry with backoff on transient network
   errors (timeouts/dropped connections); local "not running" and HTTP errors
   aren't retried. Files: `AppState.swift`.
3. **Text preprocessing** — strips markdown, reads URLs as just their host, and
   expands abbreviations ("e.g."→"for example") before synthesis (toggle in
   *General → Text*). Files: `TextPreprocessor.swift`, `AppState.swift`, `SettingsView.swift`.
4. **Pronunciation rules** — user "say X as Y" overrides (whole-word or substring)
   applied before synthesis. Files: `TextPreprocessor.swift`, `SettingsView.swift`.
5. **Auto-detect language → voice** — `NLLanguageRecognizer` picks a matching
   Apple voice / Chatterbox language for this narration without changing the saved
   selection (opt-in). Files: `LanguageDetector.swift`, `AppState.swift`.
6. **Read article from URL** — a bare URL in Quick Narrate is fetched and the
   readable body extracted (`<article>`/`<main>`, scripts/nav stripped) and
   narrated. Files: `ArticleExtractor.swift`, `AppState.swift`, `QuickNarrate.swift`.
7. **Sleep timer** — auto-pause after 5–60 min from the menu, with remaining time.
   Files: `AppState.swift`, `MenuContent.swift`.
8. **Save As + batch group export** — per-recording "Save As…" and per-group
   "Export Recordings…" with friendly, de-duplicated filenames. Files: `HistoryView.swift`.
9. **Queue reorder & remove** — per-item ▲▼/✕ controls in the menu queue. Files:
   `AppState.swift`, `MenuContent.swift`.
10. **Cross-chunk streaming seek** — the stream player now tracks each chunk's
    timeline and rebuilds the queue to scrub across any synthesized part. Files:
    `AudioController.swift`.
11. **OpenAI cost accuracy** — `gpt-4o-mini-tts` is now estimated from audio
    minutes (it bills on tokens), not characters. Files: `TTSProvider.swift`, `AppState.swift`.
12. **Clipboard-watch power guard** — the poll loop suspends in Low Power Mode and
    resumes when it turns off. Files: `AppState.swift`.
13. **History storage controls** — optional AAC/m4a compression for WAV-engine
    recordings, and a "keep at most N" auto-prune. Files: `AudioCompressor.swift`,
    `NarrationHistory.swift`, `AppState.swift`, `SettingsView.swift`.
14. **Live reader enhancements** — word/sentence highlight toggle and a highlight
    color picker. Files: `LiveReader.swift`.
15. **Localization infrastructure** — SwiftUI `LocalizedStringKey` tables
    (`en` + Turkish `tr`) wired through XcodeGen; menu/tab/action labels translate
    with no view-code changes. Files: `Sources/Resources/{en,tr}.lproj/Localizable.strings`,
    `project.yml`.

---

## Part 1e — Scientific-paper narration ✅

Narrating papers (especially via screenshot) was noisy: in-text citations read as
"bracket sixty-five", and OCR scrambled two-column layouts. Fixed in three layers.

- **Citation cleanup** *(TextPreprocessor.swift)* — a 3-way **Off / Smart /
  Aggressive** mode (default Smart). Smart strips numeric citations (`[65]`,
  `[65, 66]`, `[70–72]`, chained `[65][66]`), re-joins hyphenated line breaks,
  expands `Fig./Eq./Tab./Sec.`, removes DOIs, and repairs the punctuation/spacing
  left behind. Aggressive also strips `(Author, 2020)` citations, reads `et al.`
  aloud, and trims a trailing References/Bibliography section. Applies to every
  input path (selection, clipboard, file, screenshot).
- **Geometry-aware OCR** *(OCRLayout.swift, ScreenshotOCR.swift)* — Vision output
  is reconstructed into true reading order: detects 1 vs 2 columns via the gutter,
  emits header → left column → right column → footer, drops low-confidence specks
  and pure margin/page numbers, and raises `minimumTextHeight`. The ordering is a
  pure, unit-tested function.
- **Screenshot review panel** *(QuickNarrate.swift, AppState.swift)* — after
  capture, the cleaned + reordered text opens in an editable window (reusing the
  Quick Narrate editor) so OCR mistakes can be fixed before narration. Toggle in
  *Settings → General → Screenshot* (default on).

Settings: *General → Text* (Academic citation cleanup mode) and *General →
Screenshot* (review toggle). Unit tests cover every transform and the column
reading-order logic (`Tests/LogicTests.swift`, now 36 cases).

---

## Part 2 — Recommended next features

Each item lists **what**, **why**, **approach**, and rough **effort** (S/M/L).

### A. Playback & audio
1. **Streaming / gapless playback** *(L)* — start playing the first chunk while
   later chunks synthesize. Approach: switch `narrate()` to a producer/consumer
   queue feeding `AVAudioEngine` (or sequential `AVAudioPlayer`s with
   prebuffering). Biggest perceived-latency win, especially for cloud engines.
2. ~~**Playback rate control in the player** *(S)*~~ — ✅ shipped (Part 1b #5).
3. **Now Playing + media keys** *(M)* — integrate `MPNowPlayingInfoCenter` and
   `MPRemoteCommandCenter` so the F7/F8 media keys and Control Center control
   play/pause/skip and show the narration as "now playing."
4. ~~**Global play/pause hotkey** *(S)*~~ — ✅ shipped (Part 1b #6).

### B. Voices & input
5. **Voice presets** *(M)* — save named combos of provider + voice + model +
   sliders (e.g. "Audiobook", "Quick notes") and switch with one click. Store as
   `Codable` in a new `presets.json`; surface a preset Picker in Models.
6. **Per-language preview samples for Chatterbox** *(S)* — extend
   `previewVoice()` with a small per-language sample dictionary so the preview is
   spoken in the selected language.
7. **Auto-detect language → voice** *(M)* — use `NLLanguageRecognizer` on the
   captured text to auto-pick a Chatterbox `language_id` (or an ElevenLabs
   multilingual voice).
8. **Pronunciation / text preprocessing** *(M)* — user-editable replacement
   rules (expand abbreviations, strip markdown/URLs, "e.g."→"for example") run in
   a preprocessing pass before `TextChunker`.
9. **File narration (PDF / ePub / txt)** *(L)* — drag a document onto the app or
   pick one; extract text (PDFKit / parsing) and narrate, with the queue below.

### C. History & organization
10. **Friendly export filenames & batch export** *(S–M)* — ✅ friendly single-
    recording names shipped (Part 1b #8). Still open: **batch export** of a whole
    group as a folder/zip.
11. **Reading queue** *(M)* — queue multiple selections/clips to play back-to-
    back; a lightweight playlist UI in the menu and overlay.
12. ~~**Search in History** *(S)*~~ — ✅ shipped (Part 1b #7).
13. **Configurable history location + size cap** *(S)* — let the user pick the
    storage folder and auto-prune old recordings past a size/age limit.

### D. Cost & accounts
14. **Usage & cost dashboard** *(M)* — aggregate `estimatedCost`/credits per
    day/month for cloud engines, with an optional monthly budget warning. Data is
    already on each `NarrationRecord`.

### E. Distribution & quality
15. **Sparkle auto-update** *(M)* — upgrade the current update *check* to actual
    in-app download/install of the notarized DMG via the Sparkle framework
    (appcast generated alongside the GitHub release).
16. **First-run onboarding** *(M)* — a short wizard guiding Accessibility/Screen
    Recording permissions and API-key/local-model setup.
17. **Automated tests** *(S–M)* — unit tests for `TextChunker`, `Pricing`,
    `UpdateChecker.isNewer`, and `Keychain` round-tripping. Cheap insurance for
    refactors.
18. **Localization** *(M)* — externalize UI strings; ship at least one extra
    language. Pairs well with the multilingual local engines.

---

## Part 3 — Suggested sequencing

1. **Quick wins:** ✅ playback rate (2), global play/pause (4), History search
   (12), friendly export (10) all shipped (Part 1b). Remaining quick wins:
   per-language previews (6), tests (17), batch export (10).
2. **High-impact medium:** Now Playing/media keys (3), voice presets (5), usage
   dashboard (14), Sparkle auto-update (15), onboarding (16).
3. **Larger bets:** streaming playback (1), file narration (9), reading queue
   (11).

Streaming playback (1) is the single biggest UX improvement and a good flagship
item for a v1.1.
