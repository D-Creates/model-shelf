import Foundation

/// Parsed safetensors header: 8-byte LE header length + JSON header.
public struct SafetensorsHeader: Sendable, Equatable {
    public var metadata: [String: String]
    public var tensors: [TensorSummary]
    public var tensorCount: Int
    /// Dominant dtype, e.g. "F16", "BF16".
    public var dominantDtype: String
    /// Sum of the data_offsets spans (the weight bytes on disk).
    public var weightBytes: UInt64
}

public enum SafetensorsParser {

    /// Max JSON header we are willing to read (100 MB).
    public static let maxHeaderLength: UInt64 = 100 * 1024 * 1024

    public static let dtypeSizes: [String: UInt64] = [
        "BOOL": 1, "U8": 1, "I8": 1, "F8_E5M2": 1, "F8_E4M3": 1,
        "I16": 2, "U16": 2, "F16": 2, "BF16": 2,
        "I32": 4, "U32": 4, "F32": 4,
        "I64": 8, "U64": 8, "F64": 8,
    ]

    public static func parse(fileURL: URL) throws -> SafetensorsHeader {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let lenBytes = (try handle.read(upToCount: 8)) ?? Data()
        guard lenBytes.count == 8 else { throw ModelParseError("File too small for safetensors") }
        let headerLen = UInt64(littleEndian: lenBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) })
        guard headerLen > 0 else { throw ModelParseError("Empty safetensors header") }
        guard headerLen <= maxHeaderLength else { throw ModelParseError("safetensors header too large") }
        let jsonBytes = (try handle.read(upToCount: Int(headerLen))) ?? Data()
        guard UInt64(jsonBytes.count) == headerLen else { throw ModelParseError("Truncated safetensors header") }
        var combined = Data(capacity: 8 + jsonBytes.count)
        combined.append(lenBytes)
        combined.append(jsonBytes)
        return try parse(data: combined)
    }

    public static func parse(data: Data) throws -> SafetensorsHeader {
        guard data.count >= 8 else { throw ModelParseError("File too small for safetensors") }
        let headerLen = data.subdata(in: 0..<8).withUnsafeBytes { $0.load(as: UInt64.self) }
        guard headerLen > 0 else { throw ModelParseError("Empty safetensors header") }
        guard headerLen <= maxHeaderLength else { throw ModelParseError("safetensors header too large") }
        guard UInt64(data.count) >= 8 + headerLen else { throw ModelParseError("Truncated safetensors header") }
        let jsonData = data.subdata(in: 8..<(8 + Int(headerLen)))
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData),
              let dict = obj as? [String: Any] else {
            throw ModelParseError("Invalid safetensors JSON header")
        }

        var metadata: [String: String] = [:]
        if let meta = dict["__metadata__"] as? [String: String] {
            metadata = meta
        }

        var tensors: [TensorSummary] = []
        var weightBytes: UInt64 = 0
        var dtypeCounts: [String: Int] = [:]

        for (name, raw) in dict where name != "__metadata__" {
            guard let entry = raw as? [String: Any],
                  let dtype = entry["dtype"] as? String,
                  let offsets = entry["data_offsets"] as? [NSNumber],
                  offsets.count == 2 else {
                throw ModelParseError("Bad tensor entry \(name)")
            }
            let start = offsets[0].uint64Value
            let end = offsets[1].uint64Value
            guard end >= start else { throw ModelParseError("Bad data_offsets for \(name)") }
            let span = end - start
            weightBytes &+= span
            var elements: UInt64 = 1
            if let shape = entry["shape"] as? [NSNumber] {
                for n in shape { elements &*= n.uint64Value }
            }
            tensors.append(TensorSummary(name: name, dtype: dtype, elementCount: elements, byteCount: span))
            dtypeCounts[dtype, default: 0] += 1
        }

        let dominant = dtypeCounts.max { $0.value < $1.value }?.key ?? "unknown"
        return SafetensorsHeader(metadata: metadata, tensors: tensors, tensorCount: tensors.count,
                                 dominantDtype: dominant, weightBytes: weightBytes)
    }
}

/// Writes minimal safetensors buffers for the -demo seed files and unit tests.
public enum DemoSafetensorsWriter {

    public struct TensorSpec {
        public var name: String
        public var dtype: String
        public var shape: [UInt64]
        public init(name: String, dtype: String, shape: [UInt64]) {
            self.name = name; self.dtype = dtype; self.shape = shape
        }
    }

    public static func makeSafetensors(metadata: [String: String] = [:],
                                       tensors: [TensorSpec]) -> Data {
        var entries: [String: Any] = [:]
        if !metadata.isEmpty { entries["__metadata__"] = metadata }
        var offset: UInt64 = 0
        for t in tensors {
            let elements = t.shape.reduce(UInt64(1)) { $0 &* $1 }
            let perElement = SafetensorsParser.dtypeSizes[t.dtype] ?? 0
            let bytes = elements &* perElement
            entries[t.name] = [
                "dtype": t.dtype,
                "shape": t.shape.map { NSNumber(value: $0) },
                "data_offsets": [NSNumber(value: offset), NSNumber(value: offset &+ bytes)],
            ] as [String: Any]
            offset &+= bytes
        }
        let json = try! JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
        var out = Data()
        var len = UInt64(json.count)
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(json)
        out.append(Data(repeating: 0, count: Int(offset)))
        return out
    }
}
