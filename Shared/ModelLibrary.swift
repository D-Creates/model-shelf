import Foundation

/// Holds the user-chosen folder and the scanned model list. Main-actor bound.
@MainActor
final class ModelLibrary: ObservableObject {
    @Published var folderURL: URL?
    @Published var models: [ModelInfo] = []
    @Published var errors: [String: String] = [:]

    private static let bookmarkKey = "ModelShelf.folderBookmark"

    private var didLoadInitial = false

    /// Called once at app launch. Handles -resetData / -demo and restores the
    /// last picked folder from its security-scoped bookmark.
    func loadInitial() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        if LaunchArguments.resetData {
            DemoFiles.resetAll()
            MetadataStore.shared.reset()
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
        if LaunchArguments.seedScreenshots {
            let seeded = DemoFiles.ensureStoreShowcaseFiles()
            for (path, entry) in seeded.entries {
                MetadataStore.shared.setEntry(entry, for: path)
            }
            setFolder(seeded.folder, saveBookmark: false)
            return
        }
        if LaunchArguments.demo {
            let url = DemoFiles.ensureDemoFiles()
            setFolder(url, saveBookmark: false)
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                folderURL = url
                scan()
            }
        }
    }

    func setFolder(_ url: URL, saveBookmark: Bool = true) {
        folderURL = url
        if saveBookmark {
            #if os(macOS)
            let data = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
            #else
            let data = try? url.bookmarkData()
            #endif
            if let data { UserDefaults.standard.set(data, forKey: Self.bookmarkKey) }
        }
        scan()
    }

    func addFiles(_ urls: [URL]) {
        // iOS single-file import: scan each picked file's parent folder is wrong;
        // instead scan each file individually and merge.
        var merged = models
        var mergedErrors = errors
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ModelScanner.supportedExtensions.contains(ext) else { continue }
            let path = url.path
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
            do {
                let info = try ModelScanner.parse(fileURL: url, path: path, name: url.lastPathComponent, ext: ext, fileSize: size)
                merged.removeAll { $0.path == path }
                merged.append(info)
            } catch let error as ModelParseError {
                mergedErrors[path] = error.message
            } catch {
                mergedErrors[path] = String(describing: error)
            }
        }
        models = merged.sorted { $0.name < $1.name }
        errors = mergedErrors
    }

    func scan() {
        guard let folderURL else {
            models = []
            errors = [:]
            return
        }
        let result = ModelScanner.scan(folder: folderURL)
        models = result.models
        errors = result.errors
    }
}
