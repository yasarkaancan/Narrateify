import CoreGraphics
import Foundation

/// Reconstructs natural reading order from Vision OCR results. Vision returns one
/// observation per detected line with a normalized bounding box (origin bottom-
/// left). Naively joining lines top-to-bottom scrambles multi-column papers, so
/// this detects columns and emits header → left column → right column → footer.
/// Pure and geometry-only, so it's unit-testable with synthetic boxes.
enum OCRLayout {
    struct Line {
        let text: String
        let box: CGRect
        let confidence: Float
    }

    /// Ordered, newline-joined text. Drops low-confidence specks and pure
    /// page/line-number lines (margin noise in papers and preprints).
    static func orderedText(from lines: [Line], minConfidence: Float = 0.3) -> String {
        let kept = lines.filter {
            $0.confidence >= minConfidence
            && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isMarginNumber($0.text)
        }
        guard !kept.isEmpty else { return "" }

        let ordered: [Line]
        if let boundary = columnBoundary(kept) {
            // Lines spanning the gutter (titles, abstract headings, full-width
            // rules) are handled separately from the two body columns.
            let full = kept.filter { $0.box.width > 0.55 }
            let body = kept.filter { $0.box.width <= 0.55 }
            let left = body.filter { $0.box.midX < boundary }.sorted { $0.box.maxY > $1.box.maxY }
            let right = body.filter { $0.box.midX >= boundary }.sorted { $0.box.maxY > $1.box.maxY }
            let columnsTop = max(left.first?.box.maxY ?? 0, right.first?.box.maxY ?? 0)
            let header = full.filter { $0.box.maxY >= columnsTop }.sorted { $0.box.maxY > $1.box.maxY }
            let footer = full.filter { $0.box.maxY < columnsTop }.sorted { $0.box.maxY > $1.box.maxY }
            ordered = header + left + right + footer
        } else {
            ordered = kept.sorted { $0.box.maxY > $1.box.maxY }   // single column, top → bottom
        }
        return ordered.map { $0.text }.joined(separator: "\n")
    }

    /// The normalized x of the gutter if the page is two-column, else nil.
    /// Finds the largest gap between line mid-points and requires a clear,
    /// roughly-centered split with both sides populated.
    static func columnBoundary(_ lines: [Line]) -> CGFloat? {
        let mids = lines.filter { $0.box.width <= 0.55 }.map { $0.box.midX }.sorted()
        guard mids.count >= 6 else { return nil }

        var bestGap: CGFloat = 0
        var boundary: CGFloat = 0.5
        for i in 1..<mids.count {
            let gap = mids[i] - mids[i - 1]
            if gap > bestGap { bestGap = gap; boundary = (mids[i] + mids[i - 1]) / 2 }
        }
        let leftCount = mids.filter { $0 < boundary }.count
        let rightCount = mids.count - leftCount
        guard bestGap > 0.18, leftCount >= 3, rightCount >= 3,
              boundary > 0.3, boundary < 0.7 else { return nil }
        return boundary
    }

    /// A line that's only a number — almost always a page or margin line number.
    private static func isMarginNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^\\d{1,4}$", options: .regularExpression) != nil
    }
}
