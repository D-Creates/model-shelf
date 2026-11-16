import SwiftUI

@main
struct ModelShelfMacApp: App {
    @StateObject private var library = ModelLibrary()
    @StateObject private var store = MetadataStore.shared

    var body: some Scene {
        WindowGroup {
            MacContentView(initialTab: ShelfTab(rawValue: LaunchArguments.tab ?? 0) ?? .library)
                .environmentObject(library)
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
                .task { library.loadInitial() }
        }
    }
}

struct MacContentView: View {
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var store: MetadataStore
    @State private var selection: ShelfTab
    @State private var selectedModel: ModelInfo?
    @State private var showingFolderPicker = false

    init(initialTab: ShelfTab) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Shelf") {
                    Label("Library", systemImage: ShelfTab.library.systemImage)
                        .tag(ShelfTab.library)
                        .accessibilityIdentifier("tab.Library")
                    Label("Settings", systemImage: ShelfTab.settings.systemImage)
                        .tag(ShelfTab.settings)
                        .accessibilityIdentifier("tab.Settings")
                }
                if selection == .library {
                    Section("Models in folder") {
                        ForEach(library.models) { info in
                            HStack {
                                ModelRowView(info: info)
                                Spacer()
                                BadgeView(badge: info.badge)
                            }
                            .tag(info)
                            .accessibilityIdentifier("model.row.\(info.name)")
                            .onTapGesture { selectedModel = info }
                        }
                        ForEach(library.errors.sorted(by: { $0.key < $1.key }), id: \.key) { path, message in
                            ModelErrorRowView(name: URL(fileURLWithPath: path).lastPathComponent, message: message)
                        }
                    }
                }
            }
            .accessibilityIdentifier("library.list")
            .listStyle(.sidebar)
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        library.setFolder(url)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
        } detail: {
            Group {
                if selection == .settings {
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
                            Text("Model Shelf reads model file headers only (GGUF, safetensors): size, tensor count, quantization, estimated RAM need, fits/tight/too-big badge. No inference, no model loading, no network. Notes and tags stay on this device.")
                                .accessibilityIdentifier("settings.about")
                        }
                    }
                    .navigationTitle("Settings")
                } else if let selectedModel {
                    ModelDetailView(info: selectedModel, store: store)
                } else {
                    ContentUnavailableView(
                        "No model selected",
                        systemImage: "books.vertical",
                        description: Text("Pick a folder with .gguf or .safetensors files, or load the demo files.")
                    )
                    .accessibilityIdentifier("library.empty")
                }
            }
            // Sidebar-column toolbar items only get the sidebar's width and collapse
            // into the overflow menu, so the actions live on the detail column.
            .toolbar {
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .accessibilityIdentifier("library.openFolder")
                Button("Demo") {
                    library.setFolder(DemoFiles.ensureDemoFiles(), saveBookmark: false)
                }
                .accessibilityIdentifier("settings.demo")
            }
        }
    }
}
