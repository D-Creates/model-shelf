import Foundation

/// Top-level tabs/sections shared by the iOS TabView and the macOS sidebar.
public enum ShelfTab: Int, Hashable, Identifiable, CaseIterable, Sendable {
    case library, settings
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .library: "Library"
        case .settings: "Settings"
        }
    }
    public var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .settings: "gearshape"
        }
    }
    public var accessibilityId: String { "tab.\(title)" }
}
