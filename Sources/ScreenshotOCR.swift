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
            // Join the best candidate from each detected line.
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            completion(text.isEmpty ? nil : text)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
