# Narrateify

> A macOS menu-bar app that narrates any text on demand — selected text, a
> screen region (via OCR), or the clipboard — with a global hotkey.

Narrateify lives in your menu bar (no Dock icon) and speaks text using the TTS
engine of your choice: macOS's **built-in Apple voices** (zero setup),
**ElevenLabs** or **OpenAI** in the cloud, or **Kokoro** and **Chatterbox**
running entirely **locally and free** on your Mac.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5-orange)

---

## Features

- **Narrate from anywhere** with global hotkeys:
  | Shortcut | Action |
  |----------|--------|
  | `⌃⌥R` | Narrate the **currently selected text** (in any app) |
  | `⌃⌥S` | Drag-select a **screen region**, OCR it, and narrate the text |
  | `⌃⌥V` | Narrate whatever text is on the **clipboard** |
  | `⌃⌥N` | Open **Quick Narrate** (type or paste text) |
  | `⌃⌥Space` | Play / pause the current narration |
  | `⌃⌥X` | Stop playback |

  All shortcuts are **customizable** in *Settings → General → Shortcuts*.
- **Five TTS engines**, switchable at any time:
  - **Apple (built-in)** — macOS's on-device voices; free, offline, no API key,
    nothing to install.
  - **ElevenLabs** (cloud) — premium voices, multilingual.
  - **OpenAI** (cloud) — `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`.
  - **Kokoro-82M** (local) — fast, lightweight, free & offline.
  - **Chatterbox** (local) — expressive, multilingual (23 languages), free & offline.
- **Quick Narrate** window (`⌃⌥N`) — type or paste text and narrate it directly.
- **File narration** — narrate **PDF / txt / rtf / Markdown** files (one or
  many), with a **reading queue** that plays items back-to-back.
- **Streaming playback** *(optional)* — starts playing the first part while the
  rest is still synthesizing, for long text.
- **Floating overlay** that shows synthesis progress and turns into a draggable
  mini media player, with an adjustable **playback speed** (0.75×–2×).
- **Now Playing integration** — the **F7/F8 media keys** and Control Center
  control play/pause/skip and show the current narration.
- **Voice previews** — audition any voice with one click, right in the picker,
  before selecting it (free hosted samples for ElevenLabs; on-the-fly otherwise).
- **Voice presets** — save engine + voice + model + sliders as named presets and
  switch in one click.
- **Live highlighting** — read text in a reader window that highlights each word
  as the Apple voice speaks it.
- **Auto-narrate the clipboard** *(optional)* — reads anything you copy.
- **History** with grouping, color-coding, sort, **search**, and filter — replay,
  **share** (AirDrop/Messages/Mail/Files, with friendly filenames), or reveal any
  past narration.
- **Usage & cost dashboard** — today/month/all-time spend per engine, with an
  optional monthly budget warning.
- **First-run onboarding** that walks through permissions and the hotkeys.
- **Local-model management** — install/uninstall from the UI, see exact disk
  usage and a performance profile, and auto-start your last-used local server
  at launch.
- **Built-in update check** against this repo's GitHub releases.
- **Privacy-first** — API keys are stored in the macOS **Keychain**, local
  engines never leave your machine, and the local servers bind to `127.0.0.1`
  only.

---

## Download

Grab the latest **`Narrateify.dmg`** from the
[**Releases**](https://github.com/yasarkaancan/Narrateify/releases/latest) page,
open it, and drag **Narrateify** into your **Applications** folder.

The app and DMG are **Developer ID-signed and notarized by Apple**, so they
launch with **no Gatekeeper warning** — just open and go.

---

## Install (build from source)

Narrateify is built with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`project.yml` is the source of truth; the `.xcodeproj` is generated and
git-ignored).

```bash
# 1. Install XcodeGen (once)
brew install xcodegen

# 2. Clone and generate the Xcode project
git clone https://github.com/yasarkaancan/Narrateify.git
cd Narrateify
xcodegen generate

# 3. Open and run
open Narrateify.xcodeproj
# then press ⌘R in Xcode
```

