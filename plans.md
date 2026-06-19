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

## Part 2 — Recommended next features

Each item lists **what**, **why**, **approach**, and rough **effort** (S/M/L).

### A. Playback & audio
1. **Streaming / gapless playback** *(L)* — start playing the first chunk while
   later chunks synthesize. Approach: switch `narrate()` to a producer/consumer
   queue feeding `AVAudioEngine` (or sequential `AVAudioPlayer`s with
   prebuffering). Biggest perceived-latency win, especially for cloud engines.
2. **Playback rate control in the player** *(S)* — expose a 0.75×–2× speed
   control in `PlayerControls` and the overlay. `AVAudioPlayer.enableRate` is
   already on; just bind `player.rate`.
3. **Now Playing + media keys** *(M)* — integrate `MPNowPlayingInfoCenter` and
   `MPRemoteCommandCenter` so the F7/F8 media keys and Control Center control
   play/pause/skip and show the narration as "now playing."
4. **Global play/pause hotkey** *(S)* — add a `ShortcutAction.togglePlayback`
   bound through the existing editable-shortcut system.

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
10. **Friendly export filenames & batch export** *(S–M)* — export a recording
    (or a whole group) with names like `Narrateify 2026-06-20 — first words.wav`.
    Improves on raw UUID filenames in Share/Save.
11. **Reading queue** *(M)* — queue multiple selections/clips to play back-to-
    back; a lightweight playlist UI in the menu and overlay.
12. **Search in History** *(S)* — a search field filtering records by text
    content, complementing the existing sort/filter.
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

1. **Quick wins first:** playback rate control (2), global play/pause (4),
   per-language previews (6), History search (12), friendly export (10), tests
   (17).
2. **High-impact medium:** Now Playing/media keys (3), voice presets (5), usage
   dashboard (14), Sparkle auto-update (15), onboarding (16).
3. **Larger bets:** streaming playback (1), file narration (9), reading queue
   (11).

Streaming playback (1) is the single biggest UX improvement and a good flagship
item for a v1.1.
