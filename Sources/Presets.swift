import SwiftUI

/// A saved snapshot of the engine, voice, model, and sliders, so the user can
/// switch between configured "looks" (e.g. "Audiobook", "Quick notes") in one
/// click. Captures every provider's settings so applying it restores fully.
struct VoicePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var provider: String              // TTSProviderKind rawValue

    // ElevenLabs
    var voiceId: String
    var modelId: String
    var stability: Double
    var similarityBoost: Double
    var speed: Double

    // OpenAI
    var openAIVoice: String
    var openAIModel: String

    // Local
    var kokoroVoice: String
    var appleVoice: String
    var chatterboxLanguage: String
    var chatterboxExaggeration: Double
    var chatterboxCfgWeight: Double

    /// Friendly one-line summary for the row subtitle.
    var summary: String {
        let engine = TTSProviderKind(rawValue: provider)?.label ?? provider
        let voice: String
        switch TTSProviderKind(rawValue: provider) {
        case .appleTTS:   voice = AppleTTSClient.displayName(for: appleVoice)
        case .elevenLabs: voice = voiceId
        case .openAI:     voice = openAIVoice
        case .kokoro:     voice = kokoroVoice
        case .chatterbox: voice = ChatterboxClient.languageName(chatterboxLanguage)
        case .none:       voice = ""
        }
        return voice.isEmpty ? engine : "\(engine) · \(voice)"
    }
}

/// The "Presets" section in Settings → Models.
struct PresetsSection: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section("Presets") {
            if state.presets.isEmpty {
                Text("No presets yet. Configure an engine and voice below, then save "
                     + "it here to switch back with one click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.presets) { preset in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                            Text(preset.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") {
                            withAnimation(.snappy) { state.applyPreset(preset) }
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            withAnimation(.snappy) { state.deletePreset(preset) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete preset")
                    }
                }
            }

            HStack {
                TextField("New preset name", text: $newName)
                    .onSubmit(save)
                Button("Save current", action: save)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        state.saveCurrentAsPreset(named: trimmedName)
        newName = ""
    }
}
