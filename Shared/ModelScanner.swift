import Foundation

/// Result of scanning one folder.
public struct ScanResult: Sendable {
    public var models: [ModelInfo]
    /// path -> parse error message, for files that could not be read.
    public var errors: [String: String]
}

/// Scans a folder for .gguf / .safetensors files and parses their headers.
public enum ModelScanner {

    public static let supportedExtensions: Set<String> = ["gguf", "safetensors"]

    /// Keys copied from the header metadata into the inspector's summary.
    private static let shownMetadataKeys = [
        "general.architecture", "general.name", "general.quantization_version",
        "general.file_type", "general.size_label",
    ]

    public static func scan(folder: URL) -> ScanResult {
        var models: [ModelInfo] = []
        var errors: [String: String] = [:]
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return ScanResult(models: [], errors: [folder.path: "Folder not readable"])
        }
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let path = url.path
            let name = url.lastPathComponent
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
            do {
                let info = try parse(fileURL: url, path: path, name: name, ext: ext, fileSize: fileSize)
                models.append(info)
            } catch let error as ModelParseError {
                errors[path] = error.message
            } catch {
                errors[path] = String(describing: error)
            }
        }
        return ScanResult(models: models, errors: errors)
    }

    public static func parse(fileURL: URL, path: String, name: String, ext: String, fileSize: UInt64) throws -> ModelInfo {
        switch ext {
        case "gguf":
            let header = try GGUFParser.parse(fileURL: fileURL)
            let estimated = RAMEstimator.estimate(weightBytes: header.estimatedWeightBytes)
            var shown: [String: String] = [:]
            for key in shownMetadataKeys {
                if let v = header.metadata[key] { shown[key] = v }
            }
            return ModelInfo(path: path, name: name, kind: .gguf, fileSize: fileSize,
                             tensorCount: Int(header.tensorCount),
                             quantization: header.quantization, metadata: shown,
                             tensors: header.tensors, estimatedRAMBytes: estimated,
                             badge: RAMEstimator.badge(estimatedBytes: estimated))
        case "safetensors":
            let header = try SafetensorsParser.parse(fileURL: fileURL)
            let estimated = RAMEstimator.estimate(weightBytes: header.weightBytes)
            return ModelInfo(path: path, name: name, kind: .safetensors, fileSize: fileSize,
                             tensorCount: header.tensorCount,
                             quantization: header.dominantDtype, metadata: header.metadata,
                             tensors: header.tensors, estimatedRAMBytes: estimated,
                             badge: RAMEstimator.badge(estimatedBytes: estimated))
        default:
            throw ModelParseError("Unsupported extension \(ext)")
        }
    }
}
