import SwiftUI
import AppKit
import AVFoundation

/// Reads text aloud with Apple's engine while highlighting the current word —
/// a "karaoke" reader. This uses live `AVSpeechSynthesizer.speak` (not the
/// capture path) because only live speech emits `willSpeakRange` word ranges, so
/// it's intentionally separate from the save/scrub/history pipeline.
@MainActor
final class ReaderController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = ReaderController()

    private let synth = AVSpeechSynthesizer()

    @Published var text = ""
    @Published var highlight: NSRange?
    @Published private(set) var isPlaying = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func read(_ text: String, voiceIdentifier: String, speed: Double) {
        synth.stopSpeaking(at: .immediate)
        self.text = text
        self.highlight = nil

        let u = AVSpeechUtterance(string: text)
        if let v = AVSpeechSynthesisVoice(identifier: voiceIdentifier) { u.voice = v }
        let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        u.rate = min(max(scaled, AVSpeechUtteranceMinimumSpeechRate),
                     AVSpeechUtteranceMaximumSpeechRate)
        synth.speak(u)
        isPlaying = true
    }

    func toggle() {
        if synth.isPaused {
            synth.continueSpeaking()
            isPlaying = true
        } else if synth.isSpeaking {
            synth.pauseSpeaking(at: .word)
            isPlaying = false
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isPlaying = false
        highlight = nil
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.highlight = characterRange }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.highlight = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.highlight = nil
        }
    }
}

/// Window that hosts the live reader.
@MainActor
final class ReaderWindow: NSObject, NSWindowDelegate {
    static let shared = ReaderWindow()
    private var window: NSWindow?

    func show(text: String, voiceIdentifier: String, speed: Double) {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(rootView: ReaderView(reader: ReaderController.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Read Aloud"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 460, height: 420))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        ReaderController.shared.read(text, voiceIdentifier: voiceIdentifier, speed: speed)
    }

    func windowWillClose(_ notification: Notification) {
        ReaderController.shared.stop()
    }
}

/// Renders the text with the spoken word highlighted, plus transport controls.
private struct ReaderView: View {
    @ObservedObject var reader: ReaderController

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(attributed)
                    .font(.title3)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }

            Divider()

            HStack(spacing: 20) {
                Button { reader.toggle() } label: {
                    Image(systemName: reader.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                Button { reader.stop() } label: {
                    Image(systemName: "stop.fill")
                }
                Spacer()
                Text("Highlighting follows the Apple voice as it reads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .imageScale(.large)
            .buttonStyle(.borderless)
            .padding(14)
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    /// Builds the displayed string with the current word emphasized.
    private var attributed: AttributedString {
        var attr = AttributedString(reader.text)
        guard let hr = reader.highlight,
              let swiftRange = Range(hr, in: reader.text),
              let lo = AttributedString.Index(swiftRange.lowerBound, within: attr),
              let hi = AttributedString.Index(swiftRange.upperBound, within: attr)
        else { return attr }
        attr[lo..<hi].backgroundColor = .accentColor.opacity(0.35)
        attr[lo..<hi].foregroundColor = .primary
        attr[lo..<hi].font = .title3.bold()
        return attr
    }
}
