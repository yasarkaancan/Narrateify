import Foundation
import NaturalLanguage

/// Smaller opening followed by natural sentence groups, for local Kokoro only.
enum BufferedTextChunker {
    static func chunk(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        if sentences.isEmpty { sentences = [text] }
        var result: [String] = []
        var current = ""
        for sentence in sentences {
            let clean = sentence.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !clean.isEmpty else { continue }
            let limit = result.isEmpty ? 350 : 650
            if !current.isEmpty && current.count + clean.count + 1 > limit {
                result.append(current)
                current = ""
            }
            for word in clean.split(separator: " ") {
                let cap = result.isEmpty ? 350 : 650
                if !current.isEmpty && current.count + word.count + 1 > cap {
                    result.append(current)
                    current = ""
                }
                var rest = String(word)
                // Bound pathological unbroken strings without losing characters.
                while rest.count > (result.isEmpty ? 350 : 650) {
                    let count = result.isEmpty ? 350 : 650
                    result.append(String(rest.prefix(count)))
                    rest = String(rest.dropFirst(count))
                }
                current += (current.isEmpty ? "" : " ") + rest
            }
            if current.count >= (result.isEmpty ? 220 : 450) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
