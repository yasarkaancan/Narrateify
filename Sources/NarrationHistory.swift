import Foundation
import AVFoundation
import SwiftUI

/// One stored narration: the saved audio file plus its metadata.
struct NarrationRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let text: String
    let characterCount: Int
    let credits: Double          // ElevenLabs credits (chars × model multiplier)
    let estimatedCost: Double    // credits ÷ 1000 × user's price-per-1k
    let duration: TimeInterval
    let fileName: String         // relative to the history directory
    let voiceId: String
    let voiceName: String
    let modelId: String
    var engine: String?          // e.g. "ElevenLabs" or "Kokoro (local)"
    var groupId: UUID?           // which group it's filed under (nil = ungrouped)

    /// Short single-line preview for list rows.
    var preview: String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
    }
}

/// A user-defined color for a narration group. Stored as a stable string so it
/// survives encoding; maps to a SwiftUI `Color` for display.
enum GroupColor: String, Codable, CaseIterable, Identifiable {
    case blue, green, orange, red, purple, pink, teal, gray

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .pink:   return .pink
        case .teal:   return .teal
        case .gray:   return .gray
        }
    }
}

/// A named, colored folder that narrations can be filed under.
struct NarrationGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var color: GroupColor
    var createdAt: Date
    var sortIndex: Int
}

/// ElevenLabs credit/cost estimation. The API doesn't return a dollar cost
/// (it depends on your plan), so we estimate from character count and a
/// user-supplied price per 1,000 credits.
enum Pricing {
    static func credits(characters: Int, modelId: String) -> Double {
        // Flash/Turbo models bill at half a credit per character.
        let discounted = modelId.contains("flash") || modelId.contains("turbo")
        return Double(characters) * (discounted ? 0.5 : 1.0)
    }

    static func cost(credits: Double, pricePerThousand: Double) -> Double {
        credits / 1000.0 * pricePerThousand
    }
}

/// Persists narration audio files + a JSON index in Application Support.
@MainActor
final class NarrationHistory: ObservableObject {
    @Published private(set) var records: [NarrationRecord] = []
    @Published private(set) var groups: [NarrationGroup] = []

    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var groupsURL: URL { directory.appendingPathComponent("groups.json") }

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Narrateify/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        load()
        loadGroups()
    }

    // MARK: Groups

    /// Creates a new group and returns it. New groups sort to the end.
    @discardableResult
    func addGroup(name: String = "New Group", color: GroupColor = .blue) -> NarrationGroup {
        let next = (groups.map(\.sortIndex).max() ?? -1) + 1
        let group = NarrationGroup(id: UUID(), name: name, color: color,
                                   createdAt: Date(), sortIndex: next)
        groups.append(group)
        persistGroups()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persistGroups()
    }

    func recolorGroup(_ id: UUID, to color: GroupColor) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].color = color
        persistGroups()
    }

    /// Removes a group and un-files any narrations it contained.
    func deleteGroup(_ id: UUID) {
        for i in records.indices where records[i].groupId == id {
            records[i].groupId = nil
        }
        groups.removeAll { $0.id == id }
        persistGroups()
        persist()
    }

    /// Files a narration under a group (or `nil` to remove it from any group).
    func assign(_ record: NarrationRecord, to groupId: UUID?) {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[i].groupId = groupId
        persist()
    }

    func fileURL(for record: NarrationRecord) -> URL {
        directory.appendingPathComponent(record.fileName)
    }

    /// Writes the audio to disk and prepends a record. Returns the new record.
    /// `credits`/`estimatedCost` are supplied by the caller (0 for local engines).
    @discardableResult
    func save(audio: Data,
              text: String,
              engine: String,
              voiceId: String,
              voiceName: String,
              modelId: String,
              credits: Double,
              estimatedCost: Double,
              fileExtension: String) throws -> NarrationRecord {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        try audio.write(to: url)

        let duration = (try? AVAudioPlayer(data: audio))?.duration ?? 0

        let record = NarrationRecord(
            id: id,
            date: Date(),
            text: text,
            characterCount: text.count,
            credits: credits,
            estimatedCost: estimatedCost,
            duration: duration,
            fileName: fileName,
            voiceId: voiceId,
            voiceName: voiceName,
            modelId: modelId,
            engine: engine
        )
        records.insert(record, at: 0)
        persist()
        return record
    }

    func delete(_ record: NarrationRecord) {
        try? FileManager.default.removeItem(at: fileURL(for: record))
        records.removeAll { $0.id == record.id }
        persist()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([NarrationRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL)
    }

    private func loadGroups() {
        guard let data = try? Data(contentsOf: groupsURL),
              let decoded = try? JSONDecoder().decode([NarrationGroup].self, from: data)
        else { return }
        groups = decoded
    }

    private func persistGroups() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: groupsURL)
    }
}

/// Formats a duration as `m:ss`.
func formatDuration(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let total = Int(t.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
