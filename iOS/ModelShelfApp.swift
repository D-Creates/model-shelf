import SwiftUI
import UniformTypeIdentifiers

@main
struct ModelShelfApp: App {
    @StateObject private var library = ModelLibrary()
    @StateObject private var store = MetadataStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView(initialTab: ShelfTab(rawValue: LaunchArguments.tab ?? 0) ?? .library)
                .environmentObject(library)
                .environmentObject(store)
                .task { library.loadInitial() }
        }
    }
}

struct ContentView: View {
    @State private var selection: ShelfTab
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(initialTab: ShelfTab) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad (and any regular-width size class): two-column split view.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List {
                    ForEach(ShelfTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("sidebar.\(tab.title)")
                        .listRowBackground(selection == tab ? Color.accentColor.opacity(0.25) : nil)
                    }
                }
                .accessibilityIdentifier("sidebar")
                .navigationTitle("Model Shelf")
            } detail: {
                NavigationStack {
                    detailView(for: selection)
                }
                .id(selection)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            // iPhone (compact width): tab bar.
            TabView(selection: $selection) {
                NavigationStack {
                    LibraryView()
                }
                .tag(ShelfTab.library)
                .tabItem { Label(ShelfTab.library.title, systemImage: ShelfTab.library.systemImage) }
                .accessibilityIdentifier(ShelfTab.library.accessibilityId)

                NavigationStack {
                    SettingsView()
                }
                .tag(ShelfTab.settings)
                .tabItem { Label(ShelfTab.settings.title, systemImage: ShelfTab.settings.systemImage) }
                .accessibilityIdentifier(ShelfTab.settings.accessibilityId)
            }
        }
    }

    @ViewBuilder
    private func detailView(for tab: ShelfTab) -> some View {
        switch tab {
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var store: MetadataStore
    @State private var showingFolderPicker = false
    @State private var showingFileImporter = false

    var body: some View {
        List {
            if library.models.isEmpty && library.errors.isEmpty {
                Section {
                    Text("No model files yet. Choose a folder or import .gguf / .safetensors files from Files. Headers only are read — nothing is loaded or sent anywhere.")
                        .accessibilityIdentifier("library.empty")
                }
            }
            Section("Models") {
                ForEach(library.models) { info in
                    NavigationLink(value: info) {
                        ModelRowView(info: info)
                    }
                    .accessibilityIdentifier("model.row.\(info.name)")
                }
                ForEach(library.errors.sorted(by: { $0.key < $1.key }), id: \.key) { path, message in
                    ModelErrorRowView(name: URL(fileURLWithPath: path).lastPathComponent, message: message)
                        .accessibilityIdentifier("model.row.\(URL(fileURLWithPath: path).lastPathComponent)")
                }
            }
        }
        .accessibilityIdentifier("library.list")
        .navigationTitle("Model Shelf")
        .navigationDestination(for: ModelInfo.self) { info in
            ModelDetailView(info: info, store: store)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("library.openFolder")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("library.importFiles")
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            DirectoryPicker { url in
                if url.startAccessingSecurityScopedResource() {
                    library.setFolder(url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                library.addFiles(urls)
            }
        }
    }
}

/// UIKit wrapper for picking a folder from the Files app.
struct DirectoryPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var library: ModelLibrary

    var body: some View {
        Form {
            Section("Data") {
                Button("Load demo files") {
                    library.setFolder(DemoFiles.ensureDemoFiles(), saveBookmark: false)
                }
                .accessibilityIdentifier("settings.loadDemo")
                Button("Reset all data", role: .destructive) {
                    DemoFiles.resetAll()
                    MetadataStore.shared.reset()
                    library.scan()
                }
                .accessibilityIdentifier("settings.reset")
            }
            Section("Device") {
                LabeledContent("Device RAM", value: formatBytes(ProcessInfo.processInfo.physicalMemory))
                    .accessibilityIdentifier("settings.deviceRAM")
            }
            Section("About") {
                Text("Model Shelf is a library and inspector for local model files (GGUF and safetensors). It reads file headers only: size, tensor count, quantization, estimated RAM need and a fits/tight/too-big badge. No inference, no model loading, no network. Notes and tags stay on this device.")
                    .accessibilityIdentifier("settings.about")
            }
        }
        .navigationTitle("Settings")
    }
}
