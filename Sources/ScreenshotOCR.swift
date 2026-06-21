import AppKit
import Vision

/// Lets the user drag-select a screen region using macOS's native screenshot
/// crosshair (`screencapture -i`), then runs on-device OCR with the Vision
/// framework. No external OCR service required.
enum ScreenshotOCR {

    static func captureAndRecognize(completion: @escaping (String?) -> Void) {
        let tmpPath = NSTemporaryDirectory() + "narrator_\(UUID().uuidString).png"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive region selection   -x: no camera shutter sound
        task.arguments = ["-i", "-x", tmpPath]

        task.terminationHandler = { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? FileManager.default.removeItem(atPath: tmpPath) }

                guard FileManager.default.fileExists(atPath: tmpPath),
                      let image = NSImage(contentsOfFile: tmpPath),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    DispatchQueue.main.async { completion(nil) } // user pressed Esc
                    return
                }

                recognizeText(in: cgImage) { text in
                    DispatchQueue.main.async { completion(text) }
                }
            }
        }

        do {
            try task.run()
        } catch {
            completion(nil)
        }
    }

    private static func recognizeText(in cgImage: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            // Keep each line's geometry + confidence so we can reconstruct the
            // real reading order (columns, headers) instead of a naive top-down
            // join — critical for two-column scientific papers.
            let lines: [OCRLayout.Line] = observations.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return OCRLayout.Line(text: candidate.string,
                                      box: obs.boundingBox,
                                      confidence: candidate.confidence)
            }
            let text = OCRLayout.orderedText(from: lines)
            completion(text.isEmpty ? nil : text)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Let Vision pick the language and skip sub-pixel specks (figure noise).
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
