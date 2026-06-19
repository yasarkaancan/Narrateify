import SwiftUI

// MARK: - Sorting

enum HistorySort: String, CaseIterable, Identifiable {
    case newest, oldest, name, model

    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: return "Date (newest)"
        case .oldest: return "Date (oldest)"
        case .name:   return "Name"
        case .model:  return "Model"
        }
    }
}

// MARK: - History tab

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    @AppStorage("historySort") private var sortRaw = HistorySort.newest.rawValue
    @AppStorage("historyFilterProvider") private var filterProvider = ""   // "" = all
    @AppStorage("historyFilterModel") private var filterModel = ""

    @State private var collapsedGroups: Set<UUID> = []
    @State private var ungroupedCollapsed = false
    @State private var editingGroup: NarrationGroup?

    private var history: NarrationHistory { state.history }
    private var sort: HistorySort { HistorySort(rawValue: sortRaw) ?? .newest }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if history.records.isEmpty {
                emptyState
            } else {
                listBody
            }
            Divider()
            footer
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorSheet(group: group) { name, color in
                history.renameGroup(group.id, to: name)
                history.recolorGroup(group.id, to: color)
                editingGroup = nil
            } onCancel: {
                editingGroup = nil
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(HistorySort.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Label("Sort: \(sort.label)", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Picker("Provider", selection: $filterProvider) {
                    Text("All providers").tag("")
                    ForEach(distinctProviders, id: \.self) { Text($0).tag($0) }
                }
                Picker("Model", selection: $filterModel) {
                    Text("All models").tag("")
                    ForEach(distinctModels, id: \.self) { Text($0).tag($0) }
                }
                if isFiltering {
                    Divider()
                    Button("Clear filters") {
                        withAnimation(.snappy) { filterProvider = ""; filterModel = "" }
                    }
                }
            } label: {
                Label(isFiltering ? "Filtered" : "Filter",
                      systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill"
                                               : "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button {
                withAnimation(.snappy) {
                    let g = history.addGroup()
                    collapsedGroups.remove(g.id)
                    editingGroup = g
                }
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }
        }
        .padding(10)
        .animation(.snappy, value: sortRaw)
    }

    // MARK: List

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sortedGroups) { group in
                    GroupCardView(group: group,
                                  records: records(in: group),
                                  collapsed: $collapsedGroups) {
                        editingGroup = group
                    }
                }
                ungroupedCard
            }
            .padding(10)
        }
        .animation(.snappy, value: history.records)
        .animation(.snappy, value: history.groups)
        .animation(.snappy, value: sortRaw)
        .animation(.snappy, value: filterProvider)
        .animation(.snappy, value: filterModel)
        .animation(.snappy, value: collapsedGroups)
        .animation(.snappy, value: ungroupedCollapsed)
    }

    @ViewBuilder private var ungroupedCard: some View {
        let recs = records(in: nil)
        if !recs.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) { ungroupedCollapsed.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(ungroupedCollapsed ? 0 : 90))
                        Image(systemName: "tray").foregroundStyle(.secondary)
                        Text("Ungrouped").font(.headline)
                        CountBadge(recs.count)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(Color.secondary.opacity(0.08))

                if !ungroupedCollapsed {
                    ForEach(recs) { record in
                        Divider()
                        HistoryRow(record: record)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No narrations yet.").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Stored in \(history.directory.path)")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Reveal Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([history.directory])
            }
        }
        .padding(8)
    }

    // MARK: Data helpers

    private var sortedGroups: [NarrationGroup] {
        history.groups.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func records(in group: NarrationGroup?) -> [NarrationRecord] {
        let gid = group?.id
        let filtered = history.records.filter { $0.groupId == gid && passesFilter($0) }
        return sortRecords(filtered)
    }

    private func sortRecords(_ recs: [NarrationRecord]) -> [NarrationRecord] {
        switch sort {
        case .newest: return recs.sorted { $0.date > $1.date }
        case .oldest: return recs.sorted { $0.date < $1.date }
        case .name:   return recs.sorted { $0.preview.localizedCaseInsensitiveCompare($1.preview) == .orderedAscending }
        case .model:  return recs.sorted { $0.modelId.localizedCaseInsensitiveCompare($1.modelId) == .orderedAscending }
        }
    }

    private func passesFilter(_ r: NarrationRecord) -> Bool {
        (filterProvider.isEmpty || r.engine == filterProvider) &&
        (filterModel.isEmpty || r.modelId == filterModel)
    }

    private var distinctProviders: [String] {
        Array(Set(history.records.compactMap { $0.engine })).sorted()
    }
    private var distinctModels: [String] {
        Array(Set(history.records.map { $0.modelId })).sorted()
    }
    private var isFiltering: Bool { !filterProvider.isEmpty || !filterModel.isEmpty }
}