Requirements: **macOS 14+** and **Xcode 15+**. The waveform icon appears in your
menu bar on launch.

### Permissions

On first use of a hotkey, macOS will prompt for:

- **Accessibility** — to read selected text (it synthesizes `⌘C`).
- **Screen Recording** — for the screenshot-OCR feature.

Grant both in **System Settings → Privacy & Security**, then **quit and
relaunch** (permission changes need a restart to take effect).

> The app is intentionally **unsandboxed** — the sandbox blocks posting
> keystrokes to other apps and launching `screencapture`, both of which
> Narrateify needs. Hardened Runtime stays on.

---

## Choosing a TTS engine

Open **Settings** from the menu-bar panel → **Models**, pick a provider, and
configure it. Each provider's page links to its official documentation.

### Apple (built-in) — local, free, zero setup

Pick **Apple (built-in)** and choose a **Voice**. It uses the same on-device
speech engine as the rest of macOS — no API key, no install, no network. Add
more voices (including high-quality **Premium** ✦ ones) in **System Settings →
Accessibility → Spoken Content → System Voice → Manage Voices**; newly installed
voices appear in the picker. This is the quickest way to start narrating.

### ElevenLabs (cloud)

Enter your **API key** and **Voice ID** (or load voices from the API and pick
one), then choose a model: `eleven_multilingual_v2` (quality),
`eleven_flash_v2_5` (speed), or `eleven_v3` (expressive). A per-1,000-credit
price field drives the cost estimate shown in History.

### OpenAI (cloud)

Paste your **OpenAI API key**, choose a **voice** (alloy, nova, shimmer, …) and
a **model** (`gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`). A rough per-1,000-character
cost is shown.

### Kokoro — local, free, offline

1. Pick **Kokoro (local)** and click **Install Kokoro**. A Python virtualenv is
   created under `~/.narrateify/kokoro` and the model weights (a few hundred MB)
   download there.
2. Click **Start Server** (a local server on `127.0.0.1:8765`).
3. Pick a **Voice** (e.g. `af_heart`) and narrate.

Fast & lightweight (82M params) — runs smoothly on CPU. American/British English
voices work out of the box; other languages may need `espeak-ng`
(`brew install espeak-ng`).

### Chatterbox — local, free, multilingual

1. Pick **Chatterbox (local)** and click **Install Chatterbox**. A venv is
   created under `~/.narrateify/chatterbox`; this pulls PyTorch + several GB of
   weights.
