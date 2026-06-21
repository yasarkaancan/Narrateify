import SwiftUI
import AppKit
import AVFoundation
import NaturalLanguage

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

/// Highlight palette for the live reader.
enum ReaderHighlightColor: String, CaseIterable, Identifiable {
    case accent, yellow, green, blue, pink, orange

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .accent: return .accentColor
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .pink:   return .pink
        case .orange: return .orange
        }
    }
}

/// Renders the text with the spoken word (or sentence) highlighted, plus
/// transport controls.
private struct ReaderView: View {
    @ObservedObject var reader: ReaderController
    @AppStorage("readerSentenceHighlight") private var sentenceMode = false
    @AppStorage("readerHighlightColor") private var colorRaw = ReaderHighlightColor.accent.rawValue

    private var tint: Color {
        (ReaderHighlightColor(rawValue: colorRaw) ?? .accent).color
    }

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

            HStack(spacing: 16) {
                Button { reader.toggle() } label: {
                    Image(systemName: reader.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                Button { reader.stop() } label: {
                    Image(systemName: "stop.fill")
                }

                Picker("", selection: $sentenceMode) {
                    Text("Word").tag(false)
                    Text("Sentence").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Highlight the current word or the whole sentence")

                Menu {
                    ForEach(ReaderHighlightColor.allCases) { c in
                        Button {
                            colorRaw = c.rawValue
                        } label: {
                            Label(c.label, systemImage: colorRaw == c.rawValue ? "checkmark" : "circle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Highlight color")

                Spacer()
            }
            .imageScale(.large)
            .buttonStyle(.borderless)
            .padding(14)
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    /// Builds the displayed string with the current word — or its whole
    /// sentence — emphasized.
    private var attributed: AttributedString {
        var attr = AttributedString(reader.text)
        guard let word = reader.highlight else { return attr }
        let target = sentenceMode ? sentenceRange(containing: word) : word
        guard let swiftRange = Range(target, in: reader.text),
              let lo = AttributedString.Index(swiftRange.lowerBound, within: attr),
              let hi = AttributedString.Index(swiftRange.upperBound, within: attr)
        else { return attr }
        attr[lo..<hi].backgroundColor = tint.opacity(0.35)
        attr[lo..<hi].foregroundColor = .primary
        attr[lo..<hi].font = .title3.bold()
        return attr
    }

    /// The sentence range that contains the given word range.
    private func sentenceRange(containing word: NSRange) -> NSRange {
        let text = reader.text
        guard let wordRange = Range(word, in: text) else { return word }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result = word
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if range.contains(wordRange.lowerBound) || range.lowerBound == wordRange.lowerBound {
                result = NSRange(range, in: text)
                return false
            }
            return true
        }
        return result
    }
}
