import Foundation
import AppKit

/// Fetches a web page and pulls out its readable text so a URL can be narrated
/// like an article. Best-effort: it prefers the page's `<article>`/`<main>`
/// region, drops scripts/nav/footers, and renders the remaining HTML (entities
/// and all) to plain text via `NSAttributedString`.
enum ArticleExtractor {
    enum ExtractError: LocalizedError {
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Couldn't load the page (HTTP \(code))."
            case .empty:          return "No readable text found on that page."
            }
        }
    }

    @MainActor
    static func fetch(_ url: URL) async throws -> (title: String, text: String) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) Narrateify", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExtractError.http(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ExtractError.empty
        }

        let title = firstMatch("<title[^>]*>([\\s\\S]*?)</title>", in: html)
            .map(htmlToText) ?? (url.host ?? "Article")
        let fragment = mainContent(of: html) ?? html
        let text = htmlToText(fragment)
        guard !text.isEmpty else { throw ExtractError.empty }
        return (title.trimmingCharacters(in: .whitespacesAndNewlines), text)
    }

    // MARK: HTML helpers

    /// The most article-like region of the page, if one is identifiable.
    private static func mainContent(of html: String) -> String? {
        for tag in ["article", "main"] {
            if let m = firstMatch("<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>", in: html) { return m }
        }
        return firstMatch("<body[^>]*>([\\s\\S]*?)</body>", in: html)
    }

    /// Strips boilerplate elements, then renders the HTML to plain text.
    private static func htmlToText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "nav", "header", "footer", "aside", "form"] {
            s = remove("<\(tag)[\\s\\S]*?</\(tag)>", from: s)
        }
        if let data = s.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: crude tag strip if the HTML importer refuses the fragment.
        return remove("<[^>]+>", from: s)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func remove(_ pattern: String, from text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return re.stringByReplacingMatches(in: text,
                                           range: NSRange(text.startIndex..., in: text),
                                           withTemplate: " ")
    }
}
