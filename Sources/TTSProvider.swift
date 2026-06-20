import Foundation

/// A text-to-speech backend. Implementations return finished audio bytes
/// (MP3 or WAV — both play via AVAudioPlayer) for a chunk of text.
protocol TTSProvider {
    func synthesize(text: String) async throws -> Data
}

/// Which engine to use. Cloud (ElevenLabs / OpenAI) or local (Kokoro / Chatterbox).
enum TTSProviderKind: String, CaseIterable, Identifiable {
    case appleTTS
    case elevenLabs
    case openAI
    case kokoro
    case chatterbox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleTTS:   return "Apple (built-in)"
        case .elevenLabs: return "ElevenLabs (cloud)"
        case .openAI:     return "OpenAI (cloud)"
        case .kokoro:     return "Kokoro (local)"
        case .chatterbox: return "Chatterbox (local)"
        }
    }

    /// Stored on each history record so the UI can show what produced it.
    var engineName: String {
        switch self {
        case .appleTTS:   return "Apple (built-in)"
        case .elevenLabs: return "ElevenLabs"
        case .openAI:     return "OpenAI"
        case .kokoro:     return "Kokoro (local)"
        case .chatterbox: return "Chatterbox (local)"
        }
    }

    /// Where to read more about the provider (shown as a link in its section).
    var infoURL: URL {
        switch self {
        case .appleTTS:   return URL(string: "https://support.apple.com/guide/mac-help/change-the-voice-your-mac-uses-mchlp2290/mac")!
        case .elevenLabs: return URL(string: "https://elevenlabs.io")!
        case .openAI:     return URL(string: "https://platform.openai.com/docs/guides/text-to-speech")!
        case .kokoro:     return URL(string: "https://github.com/hexgrad/kokoro")!
        case .chatterbox: return URL(string: "https://github.com/resemble-ai/chatterbox")!
        }
    }
}

// ElevenLabsClient already exposes `synthesize(text:)`.
extension ElevenLabsClient: TTSProvider {}

/// Cloud synthesis via OpenAI's `/v1/audio/speech` endpoint. Returns MP3 bytes.
struct OpenAIClient: TTSProvider {
    let apiKey: String
    let voice: String
    let model: String
    let speed: Double

    enum OpenAIError: LocalizedError {
        case missingKey
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Enter your OpenAI API key in Settings → Models."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " – \(body.prefix(200))"
                return "OpenAI error \(code)\(detail)"
            case .empty:
                return "OpenAI returned no audio."
            }
        }
    }

    func synthesize(text: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw OpenAIError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "mp3"
        ]
        // Only the `tts-1*` models accept a speed parameter.
        if model.hasPrefix("tts-") { body["speed"] = speed }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw OpenAIError.empty }
        return data
    }

    /// OpenAI's built-in voices.
    static let voices: [String] = [
        "alloy", "ash", "ballad", "coral", "echo",
        "fable", "onyx", "nova", "sage", "shimmer", "verse"
    ]

    static let models: [(id: String, label: String)] = [
        ("gpt-4o-mini-tts", "GPT-4o mini TTS — newest, steerable"),
        ("tts-1",           "TTS-1 — fast"),
        ("tts-1-hd",        "TTS-1 HD — higher quality")
    ]

    /// Approximate USD per 1,000 characters, for the History cost estimate.
    static func pricePerThousand(model: String) -> Double {
        switch model {
        case "tts-1-hd": return 0.030
        default:         return 0.015   // tts-1 and gpt-4o-mini-tts (approx.)
        }
    }
}

/// Talks to the local Kokoro server (see `KokoroServer`) over its
/// OpenAI-compatible `/v1/audio/speech` endpoint, returning WAV bytes.
struct KokoroClient: TTSProvider {
    let baseURL: URL
    let voice: String
    let speed: Double

    enum KokoroError: LocalizedError {
        case notRunning
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Kokoro server isn't running. Start it in Settings → Provider."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " – \(body.prefix(160))"
                return "Kokoro error \(code)\(detail)"
            case .empty:
                return "Kokoro returned no audio."
            }
        }
    }

    func synthesize(text: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": "kokoro",
            "input": text,
            "voice": voice,
            "speed": speed,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KokoroError.notRunning
        }
        guard let http = response as? HTTPURLResponse else { throw KokoroError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw KokoroError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw KokoroError.empty }
        return data
    }

    /// Fetches the server's voice list (falls back to a built-in list elsewhere).
    static func fetchVoices(baseURL: URL) async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1/audio/voices")
        let (data, _) = try await URLSession.shared.data(from: url)
        struct VoicesResponse: Codable { let voices: [String] }
        return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
    }

    /// A reasonable default set of v1.0 Kokoro voices for the picker.
    static let defaultVoices: [String] = [
        "af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_aoede",
        "am_adam", "am_michael", "am_fenrir", "am_puck",
        "bf_emma", "bf_isabella", "bm_george", "bm_lewis"
    ]
}

/// Talks to the local Chatterbox server (see `ChatterboxServer`) over the same
/// OpenAI-compatible `/v1/audio/speech` endpoint. Chatterbox is multilingual,
/// so "voice" is a `language_id`; `exaggeration` / `cfg_weight` tune delivery.
struct ChatterboxClient: TTSProvider {
    let baseURL: URL
    let language: String
    let exaggeration: Double
    let cfgWeight: Double

    enum ChatterboxError: LocalizedError {
        case notRunning
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Chatterbox server isn't running. Start it in Settings → Models."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " – \(body.prefix(160))"
                return "Chatterbox error \(code)\(detail)"
            case .empty:
                return "Chatterbox returned no audio."
            }
        }
    }

    func synthesize(text: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300   // model can be slow on CPU

        let body: [String: Any] = [
            "model": "chatterbox",
            "input": text,
            "voice": language,
            "exaggeration": exaggeration,
            "cfg_weight": cfgWeight,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ChatterboxError.notRunning
        }
        guard let http = response as? HTTPURLResponse else { throw ChatterboxError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw ChatterboxError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw ChatterboxError.empty }
        return data
    }

    /// Fetches the server's language list (falls back to a built-in list).
    static func fetchVoices(baseURL: URL) async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1/audio/voices")
        let (data, _) = try await URLSession.shared.data(from: url)
        struct VoicesResponse: Codable { let voices: [String] }
        return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
    }

    /// The 23 languages Chatterbox's multilingual model supports.
    static let defaultVoices: [String] = [
        "en", "ar", "da", "de", "el", "es", "fi", "fr", "he", "hi", "it",
        "ja", "ko", "ms", "nl", "no", "pl", "pt", "ru", "sv", "sw", "tr", "zh"
    ]

    /// Friendly label for a language code, for the picker.
    static func languageName(_ code: String) -> String {
        let names = [
            "en": "English", "ar": "Arabic", "da": "Danish", "de": "German",
            "el": "Greek", "es": "Spanish", "fi": "Finnish", "fr": "French",
            "he": "Hebrew", "hi": "Hindi", "it": "Italian", "ja": "Japanese",
            "ko": "Korean", "ms": "Malay", "nl": "Dutch", "no": "Norwegian",
            "pl": "Polish", "pt": "Portuguese", "ru": "Russian", "sv": "Swedish",
            "sw": "Swahili", "tr": "Turkish", "zh": "Chinese"
        ]
        if let name = names[code] { return "\(name) (\(code))" }
        return code
    }
}
