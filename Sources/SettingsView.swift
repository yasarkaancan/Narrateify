import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            ModelsView()
                .tabItem { Label("Models", systemImage: "waveform") }
            GeneralView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 540, height: 540)
        .onAppear {
            // Keep the "On disk" figures current whenever Settings opens.
            state.kokoro.refreshDiskUsage()
            state.chatterbox.refreshDiskUsage()
        }
    }
}

// MARK: - Models (everything TTS: provider selection + per-engine config)

struct ModelsView: View {
    @EnvironmentObject var state: AppState

    private let models: [(id: String, label: String)] = [
        ("eleven_multilingual_v2", "Multilingual v2 — best quality"),
        ("eleven_flash_v2_5",      "Flash v2.5 — lowest latency"),
        ("eleven_v3",              "v3 — most expressive")
    ]

    var body: some View {
        Form {
            Section("Provider") {
                Picker("TTS engine", selection: $state.provider) {
                    ForEach(TTSProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Text(providerBlurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch state.provider {
            case .elevenLabs:
                elevenLabsSection
                Section("Billing estimate") {
                    HStack {
                        Text("Price per 1,000 credits")
                        Spacer()
                        Text("$")
                        TextField("", value: $state.pricePerThousand, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Used to estimate the cost shown in History. ElevenLabs bills "
                         + "per credit (1 per character; Flash/Turbo at 0.5). Set this to "
                         + "your plan's effective rate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .openAI:
                openAISection
            case .kokoro:
                kokoroSection
            case .chatterbox:
                chatterboxSection
            }

            Section("Voice settings") {
                switch state.provider {
                case .elevenLabs:
                    slider("Speed", value: $state.speed, range: 0.7...1.2, suffix: "×")
                    slider("Stability", value: $state.stability, range: 0...1)
                    slider("Similarity", value: $state.similarityBoost, range: 0...1)
                case .openAI, .kokoro:
                    slider("Speed", value: $state.speed, range: 0.7...1.2, suffix: "×")
                case .chatterbox:
                    slider("Exaggeration", value: $state.chatterboxExaggeration, range: 0...1)
                    slider("CFG / pace", value: $state.chatterboxCfgWeight, range: 0...1)
                    Text("Higher exaggeration = more expressive; lower CFG slows pacing. "
                         + "0.5 / 0.5 is a balanced default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var providerBlurb: String {
        switch state.provider {
        case .elevenLabs:
            return "Cloud synthesis via the ElevenLabs API. Requires an API key."
        case .openAI:
            return "Cloud synthesis via OpenAI's audio API. Requires an API key."
        case .kokoro:
            return "Runs the open-source Kokoro-82M model locally — free and offline."
        case .chatterbox:
            return "Runs Resemble AI's open-source Chatterbox model locally — "
                 + "free, offline, and multilingual (23 languages)."
        }
    }

    // MARK: ElevenLabs

    private var elevenLabsSection: some View {
        Section("ElevenLabs") {
            SecureField("API Key", text: $state.apiKey)

            // Pick from fetched voices once loaded; otherwise enter an ID.
            if state.voices.isEmpty {
                TextField("Voice ID", text: $state.voiceId)
            } else {
                Picker("Voice", selection: $state.voiceId) {
                    ForEach(state.voices) { voice in
                        Text(voice.name).tag(voice.voiceId)
                    }
                }
            }

            HStack {
                Button("Load voices from ElevenLabs") { state.refreshVoices() }
                if !state.voicesStatus.isEmpty {
                    Text(state.voicesStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Model", selection: $state.modelId) {
                ForEach(models, id: \.id) { Text($0.label).tag($0.id) }
            }

            infoLink(.elevenLabs, "About ElevenLabs")
        }
    }

    // MARK: OpenAI

    private let openAIModels = OpenAIClient.models

    private var openAISection: some View {
        Section("OpenAI") {
            SecureField("API Key", text: $state.openAIKey)

            Picker("Voice", selection: $state.openAIVoice) {
                ForEach(OpenAIClient.voices, id: \.self) { Text($0.capitalized).tag($0) }
            }

            Picker("Model", selection: $state.openAIModel) {
                ForEach(openAIModels, id: \.id) { Text($0.label).tag($0.id) }
            }

            HStack {
                Text("Estimated cost")
                Spacer()
                Text(String(format: "$%.3f / 1,000 characters",
                            OpenAIClient.pricePerThousand(model: state.openAIModel)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("Approximate — shown in History. Get a key from platform.openai.com.")
                .font(.caption)
                .foregroundStyle(.secondary)

            infoLink(.openAI, "About OpenAI text-to-speech")
        }
    }

    // MARK: Kokoro (local)

    private var kokoroSection: some View {
        Section("Kokoro (local)") {
            HStack {
                Text("Status")
                Spacer()
                Text(kokoroStatusText)
                    .foregroundStyle(kokoroStatusColor)
            }

            Picker("Voice", selection: $state.kokoroVoice) {
                ForEach(state.kokoroVoices, id: \.self) { Text($0).tag($0) }
            }

            HStack(spacing: 10) {
                switch state.kokoro.status {
                case .notInstalled:
                    Button("Install Kokoro") { state.kokoro.install() }
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("Installing…").foregroundStyle(.secondary)
                case .stopped, .failed:
                    Button("Start Server") { state.kokoro.start() }
                    if case .failed = state.kokoro.status {
                        Button("Reinstall") { state.kokoro.install() }
                    }
                case .starting:
                    ProgressView().controlSize(.small)
                    Text("Starting… (first run downloads the model)")
                        .foregroundStyle(.secondary)
                    Button("Stop") { state.kokoro.stop() }   // terminate mid-startup
                case .running:
                    Button("Stop Server") { state.kokoro.stop() }
                    Button("Refresh Voices") { state.refreshKokoroVoices() }
                }
                Spacer()
            }

            Text("\(KokoroServer.performanceNote) Free & offline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.kokoro.status == .notInstalled {
                LabeledContent("Download size", value: KokoroServer.estimatedDownload)
                Text("Creates a Python venv under ~/.narrateify/kokoro; all weights "
                     + "stay there so nothing else on your system is touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("On disk", value: state.kokoro.diskUsage > 0
                               ? LocalServerSupport.formatBytes(state.kokoro.diskUsage)
                               : "calculating…")
                Button("Uninstall Kokoro", role: .destructive) {
                    state.kokoro.uninstall()
                }
            }

            if !state.kokoro.log.isEmpty {
                DisclosureGroup("Log") {
                    ScrollView {
                        Text(state.kokoro.log)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 120)
                }
            }

            infoLink(.kokoro, "About Kokoro")
        }
    }

    private var kokoroStatusText: String {
        switch state.kokoro.status {
        case .notInstalled: return "Not installed"
        case .installing:   return "Installing…"
        case .stopped:      return "Installed · stopped"
        case .starting:     return "Starting…"
        case .running:      return "Running"
        case .failed(let m): return "Error: \(m)"
        }
    }

    private var kokoroStatusColor: Color {
        switch state.kokoro.status {
        case .running:   return .green
        case .failed:    return .red
        case .installing, .starting: return .orange
        default:         return .secondary
        }
    }

    // MARK: Chatterbox (local)

    private var chatterboxSection: some View {
        Section("Chatterbox (local)") {
            HStack {
                Text("Status")
                Spacer()
                Text(chatterboxStatusText)
                    .foregroundStyle(chatterboxStatusColor)
            }

            Picker("Language", selection: $state.chatterboxLanguage) {
                ForEach(state.chatterboxVoices, id: \.self) { code in
                    Text(ChatterboxClient.languageName(code)).tag(code)
                }
            }

            HStack(spacing: 10) {
                switch state.chatterbox.status {
                case .notInstalled:
                    Button("Install Chatterbox") { state.chatterbox.install() }
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("Installing…").foregroundStyle(.secondary)
                case .stopped, .failed:
                    Button("Start Server") { state.chatterbox.start() }
                    if case .failed = state.chatterbox.status {
                        Button("Reinstall") { state.chatterbox.install() }
                    }
                case .starting:
                    ProgressView().controlSize(.small)
                    Text("Starting… (first run downloads the model)")
                        .foregroundStyle(.secondary)
                    Button("Stop") { state.chatterbox.stop() }   // terminate mid-startup
                case .running:
                    Button("Stop Server") { state.chatterbox.stop() }
                    Button("Refresh Languages") { state.refreshChatterboxVoices() }
                }
                Spacer()
            }

            Text("\(ChatterboxServer.performanceNote) Free & offline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.chatterbox.status == .notInstalled {
                LabeledContent("Download size", value: ChatterboxServer.estimatedDownload)
                Text("Creates a Python venv under ~/.narrateify/chatterbox; all weights "
                     + "stay there so nothing else on your system is touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("On disk", value: state.chatterbox.diskUsage > 0
                               ? LocalServerSupport.formatBytes(state.chatterbox.diskUsage)
                               : "calculating…")
                Button("Uninstall Chatterbox", role: .destructive) {
                    state.chatterbox.uninstall()
                }
            }

            if !state.chatterbox.log.isEmpty {
                DisclosureGroup("Log") {
                    ScrollView {
                        Text(state.chatterbox.log)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 120)
                }
            }

            infoLink(.chatterbox, "About Chatterbox")
        }
    }

    /// A footer link to a provider's information page, shown at the bottom of
    /// that provider's own section.
    private func infoLink(_ kind: TTSProviderKind, _ title: String) -> some View {
        Link(destination: kind.infoURL) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "arrow.up.right.square")
            }
            .font(.caption)
        }
    }

    private var chatterboxStatusText: String {
        switch state.chatterbox.status {
        case .notInstalled: return "Not installed"
        case .installing:   return "Installing…"
        case .stopped:      return "Installed · stopped"
        case .starting:     return "Starting…"
        case .running:      return "Running"
        case .failed(let m): return "Error: \(m)"
        }
    }

    private var chatterboxStatusColor: Color {
        switch state.chatterbox.status {
        case .running:   return .green
        case .failed:    return .red
        case .installing, .starting: return .orange
        default:         return .secondary
        }
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue) + suffix)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - General (app behavior: overlay + shortcuts)

struct GeneralView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Narrateify at login", isOn: $state.launchAtLogin)
                Toggle("Auto-start last-used local model on launch",
                       isOn: $state.autoStartLocalServer)
                Text("When your most recent narration used a local model (Kokoro or "
                     + "Chatterbox) that's installed, its server starts automatically "
                     + "the next time you open Narrateify — so it's ready to narrate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Overlay") {
                Toggle("Show floating overlay", isOn: $state.overlayEnabled)
                Toggle("Keep player floating after conversion", isOn: $state.keepPlayerVisible)
                    .disabled(!state.overlayEnabled)
                HStack {
                    Text("Drag the overlay anywhere to reposition it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Position") { state.resetOverlayPosition() }
                }
            }

            Section("Shortcuts") {
                ShortcutsSettingsView()
            }

            Section("About & Updates") {
                LabeledContent("Version", value: state.updateChecker.currentVersion)

                HStack {
                    updateStatusView
                    Spacer()
                    Button("Check Now") {
                        Task { await state.updateChecker.check() }
                    }
                    .disabled(state.updateChecker.state == .checking)
                }

                Link(destination: UpdateChecker.releasesURL) {
                    Label("View releases on GitHub", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch state.updateChecker.state {
        case .idle:
            Text("Not checked yet").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .available(let version, let url):
            Link(destination: url) {
                Label("Update available: \(version)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
        case .failed(let message):
            Label("Check failed: \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }
}

// History lives in HistoryView.swift.
