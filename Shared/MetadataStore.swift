import Foundation

/// Per-file user metadata: free-text notes and tags. Stored on device only.
public struct ModelEntry: Codable, Sendable, Equatable {
    public var notes: String
    public var tags: [String]

    public init(notes: String = "", tags: [String] = []) {
        self.notes = notes
        self.tags = tags
    }
}

/// JSON-backed store of notes/tags, keyed by absolute file path.
@MainActor
final class MetadataStore: ObservableObject {
    static let shared = MetadataStore()

    @Published private(set) var entries: [String: ModelEntry] = [:]

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ModelShelf", isDirectory: true)
        return dir.appendingPathComponent("metadata.json")
    }

    private init() { load() }

    func entry(for path: String) -> ModelEntry {
        entries[path] ?? ModelEntry()
    }

    func setEntry(_ entry: ModelEntry, for path: String) {
        entries[path] = entry
        save()
    }

    func reset() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ModelEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(entries)
        try? data?.write(to: fileURL)
    }
}
