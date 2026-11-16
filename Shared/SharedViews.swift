import SwiftUI

/// Colored pill for the fits/tight/too-big badge.
struct BadgeView: View {
    var badge: Badge

    init(badge: Badge) { self.badge = badge }

    private var color: Color {
        switch badge {
        case .fits: .green
        case .tight: .orange
        case .tooBig: .red
        }
    }

    var body: some View {
        Text(badge.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityIdentifier(badge.accessibilityId)
    }
}

/// One model row in the library list.
struct ModelRowView: View {
    var info: ModelInfo

    init(info: ModelInfo) { self.info = info }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.body.weight(.medium))
                Text("\(info.kind.rawValue.uppercased()) · \(info.quantization) · \(info.tensorCount) tensors · \(formatBytes(info.fileSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BadgeView(badge: info.badge)
        }
    }
}

/// Row for a file whose header could not be parsed.
struct ModelErrorRowView: View {
    var name: String
    var message: String

    init(name: String, message: String) {
        self.name = name
        self.message = message
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            Text("Unreadable")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.red.opacity(0.15)).foregroundStyle(.red)
                .clipShape(Capsule())
                .accessibilityIdentifier("badge.unreadable")
        }
    }
}

/// Inspector detail for one model file: header facts, RAM badge, notes, tags.
struct ModelDetailView: View {
    var info: ModelInfo
    @ObservedObject var store: MetadataStore

    init(info: ModelInfo, store: MetadataStore) {
        self.info = info
        self.store = store
    }

    private var entry: ModelEntry { store.entry(for: info.path) }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("File") {
                    LabeledContent("Name", value: info.name)
                        .accessibilityIdentifier("detail.title")
                    LabeledContent("Format", value: info.kind.rawValue.uppercased())
                    LabeledContent("Size on disk", value: formatBytes(info.fileSize))
                        .accessibilityIdentifier("detail.size")
                    LabeledContent("Tensors", value: "\(info.tensorCount)")
                        .accessibilityIdentifier("detail.tensors")
                    LabeledContent("Quantization / dtype", value: info.quantization)
                        .accessibilityIdentifier("detail.quantization")
                }
                Section("Memory") {
                    LabeledContent("Estimated RAM need", value: formatBytes(info.estimatedRAMBytes))
                        .accessibilityIdentifier("detail.ram")
                    LabeledContent("Device RAM", value: formatBytes(ProcessInfo.processInfo.physicalMemory))
                        .accessibilityIdentifier("detail.deviceRAM")
                    HStack {
                        Text("Badge")
                        Spacer()
                        BadgeView(badge: info.badge)
                    }
                    .accessibilityIdentifier("detail.badgeRow")
                }
                if !info.metadata.isEmpty {
                    Section("Header metadata") {
                        ForEach(info.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key, value: value)
                                .accessibilityIdentifier("detail.meta.\(key)")
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes about this file", text: Binding(
                        get: { entry.notes },
                        set: { store.setEntry(ModelEntry(notes: $0, tags: entry.tags), for: info.path) }
                    ), axis: .vertical)
                    .accessibilityIdentifier("detail.notes")
                }
                .id("section.notes")
                Section("Tags") {
                    TextField("Comma-separated tags", text: Binding(
                        get: { entry.tags.joined(separator: ", ") },
                        set: { store.setEntry(ModelEntry(notes: entry.notes,
                                                         tags: $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }),
                                               for: info.path) }
                    ))
                    .accessibilityIdentifier("detail.tags")
                }
                Section("Tensors (header only)") {
                    ForEach(info.tensors.prefix(50)) { t in
                        HStack {
                            Text(t.name).lineLimit(1)
                            Spacer()
                            Text("\(t.dtype) · \(formatBytes(t.byteCount))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(info.name)
            .task {
                if LaunchArguments.scrollToNotes {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.none) {
                        proxy.scrollTo("section.notes", anchor: UnitPoint(x: 0.5, y: 0.14))
                    }
                }
            }
        }
    }
}
