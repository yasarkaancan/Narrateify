import SwiftUI
import Combine
import AppKit
import ServiceManagement

/// Single source of truth. Holds settings (persisted in UserDefaults) and
/// orchestrates: capture text -> synthesize -> play.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Settings (persisted)
    /// Which TTS engine is active.
    @Published var provider: TTSProviderKind {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "ttsProvider") }
    }
    @Published var apiKey: String {
        didSet { Keychain.set(apiKey, account: "elevenLabsAPIKey") }
    }
    @Published var voiceId: String {
        didSet { UserDefaults.standard.set(voiceId, forKey: "elevenLabsVoiceId") }
    }
    @Published var modelId: String {
        didSet { UserDefaults.standard.set(modelId, forKey: "elevenLabsModelId") }
    }
    @Published var stability: Double {
        didSet { UserDefaults.standard.set(stability, forKey: "elevenLabsStability") }
    }
    @Published var similarityBoost: Double {
        didSet { UserDefaults.standard.set(similarityBoost, forKey: "elevenLabsSimilarity") }
    }
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "elevenLabsSpeed") }
    }
    @Published var pricePerThousand: Double {
        didSet { UserDefaults.standard.set(pricePerThousand, forKey: "pricePerThousandCredits") }
    }
    /// Master switch for the floating overlay. When off, nothing floats.
    @Published var overlayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(overlayEnabled, forKey: "overlayEnabled")
            if !overlayEnabled { SynthesisOverlay.shared.hide() }
        }
    }
    /// Keep the overlay on screen as a media player after conversion finishes.
    @Published var keepPlayerVisible: Bool {
        didSet { UserDefaults.standard.set(keepPlayerVisible, forKey: "keepPlayerVisible") }
    }
    /// When the last narration used an installed local model, start its server
    /// automatically on the next app launch.
    @Published var autoStartLocalServer: Bool {
        didSet { UserDefaults.standard.set(autoStartLocalServer, forKey: "autoStartLocalServer") }
    }
    /// Whether Narrateify launches automatically at login (macOS login item).
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else             { try SMAppService.mainApp.unregister() }
            } catch {
                status = "Login item error: \(error.localizedDescription)"
            }
        }
    }
    /// The provider used by the most recent narration (drives auto-start).
    @Published var lastUsedProvider: TTSProviderKind? {
        didSet { UserDefaults.standard.set(lastUsedProvider?.rawValue, forKey: "lastUsedProvider") }
    }
    /// Selected Kokoro voice (local engine).
    @Published var kokoroVoice: String {
        didSet { UserDefaults.standard.set(kokoroVoice, forKey: "kokoroVoice") }
    }
    /// Selected Apple system-voice identifier (built-in, on-device engine).
    @Published var appleVoice: String {
        didSet { UserDefaults.standard.set(appleVoice, forKey: "appleVoice") }
    }
    /// When on, newly copied clipboard text is narrated automatically.
    @Published var clipboardWatch: Bool {
        didSet {
            UserDefaults.standard.set(clipboardWatch, forKey: "clipboardWatch")
            clipboardWatch ? startClipboardWatch() : stopClipboardWatch()
        }
    }
    /// Saved voice presets (engine + voice + model + sliders).
    @Published var presets: [VoicePreset] {
        didSet { persistPresets() }
    }
    /// Optional monthly spend cap (USD) for cloud engines; 0 = no budget.
    @Published var monthlyBudget: Double {
        didSet { UserDefaults.standard.set(monthlyBudget, forKey: "monthlyBudget") }
    }
    /// Start playing the first chunk while later chunks still synthesize.
    @Published var streamPlayback: Bool {
        didSet { UserDefaults.standard.set(streamPlayback, forKey: "streamPlayback") }
    }
    // OpenAI (cloud) settings.
    @Published var openAIKey: String {
        didSet { Keychain.set(openAIKey, account: "openAIKey") }
    }
    @Published var openAIVoice: String {
        didSet { UserDefaults.standard.set(openAIVoice, forKey: "openAIVoice") }
    }
    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") }
    }
    /// Selected Chatterbox language (local engine; "voice" == language_id).
    @Published var chatterboxLanguage: String {
        didSet { UserDefaults.standard.set(chatterboxLanguage, forKey: "chatterboxLanguage") }
    }
    /// Chatterbox expressiveness knobs.
    @Published var chatterboxExaggeration: Double {
        didSet { UserDefaults.standard.set(chatterboxExaggeration, forKey: "chatterboxExaggeration") }
    }
    @Published var chatterboxCfgWeight: Double {
        didSet { UserDefaults.standard.set(chatterboxCfgWeight, forKey: "chatterboxCfgWeight") }
    }

    // MARK: Runtime state
    @Published var status: String = "Ready"
    /// True while audio is being synthesized (drives the overlay's first phase).
    @Published private(set) var isSynthesizing = false
    /// True while a short voice preview is being fetched/synthesized.
    @Published private(set) var isPreviewing = false
    /// Whether the Settings window is currently on screen (drives the menu's
    /// "Settings (open)" affordance).
    @Published var settingsWindowOpen = false
    /// Pending reading-queue items (played back-to-back after the current one).
    @Published var queue: [QueueItem] = []
    /// Voices fetched from the ElevenLabs API (not persisted).
    @Published var voices: [ElevenLabsClient.Voice] = []
    @Published var voicesStatus: String = ""
    /// Available Kokoro voices (defaults built-in; refreshed from the server).
    @Published var kokoroVoices: [String] = KokoroClient.defaultVoices
    /// Available Chatterbox languages (defaults built-in; refreshed from server).
    @Published var chatterboxVoices: [String] = ChatterboxClient.defaultVoices
    let audio = AudioController()
    let history = NarrationHistory()
    let kokoro = KokoroServer()
    let chatterbox = ChatterboxServer()
    let shortcutStore = ShortcutStore()
    let updateChecker = UpdateChecker()

    private init() {
        let d = UserDefaults.standard
        // New installs default to Apple's built-in engine — it works instantly
        // with no API key or download. Existing users keep their stored choice.
        provider = TTSProviderKind(rawValue: d.string(forKey: "ttsProvider") ?? "") ?? .appleTTS
        // API keys live in the Keychain; transparently migrate any legacy
        // plaintext value stored in UserDefaults by older builds.
        apiKey  = Keychain.migratingValue(account: "elevenLabsAPIKey",
                                          legacyDefaultsKey: "elevenLabsAPIKey")
        voiceId = d.string(forKey: "elevenLabsVoiceId") ?? "21m00Tcm4TlvDq8ikWAM" // "Rachel" demo voice
        modelId = d.string(forKey: "elevenLabsModelId") ?? "eleven_multilingual_v2"
        stability       = d.object(forKey: "elevenLabsStability") as? Double ?? 0.5
        similarityBoost = d.object(forKey: "elevenLabsSimilarity") as? Double ?? 0.75
        speed           = d.object(forKey: "elevenLabsSpeed") as? Double ?? 1.0
        pricePerThousand = d.object(forKey: "pricePerThousandCredits") as? Double ?? 0.30
        overlayEnabled    = d.object(forKey: "overlayEnabled") as? Bool ?? true
        keepPlayerVisible = d.object(forKey: "keepPlayerVisible") as? Bool ?? true
        autoStartLocalServer = d.object(forKey: "autoStartLocalServer") as? Bool ?? true
        // Reflect the real login-item state rather than a stored guess.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        lastUsedProvider = (d.string(forKey: "lastUsedProvider"))
            .flatMap(TTSProviderKind.init(rawValue:))
        openAIKey   = Keychain.migratingValue(account: "openAIKey",
                                              legacyDefaultsKey: "openAIKey")
        openAIVoice = d.string(forKey: "openAIVoice") ?? "alloy"
        openAIModel = d.string(forKey: "openAIModel") ?? "gpt-4o-mini-tts"
        kokoroVoice = d.string(forKey: "kokoroVoice") ?? "af_heart"
        appleVoice  = d.string(forKey: "appleVoice")
            ?? AppleTTSClient.defaultVoiceIdentifier()
        clipboardWatch = d.object(forKey: "clipboardWatch") as? Bool ?? false
        presets = (d.data(forKey: "voicePresets"))
            .flatMap { try? JSONDecoder().decode([VoicePreset].self, from: $0) } ?? []
        monthlyBudget = d.object(forKey: "monthlyBudget") as? Double ?? 0
        streamPlayback = d.object(forKey: "streamPlayback") as? Bool ?? false
        chatterboxLanguage = d.string(forKey: "chatterboxLanguage") ?? "en"
        chatterboxExaggeration = d.object(forKey: "chatterboxExaggeration") as? Double ?? 0.5
        chatterboxCfgWeight    = d.object(forKey: "chatterboxCfgWeight") as? Double ?? 0.5

        // Re-publish AppState when the audio controller's published state changes,
        // so the menu bar icon/status stay in sync — and keep the system
        // Now Playing info (media keys / Control Center) current.
        audio.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.refreshNowPlaying()
            }
            .store(in: &cancellables)
        // Likewise for history changes (so the Settings list updates live).
        history.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // …and the Kokoro server's install/run status + log.
        kokoro.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // …and the Chatterbox server's install/run status + log.
        chatterbox.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // …and the editable keyboard-shortcut bindings.
        shortcutStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // …and the GitHub update checker's result.
        updateChecker.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Begin watching the clipboard if the user left it enabled.
        if clipboardWatch { startClipboardWatch() }

        // Advance the reading queue (and clear Now Playing) when playback ends.
        audio.onFinished = { [weak self] in self?.handlePlaybackFinished() }

        // Hook the media keys / Control Center transport to playback.
        NowPlayingController.shared.activate(
            play:   { [weak self] in self?.audio.play() },
            pause:  { [weak self] in self?.audio.pause() },
            toggle: { [weak self] in self?.audio.togglePlayPause() },
            skipBy: { [weak self] s in self?.audio.skip(by: s) },
            seekTo: { [weak self] t in self?.audio.seek(to: t) }
        )
    }

    /// Title shown in the system Now Playing panel for the current narration.
    private func startNowPlaying(_ title: String) {
        NowPlayingController.shared.setTrack(title: title, duration: audio.duration)
    }

    private func refreshNowPlaying() {
        guard audio.hasAudio else { return }
        NowPlayingController.shared.updatePlayback(elapsed: audio.currentTime,
                                                   rate: audio.rate,
                                                   isPlaying: audio.isPlaying,
                                                   duration: audio.duration)
    }
    private var cancellables = Set<AnyCancellable>()

    private var voiceSettings: ElevenLabsClient.VoiceSettings {
        .init(stability: stability, similarityBoost: similarityBoost, speed: speed)
    }

    // MARK: Triggers

    func narrateSelection() {
        status = "Reading selection…"
        // The selection grab copies (and restores) the clipboard; keep the
        // clipboard watcher from reacting to that.
        suppressClipboardWatch()
        TextCapture.selectedText { [weak self] text in
            guard let self else { return }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                self.status = AXIsProcessTrusted()
                    ? "No text selected"
                    : "Grant Accessibility access in System Settings"
                return
            }
            self.narrate(trimmed)
        }
    }

    func narrateScreenshot() {
        status = "Select a region…"
        ScreenshotOCR.captureAndRecognize { [weak self] text in
            guard let self else { return }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                self.status = "No text found (or capture cancelled)"
                return
            }
            self.narrate(trimmed)
        }
    }

    func narrateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            status = "Clipboard has no text"
            return
        }
        narrate(text)
    }

    func stop() {
        audio.stop()
        queue.removeAll()
        status = "Stopped"
        NowPlayingController.shared.clear()
    }

    /// Opens the Quick Narrate window (type/paste text → narrate).
    func showQuickNarrate() {
        QuickNarrateWindow.shared.show()
    }

    // MARK: Reading queue

    /// Narrate text now if idle, otherwise add it to the queue.
    func enqueue(_ text: String, title: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if audio.hasAudio || isSynthesizing {
            queue.append(QueueItem(title: title ?? String(trimmed.prefix(50)), text: trimmed))
            status = "Queued — \(queue.count) waiting"
        } else {
            narrate(trimmed)
        }
    }

    func clearQueue() { queue.removeAll() }

    private func playNextInQueue() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        narrate(next.text)
    }

    private func handlePlaybackFinished() {
        if queue.isEmpty {
            NowPlayingController.shared.clear()
        } else {
            playNextInQueue()
        }
    }

    /// Prompts for one or more documents (PDF/txt/rtf/md), extracts their text,
    /// and narrates / queues them.
    func narrateFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileTextExtractor.allowedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var added = 0
        var failed: [String] = []
        for url in panel.urls {
            if let text = FileTextExtractor.extract(from: url)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                enqueue(text, title: url.lastPathComponent)
                added += 1
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        if added == 0 && !failed.isEmpty {
            status = "Couldn't read text from \(failed.joined(separator: ", "))"
        } else if !failed.isEmpty {
            status = "Skipped \(failed.count) unreadable file(s)"
        }
    }

    /// Opens the live reader (word-by-word highlighting) for the given text,
    /// always using Apple's on-device engine since only it emits word ranges.
    func readAloudHighlighted(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "No text to read"; return }
        let voice = appleVoice.isEmpty ? AppleTTSClient.defaultVoiceIdentifier() : appleVoice
        ReaderWindow.shared.show(text: trimmed, voiceIdentifier: voice, speed: speed)
    }

    /// Reads the current clipboard text in the live reader.
    func readClipboardHighlighted() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        readAloudHighlighted(text)
    }

    // MARK: Presets

    func saveCurrentAsPreset(named name: String) {
        presets.append(VoicePreset(
            name: name,
            provider: provider.rawValue,
            voiceId: voiceId,
            modelId: modelId,
            stability: stability,
            similarityBoost: similarityBoost,
            speed: speed,
            openAIVoice: openAIVoice,
            openAIModel: openAIModel,
            kokoroVoice: kokoroVoice,
            appleVoice: appleVoice,
            chatterboxLanguage: chatterboxLanguage,
            chatterboxExaggeration: chatterboxExaggeration,
            chatterboxCfgWeight: chatterboxCfgWeight))
    }

    func applyPreset(_ p: VoicePreset) {
        if let kind = TTSProviderKind(rawValue: p.provider) { provider = kind }
        voiceId = p.voiceId
        modelId = p.modelId
        stability = p.stability
        similarityBoost = p.similarityBoost
        speed = p.speed
        openAIVoice = p.openAIVoice
        openAIModel = p.openAIModel
        kokoroVoice = p.kokoroVoice
        appleVoice = p.appleVoice
        chatterboxLanguage = p.chatterboxLanguage
        chatterboxExaggeration = p.chatterboxExaggeration
        chatterboxCfgWeight = p.chatterboxCfgWeight
    }

    func deletePreset(_ p: VoicePreset) {
        presets.removeAll { $0.id == p.id }
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: "voicePresets")
    }

    // MARK: Clipboard watch

    private var clipboardTimer: Timer?
    private var lastClipboardChange = NSPasteboard.general.changeCount
    private var lastClipboardText = ""
    /// Programmatic pasteboard use (e.g. the selection grab) sets this so the
    /// watcher ignores the resulting changes.
    private var suppressClipboardUntil = Date.distantPast

    private func suppressClipboardWatch(for seconds: TimeInterval = 1.5) {
        suppressClipboardUntil = Date().addingTimeInterval(seconds)
    }

    private func startClipboardWatch() {
        lastClipboardChange = NSPasteboard.general.changeCount
        clipboardTimer?.invalidate()
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
        RunLoop.main.add(t, forMode: .common)
        clipboardTimer = t
        status = "Watching clipboard…"
    }

    private func stopClipboardWatch() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardChange else { return }
        lastClipboardChange = pb.changeCount
        // Skip our own pipeline activity and the selection-copy round-trip.
        guard !isSynthesizing, Date() >= suppressClipboardUntil else { return }
        let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text != lastClipboardText else { return }
        lastClipboardText = text
        narrate(text)
    }

    // MARK: Voices

    func refreshVoices() {
        let key = apiKey
        guard !key.isEmpty else {
            voicesStatus = "Enter your API key first."
            return
        }
        voicesStatus = "Loading voices…"
        Task {
            do {
                let fetched = try await ElevenLabsClient.fetchVoices(apiKey: key)
                self.voices = fetched.sorted { $0.name.lowercased() < $1.name.lowercased() }
                self.voicesStatus = "\(fetched.count) voices loaded"
            } catch {
                self.voicesStatus = error.localizedDescription
            }
        }
    }

    /// Pull the Kokoro voice list from the running local server.
    func refreshKokoroVoices() {
        let url = kokoro.baseURL
        Task {
            if let fetched = try? await KokoroClient.fetchVoices(baseURL: url), !fetched.isEmpty {
                self.kokoroVoices = fetched
            }
        }
    }

    /// Pull the Chatterbox language list from the running local server.
    func refreshChatterboxVoices() {
        let url = chatterbox.baseURL
        Task {
            if let fetched = try? await ChatterboxClient.fetchVoices(baseURL: url), !fetched.isEmpty {
                self.chatterboxVoices = fetched
            }
        }
    }

    // MARK: Voice preview

    /// Plays a short sample of the currently-selected voice so the user can
    /// audition it before narrating. Uses ElevenLabs' free hosted preview when
    /// available; otherwise synthesizes a brief sample with the active engine.
    /// Previews are NOT saved to history.
    /// The fixed sentence spoken by all voice previews.
    static let previewSample = "Hi! This is a quick preview of how this voice sounds."

    /// Audition a specific Apple system voice (by identifier) without changing
    /// the current selection. Not saved to history.
    func auditionApple(_ identifier: String) {
        guard !isPreviewing else { return }
        isPreviewing = true
        status = "Previewing \(AppleTTSClient.displayName(for: identifier))…"
        Task {
            do {
                let client = AppleTTSClient(voiceIdentifier: identifier, speed: speed)
                let data = try await client.synthesize(text: Self.previewSample)
                self.audio.load(data: data)
                self.status = "Voice preview"
                self.startNowPlaying("Voice preview")
            } catch {
                self.status = error.localizedDescription
            }
            self.isPreviewing = false
        }
    }

    /// Audition a specific ElevenLabs voice without changing the selection.
    /// Uses the free hosted preview when available; otherwise synthesizes.
    func auditionElevenLabs(_ voice: ElevenLabsClient.Voice) {
        guard !isPreviewing else { return }
        isPreviewing = true
        status = "Previewing \(voice.name)…"
        Task {
            do {
                let data: Data
                if let preview = voice.previewURL {
                    (data, _) = try await URLSession.shared.data(from: preview)
                } else {
                    let client = ElevenLabsClient(apiKey: apiKey, voiceId: voice.voiceId,
                                                  modelId: modelId, settings: voiceSettings)
                    data = try await client.synthesize(text: Self.previewSample)
                }
                self.audio.load(data: data)
                self.status = "Voice preview"
                self.startNowPlaying("Voice preview")
            } catch {
                self.status = error.localizedDescription
            }
            self.isPreviewing = false
        }
    }

    func previewVoice() {
        guard !isPreviewing else { return }
        let sample = Self.previewSample
        isPreviewing = true
        status = "Previewing voice…"

        Task {
            do {
                let data: Data
                switch provider {
                case .appleTTS:
                    let client = AppleTTSClient(voiceIdentifier: appleVoice, speed: speed)
                    data = try await client.synthesize(text: sample)
                case .elevenLabs:
                    if let v = voices.first(where: { $0.voiceId == voiceId }),
                       let preview = v.previewURL {
                        (data, _) = try await URLSession.shared.data(from: preview)
                    } else {
                        let client = ElevenLabsClient(apiKey: apiKey, voiceId: voiceId,
                                                      modelId: modelId, settings: voiceSettings)
                        data = try await client.synthesize(text: sample)
                    }
                case .openAI:
                    let client = OpenAIClient(apiKey: openAIKey, voice: openAIVoice,
                                              model: openAIModel, speed: speed)
                    data = try await client.synthesize(text: sample)
                case .kokoro:
                    guard kokoro.status == .running else {
                        status = "Start the Kokoro server to preview."
                        isPreviewing = false; return
                    }
                    let client = KokoroClient(baseURL: kokoro.baseURL, voice: kokoroVoice, speed: speed)
                    data = try await client.synthesize(text: sample)
                case .chatterbox:
                    guard chatterbox.status == .running else {
                        status = "Start the Chatterbox server to preview."
                        isPreviewing = false; return
                    }
                    let client = ChatterboxClient(baseURL: chatterbox.baseURL,
                                                  language: chatterboxLanguage,
                                                  exaggeration: chatterboxExaggeration,
                                                  cfgWeight: chatterboxCfgWeight)
                    data = try await client.synthesize(text: sample)
                }
                self.audio.load(data: data)
                self.status = "Voice preview"
                self.startNowPlaying("Voice preview")
            } catch {
                self.status = error.localizedDescription
            }
            self.isPreviewing = false
        }
    }

    // MARK: History playback

    /// Re-play a previously saved narration from history.
    func play(_ record: NarrationRecord) {
        audio.load(url: history.fileURL(for: record))
        status = "Playing"
        startNowPlaying(record.preview.isEmpty ? "Narration" : record.preview)
    }

    func delete(_ record: NarrationRecord) {
        history.delete(record)
    }

    // MARK: Overlay

    /// Dismiss the floating overlay (leaves any audio playing — reachable from
    /// the menu). Triggered by the overlay's close button.
    func closeOverlay() {
        SynthesisOverlay.shared.hide()
    }

    /// The overlay's "end" control: stop playback and dismiss the overlay.
    func endNarration() {
        audio.stop()
        status = "Stopped"
        NowPlayingController.shared.clear()
        SynthesisOverlay.shared.hide()
    }

    func resetOverlayPosition() {
        SynthesisOverlay.shared.resetPosition()
    }

    // MARK: Startup / shutdown

    /// On launch: if the last narration used a local model that's installed,
    /// start its server so it's ready without the user opening Settings.
    func autoStartLastServerIfNeeded() {
        guard autoStartLocalServer else { return }
        switch lastUsedProvider {
        case .kokoro     where kokoro.isInstalled:     kokoro.start()
        case .chatterbox where chatterbox.isInstalled: chatterbox.start()
        default: break
        }
    }

    /// Terminate any running local servers — called on app quit so we never
    /// leave orphaned Python processes behind.
    func shutdownServers() {
        kokoro.stop()
        chatterbox.stop()
    }

    // MARK: Pipeline

    func narrate(_ text: String) {
        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else { return }
        // Remember what we're narrating so the clipboard watcher won't repeat it.
        lastClipboardText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve the active engine and the metadata we'll record with it.
        let engine: TTSProviderKind = provider
        let client: TTSProvider
        let voiceId: String
        let voiceName: String
        let modelId: String
        let credits: Double
        let cost: Double
        let fileExtension: String

        switch engine {
        case .appleTTS:
            client = AppleTTSClient(voiceIdentifier: appleVoice, speed: speed)
            voiceId = appleVoice
            voiceName = AppleTTSClient.displayName(for: appleVoice)
            modelId = "apple-tts"
            credits = 0          // built-in + free
            cost = 0
            fileExtension = "wav"
        case .elevenLabs:
            client = ElevenLabsClient(apiKey: apiKey, voiceId: self.voiceId,
                                      modelId: self.modelId, settings: voiceSettings)
            voiceId = self.voiceId
            voiceName = voices.first { $0.voiceId == self.voiceId }?.name ?? self.voiceId
            modelId = self.modelId
            credits = Pricing.credits(characters: text.count, modelId: self.modelId)
            cost = Pricing.cost(credits: credits, pricePerThousand: pricePerThousand)
            fileExtension = "mp3"
        case .openAI:
            client = OpenAIClient(apiKey: openAIKey, voice: openAIVoice,
                                  model: openAIModel, speed: speed)
            voiceId = openAIVoice
            voiceName = openAIVoice
            modelId = openAIModel
            credits = 0          // OpenAI bills per character, not credits
            cost = Double(text.count) / 1000.0
                 * OpenAIClient.pricePerThousand(model: openAIModel)
            fileExtension = "mp3"
        case .kokoro:
            guard kokoro.status == .running else {
                status = "Start the Kokoro server in Settings → Models."
                return
            }
            client = KokoroClient(baseURL: kokoro.baseURL, voice: kokoroVoice, speed: speed)
            voiceId = kokoroVoice
            voiceName = kokoroVoice
            modelId = "kokoro"
            credits = 0          // local + free
            cost = 0
            fileExtension = "wav"
        case .chatterbox:
            guard chatterbox.status == .running else {
                status = "Start the Chatterbox server in Settings → Models."
                return
            }
            client = ChatterboxClient(baseURL: chatterbox.baseURL,
                                      language: chatterboxLanguage,
                                      exaggeration: chatterboxExaggeration,
                                      cfgWeight: chatterboxCfgWeight)
            voiceId = chatterboxLanguage
            voiceName = ChatterboxClient.languageName(chatterboxLanguage)
            modelId = "chatterbox-multilingual"
            credits = 0          // local + free
            cost = 0
            fileExtension = "wav"
        }

        // Remember what we actually used, so we can auto-start it next launch.
        lastUsedProvider = engine

        audio.stop()
        status = "Synthesizing…"
        // Slick floating indicator — visible whether narration was triggered by
        // a global hotkey or from the menu. It morphs into a media player once
        // playback starts (unless the user has turned either behavior off).
        isSynthesizing = true
        if overlayEnabled { SynthesisOverlay.shared.show() }

        // Stream only when it helps: opted in and more than one chunk.
        let streaming = streamPlayback && chunks.count > 1
        let title = String(text.prefix(80))

        Task {
            do {
                var combined = Data()

                if streaming {
                    // Start playing chunk 1 as soon as it's ready, enqueuing the
                    // rest as they finish — while still building the combined file
                    // for history.
                    let dir = self.streamingTempDir(reset: true)
                    self.audio.beginStreaming()
                    self.isSynthesizing = false
                    self.status = "Streaming…"
                    self.startNowPlaying(title.isEmpty ? "Narration" : title)
                    for (i, chunk) in chunks.enumerated() {
                        let data = try await client.synthesize(text: chunk)
                        combined.append(data)
                        let url = dir.appendingPathComponent("chunk-\(i).\(fileExtension)")
                        try? data.write(to: url)
                        self.audio.enqueueStreaming(url: url)
                    }
                    self.status = "Playing"
                } else {
                    // Synthesize every chunk and concatenate into one file, so the
                    // player can scrub/seek across the whole narration.
                    for chunk in chunks {
                        combined.append(try await client.synthesize(text: chunk))
                    }
                }

                let record = try self.history.save(audio: combined,
                                                   text: text,
                                                   engine: engine.engineName,
                                                   voiceId: voiceId,
                                                   voiceName: voiceName,
                                                   modelId: modelId,
                                                   credits: credits,
                                                   estimatedCost: cost,
                                                   fileExtension: fileExtension)
                if !streaming {
                    self.isSynthesizing = false
                    self.audio.load(url: self.history.fileURL(for: record))
                    self.status = "Playing"
                    self.startNowPlaying(record.preview.isEmpty ? "Narration" : record.preview)
                }
                // Keep the overlay as a floating player, or dismiss it.
                if !(self.overlayEnabled && self.keepPlayerVisible) {
                    SynthesisOverlay.shared.hide()
                }
            } catch {
                self.isSynthesizing = false
                self.status = error.localizedDescription
                SynthesisOverlay.shared.hide()
            }
        }
    }

    /// Scratch directory for streamed chunk files.
    private func streamingTempDir(reset: Bool = false) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Narrateify-Stream", isDirectory: true)
        if reset { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