// MARK: - Group card

private struct GroupCardView: View {
    @EnvironmentObject var state: AppState
    let group: NarrationGroup
    let records: [NarrationRecord]
    @Binding var collapsed: Set<UUID>
    let onEdit: () -> Void

    private var isExpanded: Bool { !collapsed.contains(group.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded { rows }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(group.color.color.opacity(0.40), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Circle().fill(group.color.color).frame(width: 11, height: 11)
                    Text(group.name).font(.headline).foregroundStyle(.primary)
                    CountBadge(records.count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button { onEdit() } label: { Label("Rename & Color…", systemImage: "pencil") }
                Menu {
                    ForEach(GroupColor.allCases) { c in
                        Button {
                            withAnimation(.snappy) { state.history.recolorGroup(group.id, to: c) }
                        } label: {
                            Label(c.label, systemImage: c == group.color ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                } label: { Label("Color", systemImage: "paintpalette") }
                Divider()
                Button(role: .destructive) {
                    withAnimation(.snappy) { state.history.deleteGroup(group.id) }
                } label: { Label("Delete Group", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(10)
        .background(group.color.color.opacity(0.13))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                Text("Empty — use a narration's Move menu to file it here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                ForEach(records) { record in
                    Divider()
                    HistoryRow(record: record)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggle() {
        if collapsed.contains(group.id) { collapsed.remove(group.id) }
        else { collapsed.insert(group.id) }
    }
}

private struct CountBadge: View {
    let count: Int
    init(_ count: Int) { self.count = count }
    var body: some View {
        Text("\(count)")
            .font(.caption2).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .contentTransition(.numericText())
    }
}

// MARK: - Row

struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let record: NarrationRecord

    private var history: NarrationHistory { state.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.preview.isEmpty ? "(empty)" : record.preview)
                .lineLimit(2)

            HStack(spacing: 10) {
                label("clock", formatDuration(record.duration))
                label("textformat.123", "\(record.characterCount) chars")
                if record.estimatedCost > 0 {
                    if record.credits > 0 {
                        label("creditcard", "\(Int(record.credits)) cr")
                    }
                    label("dollarsign.circle", String(format: "$%.4f", record.estimatedCost))
                } else {
                    label("gift", "free")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let engine = record.engine { Text(engine) }
                Text(record.voiceName)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button { state.play(record) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: record)])
                } label: {
                    Label("Show File", systemImage: "folder")
                }
                ShareLink(item: history.fileURL(for: record),
                          subject: Text("Narrateify recording"),
                          preview: SharePreview(record.preview.isEmpty ? "Narration"
                                                                       : record.preview)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                moveMenu
                Button(role: .destructive) {
                    withAnimation(.snappy) { state.delete(record) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moveMenu: some View {
        Menu {
            if record.groupId != nil {
                Button {
                    withAnimation(.snappy) { history.assign(record, to: nil) }
                } label: { Label("Remove from group", systemImage: "tray.and.arrow.up") }
                Divider()
            }
            ForEach(history.groups.sorted { $0.sortIndex < $1.sortIndex }) { g in
                Button {
                    withAnimation(.snappy) { history.assign(record, to: g.id) }
                } label: {
                    Label(g.name, systemImage: g.id == record.groupId ? "checkmark" : "folder")
                }
            }
            Divider()
            Button {
                withAnimation(.snappy) {
                    let g = history.addGroup()
                    history.assign(record, to: g.id)
                }
            } label: { Label("New Group…", systemImage: "folder.badge.plus") }
        } label: {
            Label("Move", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func label(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
    }
}

// MARK: - Group editor sheet

private struct GroupEditorSheet: View {
    let group: NarrationGroup
    let onSave: (String, GroupColor) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: GroupColor

    init(group: NarrationGroup,
         onSave: @escaping (String, GroupColor) -> Void,
         onCancel: @escaping () -> Void) {
        self.group = group
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: group.name)
        _color = State(initialValue: group.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Group").font(.headline)

            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(GroupColor.allCases) { c in
                        Circle()
                            .fill(c.color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: c == color ? 2 : 0))
                            .overlay(Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .opacity(c == color ? 1 : 0))
                            .scaleEffect(c == color ? 1.15 : 1)
                            .onTapGesture { withAnimation(.snappy) { color = c } }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, color)
    }
}