2. Click **Start Server** (`127.0.0.1:8766`). On Apple silicon it uses the GPU
   (Metal/**MPS**), falling back to CPU otherwise.
3. Pick a **Language** and tune **Exaggeration** / **CFG** under Voice settings.

Compute-heavy (0.5B params) and best on Apple-silicon GPU — higher quality and
expressive across 23 languages. The server logs the active device and
per-request timing.

### Managing local models

Each local model's section shows its **performance profile**, **download size**
before install, and **exact disk usage** once installed (everything stays under
`~/.narrateify/<model>`). You can **Stop** a server any time — including
mid-startup — and **Uninstall** to reclaim all space. Quitting Narrateify shuts
the servers down so no Python process is left running.

In **Settings → General → Startup** you can **Launch at login** and
**Auto-start the last-used local model**, so it's ready to narrate immediately.

---

## Privacy & security

- **API keys** are stored in the macOS **Keychain** (encrypted at rest), not in
  `UserDefaults` or any file. Older builds stored them in `UserDefaults`; on
  first launch the app migrates them into the Keychain and deletes the
  plaintext copy.
- **Local engines** (Kokoro, Chatterbox) run fully on-device — no text leaves
  your Mac. Their HTTP servers bind to **`127.0.0.1`** only.
- **Cloud engines** send text to ElevenLabs / OpenAI over **HTTPS** only, using
  your own API key. Review their respective privacy policies.
- The **update check** is a single read-only request to the public GitHub
  Releases API. No analytics or telemetry of any kind.

---

## Project layout

| File | Responsibility |
|------|----------------|
| `NarrateifyApp.swift` | App entry; menu bar + Settings scenes |
| `AppDelegate.swift` | Background-agent setup; registers global hotkeys; launch tasks |
| `AppState.swift` | Settings + the capture → synthesize → play pipeline |
| `HotKeyManager.swift` | System-wide hotkeys via Carbon `RegisterEventHotKey` |
| `Shortcuts.swift` | Editable shortcut bindings + the recorder UI |
| `TextCapture.swift` | Reads selected text by synthesizing `⌘C` |
| `ScreenshotOCR.swift` | Native region capture + Vision OCR |
| `TTSProvider.swift` | Provider protocol + OpenAI/Kokoro/Chatterbox clients |
| `AppleTTS.swift` | Built-in on-device `AVSpeechSynthesizer` engine → WAV |
| `QuickNarrate.swift` | Type/paste-to-narrate window |
| `FileNarration.swift` | Document text extraction + reading-queue model |
| `LiveReader.swift` | Word-highlighting reader (live Apple speech) |
| `NowPlaying.swift` | Now Playing / media-key integration |
| `Presets.swift` | Saved voice presets + their Settings section |
| `Usage.swift` | Spend aggregation + the usage dashboard |
| `Onboarding.swift` | First-run permissions/hotkeys wizard |
| `VoiceListPicker.swift` | Selectable voice list with per-row preview |
| `ElevenLabsClient.swift` | ElevenLabs TTS client + long-text chunking |
| `ServiceProvider.swift` | "Narrate with Narrateify" macOS Services entry |
| `KokoroServer.swift` / `ChatterboxServer.swift` | Local Python TTS servers (install/run/manage) |
| `LocalServerSupport.swift` | Disk-usage, byte formatting, port cleanup helpers |
| `AudioController.swift` | Queued playback + scrubbing |
| `Keychain.swift` | Secure API-key storage + legacy migration |
| `UpdateChecker.swift` | GitHub Releases update check |
| `MenuContent.swift` | Menu-bar popover UI |
| `SettingsView.swift` | Settings window (Models / General tabs) |
| `HistoryView.swift` | History tab: groups, color-coding, sort & filter |
| `NarrationHistory.swift` | Stored narrations + groups persistence |
| `SynthesisOverlay.swift` | Floating progress/player overlay |

---

## Contributing

Issues and pull requests are welcome. Because the Xcode project is generated:

1. Edit **`project.yml`** (not the `.xcodeproj`) to add files or change build
   settings, then run `xcodegen generate`.
2. Keep new source files in `Sources/` — they're picked up automatically.
3. Build before submitting: `xcodebuild -project Narrateify.xcodeproj -scheme Narrateify build`.
4. Run the tests: `xcodebuild -project Narrateify.xcodeproj -scheme Narrateify test`
   (unit tests live in `Tests/`).

### Cutting a release (maintainers)

Each release ships a drag-to-install DMG built by `scripts/make-dmg.sh`:

```bash
./scripts/make-dmg.sh                       # -> dist/Narrateify-<version>.dmg
gh release create vX.Y.Z dist/Narrateify-*.dmg --title "Narrateify vX.Y.Z" --notes "…"
```

Bump `MARKETING_VERSION` in `project.yml` before tagging. The in-app updater
compares the running version against the latest release tag, so the tag
(e.g. `v1.2.0`) must be ≥ the shipped version for users to be notified.

---

## Roadmap / known limitations

- **Selection capture** uses the clipboard-copy trick (briefly overwrites the
  clipboard, works only where `⌘C` copies). A future version could read
  `kAXSelectedTextAttribute` via the Accessibility API and fall back to copy.
- **Streaming:** an opt-in streaming mode (Settings → General → Playback) starts
  playback while later chunks synthesize. Cross-chunk scrubbing is limited in
  that mode; a true `AVAudioEngine` scheduler would make it gapless and seekable.
- **Auto-update:** the app can download and open the latest release DMG, but does
  not yet self-install silently (a Sparkle appcast would enable that).

---

## License

[MIT](LICENSE) © 2026 Yasar Kaan Can
