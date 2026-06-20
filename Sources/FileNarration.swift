import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Extracts plain text from documents the user wants narrated.
enum FileTextExtractor {
    /// Content types the open panel accepts.
    static let allowedTypes: [UTType] = [.pdf, .plainText, .rtf, .text, UTType("net.daringfireball.markdown")].compactMap { $0 }

    /// Returns the text of `url`, or nil if it can't be read.
    static func extract(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(url: url)?.string
        case "rtf", "rtfd":
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        default:
            // txt, md, and other UTF-8/plain files.
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
            return try? String(contentsOf: url)
        }
    }
}

/// One item waiting in the reading queue.
struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var text: String
}
