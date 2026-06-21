import SwiftUI
import Combine
import AppKit
import AVFoundation
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
    /// Clean text before synthesis (strip markdown, expand abbreviations, tidy
    /// URLs) so voices stop reading literal `**` and raw links.
    @Published var cleanText: Bool {
        didSet { UserDefaults.standard.set(cleanText, forKey: "cleanText") }
    }
    /// User "say X as Y" pronunciation overrides, applied before synthesis.
    @Published var pronunciations: [PronunciationRule] {
        didSet {
            if let data = try? JSONEncoder().encode(pronunciations) {
                UserDefaults.standard.set(data, forKey: "pronunciations")
            }
        }
    }
    /// Auto-pick a voice that matches the text's detected language (Apple voices
    /// and Chatterbox languages). Off by default so an explicit voice choice is
    /// respected unless the user opts in.
    @Published var autoDetectLanguage: Bool {
        didSet { UserDefaults.standard.set(autoDetectLanguage, forKey: "autoDetectLanguage") }
    }
    /// How aggressively to strip scientific-paper citation noise ([65], author-
    /// year, reference lists) before synthesis.
    @Published var citationMode: CitationCleanupMode {
        didSet { UserDefaults.standard.set(citationMode.rawValue, forKey: "citationMode") }
    }
    /// Show the recognized text in an editable window before narrating a
    /// screenshot, so OCR mistakes can be fixed first.
    @Published var reviewScreenshotText: Bool {
        didSet { UserDefaults.standard.set(reviewScreenshotText, forKey: "reviewScreenshotText") }
    }
    /// Maximum number of history recordings to keep (0 = unlimited). Older
    /// recordings beyond this are pruned automatically.
    @Published var historyLimit: Int {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
            history.prune(maxItems: historyLimit)
        }
    }
    /// Store WAV-engine output (Apple/Kokoro/Chatterbox) as compressed m4a.
    @Published var compressAudio: Bool {
        didSet { UserDefaults.standard.set(compressAudio, forKey: "compressAudio") }
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
    /// When set, playback auto-pauses at this time (sleep timer).
    @Published private(set) var sleepTimerEnds: Date?
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
        cleanText = d.object(forKey: "cleanText") as? Bool ?? true
        pronunciations = (d.data(forKey: "pronunciations"))
            .flatMap { try? JSONDecoder().decode([PronunciationRule].self, from: $0) } ?? []
        autoDetectLanguage = d.object(forKey: "autoDetectLanguage") as? Bool ?? false
        citationMode = CitationCleanupMode(rawValue: d.string(forKey: "citationMode") ?? "") ?? .smart
        reviewScreenshotText = d.object(forKey: "reviewScreenshotText") as? Bool ?? true
        historyLimit = d.object(forKey: "historyLimit") as? Int ?? 0
        compressAudio = d.object(forKey: "compressAudio") as? Bool ?? false
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

    /// Preprocessor built from the current settings. Pronunciation rules always
    /// apply; the markdown/abbreviation/URL stages follow the `cleanText` toggle.
    var textPreprocessor: TextPreprocessor {
        TextPreprocessor(stripMarkdown: cleanText,
                         expandAbbreviations: cleanText,
                         simplifyURLs: cleanText,
                         citationMode: citationMode,
                         pronunciations: pronunciations)
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
            // OCR is imperfect on dense papers — let the user review/fix the
            // cleaned text before it's spoken (unless they've opted out).
            if self.reviewScreenshotText {
                let cleaned = self.textPreprocessor.process(trimmed)
                self.status = "Review the recognized text"
                TextReviewWindow.shared.show(text: cleaned, title: "Review Screenshot Text")
            } else {
                self.narrate(trimmed)
            }
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

    /// Fetch a web page's readable text and narrate it (queues if busy).
    func narrateURL(_ url: URL) {
        status = "Fetching \(url.host ?? "page")…"
        Task {
            do {
                let article = try await ArticleExtractor.fetch(url)
                self.enqueue(article.text, title: article.title)
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    /// A bare http(s) URL (no surrounding text), suitable for article fetching.
    nonisolated static func bareURL(in text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }),
              s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://"),
              let url = URL(string: s), url.host != nil else { return nil }
        return url
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

    /// Remove a single queued item.
    func removeFromQueue(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
    }

    /// Reorder queued items (driven by the menu's drag handles).
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
    }

    // MARK: Sleep timer

    private var sleepTimer: Timer?

    /// Auto-pause playback (and stop advancing the queue) after `minutes`.
    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        let ends = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        sleepTimerEnds = ends
        let t = Timer(timeInterval: TimeInterval(minutes) * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireSleepTimer() }
        }
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEnds = nil
    }

    private func fireSleepTimer() {
        sleepTimer = nil
        sleepTimerEnds = nil
        queue.removeAll()      // don't roll into the next queued item
        audio.pause()
        status = "Paused by sleep timer"
    }

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

    private var powerObserver: NSObjectProtocol?

    private func startClipboardWatch() {
        // Suspend the poll loop in Low Power Mode to save battery; resume when it
        // turns off. (Observe the power-state change once.)
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconcileClipboardWatch() }
            }
        }
        reconcileClipboardWatch()
    }

    private func stopClipboardWatch() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
    }

    /// Start/stop the poll loop to match the watch setting and power state.
    private func reconcileClipboardWatch() {
        guard clipboardWatch else {
            clipboardTimer?.invalidate(); clipboardTimer = nil
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            clipboardTimer?.invalidate(); clipboardTimer = nil
            status = "Clipboard watch paused (Low Power Mode)"
            return
        }
        guard clipboardTimer == nil else { return }
        lastClipboardChange = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
        RunLoop.main.add(t, forMode: .common)
        clipboardTimer = t
        status = "Watching clipboard…"
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

    /// Synthesize one chunk, retrying once after a short backoff on transient
    /// network errors (timeouts, dropped connections). Local-server "not running"
    /// errors and HTTP failures aren't retried — a retry wouldn't help.
    private func synthesize(_ client: TTSProvider, text: String, retries: Int = 1) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await client.synthesize(text: text)
            } catch {
                attempt += 1
                guard attempt <= retries, Self.isTransient(error) else { throw error }
                let backoff = 0.8 * Double(attempt)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }

    /// Whether an error is a transient network condition worth retrying.
    private static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    func narrate(_ text: String) {
        // Remember the raw text so the clipboard watcher won't repeat it, then
        // clean it (markdown/URLs/abbreviations + pronunciation rules) before
        // synthesis. `spoken` is what we actually voice, save, and bill.
        lastClipboardText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = textPreprocessor.process(text)
        let chunks = TextChunker.chunk(spoken)
        guard !chunks.isEmpty else { return }

        // Optionally match the voice to the text's detected language. These are
        // local overrides for this narration only — the user's saved selection
        // is left untouched.
        let autoBase = autoDetectLanguage ? LanguageDetector.detectBaseCode(spoken) : nil
        let effectiveAppleVoice = appleVoiceMatching(autoBase) ?? appleVoice
        let effectiveChatterboxLanguage = chatterboxLanguageMatching(autoBase) ?? chatterboxLanguage

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
            client = AppleTTSClient(voiceIdentifier: effectiveAppleVoice, speed: speed)
            voiceId = effectiveAppleVoice
            voiceName = AppleTTSClient.displayName(for: effectiveAppleVoice)
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
            credits = Pricing.credits(characters: spoken.count, modelId: self.modelId)
            cost = Pricing.cost(credits: credits, pricePerThousand: pricePerThousand)
            fileExtension = "mp3"
        case .openAI:
            client = OpenAIClient(apiKey: openAIKey, voice: openAIVoice,
                                  model: openAIModel, speed: speed)
            voiceId = openAIVoice
            voiceName = openAIVoice
            modelId = openAIModel
            credits = 0          // OpenAI bills per character, not credits
            cost = Double(spoken.count) / 1000.0
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
                                      language: effectiveChatterboxLanguage,
                                      exaggeration: chatterboxExaggeration,
                                      cfgWeight: chatterboxCfgWeight)
            voiceId = effectiveChatterboxLanguage
            voiceName = ChatterboxClient.languageName(effectiveChatterboxLanguage)
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
        let title = String(spoken.prefix(80))

        Task {
            do {
                // Collect each chunk's bytes so we can join them into one valid
                // file. WAV chunks can't be naively concatenated (each carries its
                // own header), so `AudioJoiner` PCM-merges them.
                var parts: [Data] = []

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
                        let data = try await self.synthesize(client, text: chunk)
                        parts.append(data)
                        let url = dir.appendingPathComponent("chunk-\(i).\(fileExtension)")
                        try? data.write(to: url)
                        self.audio.enqueueStreaming(url: url)
                    }
                    self.status = "Playing"
                } else {
                    // Synthesize every chunk so the player can scrub/seek across
                    // the whole narration once joined.
                    for chunk in chunks {
                        parts.append(try await self.synthesize(client, text: chunk))
                    }
                }

                let combined = AudioJoiner.join(parts, fileExtension: fileExtension)

                // gpt-4o-mini-tts bills by audio (not characters), so estimate it
                // from the finished duration now that we have it. Character-billed
                // models (ElevenLabs, tts-1*) keep their pre-synthesis estimate.
                var finalCost = cost
                if engine == .openAI, modelId == "gpt-4o-mini-tts" {
                    let minutes = ((try? AVAudioPlayer(data: combined))?.duration ?? 0) / 60.0
                    finalCost = minutes * OpenAIClient.pricePerMinute
                }

                // Optionally shrink uncompressed WAV output to AAC m4a for storage.
                var audioData = combined
                var storedExtension = fileExtension
                if self.compressAudio, fileExtension == "wav",
                   let compressed = await AudioCompressor.aacM4A(from: combined) {
                    audioData = compressed
                    storedExtension = "m4a"
                }

                let record = try self.history.save(audio: audioData,
                                                   text: spoken,
                                                   engine: engine.engineName,
                                                   voiceId: voiceId,
                                                   voiceName: voiceName,
                                                   modelId: modelId,
                                                   credits: credits,
                                                   estimatedCost: finalCost,
                                                   fileExtension: storedExtension)
                self.history.prune(maxItems: self.historyLimit)
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

    /// Best installed Apple voice for the detected language `base` ("de"), or nil
    /// to keep the current selection (already matching, unsupported, or no auto).
    private func appleVoiceMatching(_ base: String?) -> String? {
        guard let base else { return nil }
        let voices = AppleTTSClient.installedVoices()
        // Keep the current voice if it already speaks the language.
        if let current = voices.first(where: { $0.id == appleVoice }),
           current.language.lowercased().hasPrefix(base.lowercased()) {
            return appleVoice
        }
        let matches = voices.filter { $0.language.lowercased().hasPrefix(base.lowercased()) }
        return (matches.first { $0.premium } ?? matches.first)?.id
    }

    /// Chatterbox language code for the detected `base`, or nil to keep current.
    private func chatterboxLanguageMatching(_ base: String?) -> String? {
        guard let base else { return nil }
        return ChatterboxClient.defaultVoices.contains(base) ? base : nil
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
