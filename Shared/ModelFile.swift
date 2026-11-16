import Foundation

/// On-disk format of a model file.
public enum ModelKind: String, Sendable, Codable {
    case gguf
    case safetensors
}

/// RAM-fit badge, computed from the estimated RAM need vs the device RAM.
public enum Badge: String, Sendable, Codable {
    case fits
    case tight
    case tooBig

    public var label: String {
        switch self {
        case .fits: "Fits"
        case .tight: "Tight"
        case .tooBig: "Too big"
        }
    }

    /// Stable accessibility identifier, e.g. "badge.fits".
    public var accessibilityId: String { "badge.\(rawValue)" }
}

/// One parsed tensor.
public struct TensorSummary: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var dtype: String
    public var elementCount: UInt64
    public var byteCount: UInt64

    public init(name: String, dtype: String, elementCount: UInt64, byteCount: UInt64) {
        self.name = name
        self.dtype = dtype
        self.elementCount = elementCount
        self.byteCount = byteCount
    }
}

/// Everything the inspector shows for one model file. Header data only.
public struct ModelInfo: Sendable, Identifiable, Equatable, Hashable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var kind: ModelKind
    public var fileSize: UInt64
    public var tensorCount: Int
    /// Quantization label (GGUF) or dominant dtype (safetensors).
    public var quantization: String
    /// Selected header metadata shown to the user.
    public var metadata: [String: String]
    public var tensors: [TensorSummary]
    public var estimatedRAMBytes: UInt64
    public var badge: Badge

    public init(path: String, name: String, kind: ModelKind, fileSize: UInt64,
                tensorCount: Int, quantization: String, metadata: [String: String],
                tensors: [TensorSummary], estimatedRAMBytes: UInt64, badge: Badge) {
        self.path = path
        self.name = name
        self.kind = kind
        self.fileSize = fileSize
        self.tensorCount = tensorCount
        self.quantization = quantization
        self.metadata = metadata
        self.tensors = tensors
        self.estimatedRAMBytes = estimatedRAMBytes
        self.badge = badge
    }
}

/// Error thrown when a model file header cannot be parsed.
public struct ModelParseError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// Human-readable byte count, e.g. "4.2 MB".
public func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
