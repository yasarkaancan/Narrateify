import Foundation

/// A language Narrateify can translate into before synthesis. Codes are the
/// 2-letter base used by the voice-matching logic (Apple / Chatterbox), so an
/// auto-selected voice can follow the translation target.
enum TranslationLanguage: String, CaseIterable, Identifiable {
    case english = "en", spanish = "es", french = "fr", german = "de"
    case italian = "it", portuguese = "pt", dutch = "nl", russian = "ru"
    case turkish = "tr", arabic = "ar", hindi = "hi", japanese = "ja"
    case korean = "ko", chinese = "zh", polish = "pl", swedish = "sv"
    case norwegian = "no", danish = "da", finnish = "fi", greek = "el"
    case hebrew = "he", ukrainian = "uk"

    var id: String { rawValue }

    /// Name shown in the Settings picker.
    var label: String { englishName }

    /// Full English name used in the translation prompt (unambiguous for the model).
    var englishName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch:      return "Dutch"
        case .russian:    return "Russian"
        case .turkish:    return "Turkish"
        case .arabic:     return "Arabic"
        case .hindi:      return "Hindi"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .chinese:    return "Simplified Chinese"
        case .polish:     return "Polish"
        case .swedish:    return "Swedish"
        case .norwegian:  return "Norwegian"
        case .danish:     return "Danish"
        case .finnish:    return "Finnish"
        case .greek:      return "Greek"
        case .hebrew:     return "Hebrew"
        case .ukrainian:  return "Ukrainian"
        }
    }
}

/// Translates text into a target language before it reaches the TTS engine,
/// reusing the user's existing OpenAI key (kept in the Keychain). Used as an
/// optional pre-synthesis stage so narration can be heard in another language
/// than the source — for both selected text and screenshots.
struct Translator {
    let apiKey: String
    let target: TranslationLanguage
    /// The chat model used for translation (cheap + multilingual).
    var model: String = "gpt-4o-mini"

    enum TranslateError: LocalizedError {
        case missingKey
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your OpenAI API key in Settings → Models to use translation."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " – \(body.prefix(200))"
                return "Translation error \(code)\(detail)"
            case .empty:
                return "The translator returned no text."
            }
        }
    }

    /// System instruction for a faithful, output-only translation.
    static func systemPrompt(targetLanguageName name: String) -> String {
        "You are a professional translator. Translate the user's text into \(name). "
        + "Preserve meaning, tone, names, and paragraph breaks. "
        + "Output ONLY the translated text — no preamble, quotes, notes, or explanations. "
        + "If the text is already in \(name), return it unchanged."
    }

    /// Translate possibly-long text by splitting it on sentence boundaries so
    /// each request stays well within output limits, then rejoining. Returns the
    /// original text unchanged if it's blank.
    func translate(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard !apiKey.isEmpty else { throw TranslateError.missingKey }

        let parts = TextChunker.chunk(trimmed, maxLength: 3000)
        var out: [String] = []
        out.reserveCapacity(parts.count)
        for part in parts {
            out.append(try await translateOne(part))
        }
        return out.joined(separator: "\n")
    }

    /// One chat-completions round-trip for a single chunk.
    private func translateOne(_ text: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(targetLanguageName: target.englishName)],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslateError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslateError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw TranslateError.empty }
        return content
    }
}
