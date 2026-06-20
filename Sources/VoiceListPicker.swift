import SwiftUI

/// One selectable voice row.
struct VoiceRowItem: Identifiable, Equatable {
    let id: String         // the selection value (voice id / identifier)
    let title: String
    var subtitle: String?  // e.g. language
    var premium: Bool = false
}

/// A compact, scrollable voice list where each row is selectable and has a ▶
/// button to audition that voice without committing the selection. Used for the
/// Apple and ElevenLabs voice lists in Settings → Models.
struct VoiceListPicker: View {
    let items: [VoiceRowItem]
    @Binding var selection: String
    var previewDisabled: Bool = false
    let onPreview: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        Divider()
                    }
                }
            }
            .frame(height: 190)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }

    private func row(_ item: VoiceRowItem) -> some View {
        let selected = item.id == selection
        return HStack(spacing: 8) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                    if item.premium {
                        Text("✦").foregroundStyle(.orange).help("Premium / Enhanced voice")
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { onPreview(item.id) } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(previewDisabled)
            .help("Preview this voice")
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
        .onTapGesture { selection = item.id }
        .id(item.id)
    }
}
