import Foundation

/// Parsed GGUF header (magic, version, metadata, tensor infos). Header only —
/// tensor weight data is never read.
public struct GGUFHeader: Sendable, Equatable {
    public var version: UInt32
    public var tensorCount: UInt64
    public var metadata: [String: String]
    public var tensors: [TensorSummary]
    /// Byte offset where tensor data starts (after alignment padding).
    public var dataStart: UInt64
    public var estimatedWeightBytes: UInt64
    /// Dominant ggml type name, e.g. "Q4_K", "F16".
    public var quantization: String
}

public enum GGUFParser {

    public static let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46] // "GGUF"

    /// ggml_type table: type -> (name, block elements, block bytes).
    /// Unknown types return nil and fall back to the file-size estimate.
    public static func ggmlTypeInfo(_ type: UInt32) -> (name: String, blockElements: UInt64, blockBytes: UInt64)? {
        switch type {
        case 0: return ("F32", 1, 4)
        case 1: return ("F16", 1, 2)
        case 2: return ("Q4_0", 32, 18)
        case 3: return ("Q4_1", 32, 20)
        case 6: return ("Q5_0", 32, 22)
        case 7: return ("Q5_1", 32, 24)
        case 8: return ("Q8_0", 32, 34)
        case 9: return ("Q8_1", 32, 36)
        case 10: return ("Q2_K", 256, 84)
        case 11: return ("Q3_K", 256, 110)
        case 12: return ("Q4_K", 256, 144)
        case 13: return ("Q5_K", 256, 176)
        case 14: return ("Q6_K", 256, 210)
        case 15: return ("Q8_K", 256, 292)
        case 30: return ("BF16", 1, 2)
        default: return nil
        }
    }

    /// Max bytes read from disk when inspecting a GGUF header (32 MB).
    public static let maxHeaderReadBytes = 32 * 1024 * 1024

    /// Parse the header of a GGUF file. Reads only the header region.
    public static func parse(fileURL: URL) throws -> GGUFHeader {
        let actualSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = (try handle.read(upToCount: maxHeaderReadBytes)) ?? Data()
        var cursor = Cursor(data)
        return try parse(cursor: &cursor, fileSize: max(actualSize, UInt64(data.count)))
    }

    public static func parse(data: Data) throws -> GGUFHeader {
        var cursor = Cursor(data)
        return try parse(cursor: &cursor, fileSize: UInt64(data.count))
    }

    private static func parse(cursor: inout Cursor, fileSize: UInt64) throws -> GGUFHeader {
        let magicBytes = try cursor.readBytes(4)
        guard magicBytes == magic else {
            throw ModelParseError("Not a GGUF file (bad magic)")
        }
        let version = try cursor.readU32()
        guard version >= 1 && version <= 3 else {
            throw ModelParseError("Unsupported GGUF version \(version)")
        }
        let tensorCount = try cursor.readU64()
        let kvCount = try cursor.readU64()
        guard kvCount <= 100_000 else { throw ModelParseError("Implausible metadata count") }

        var metadata: [String: String] = [:]
        for _ in 0..<kvCount {
            let key = try cursor.readString()
            let valueType = try cursor.readU32()
            let value = try readValue(cursor: &cursor, type: valueType)
            metadata[key] = value
        }

        var tensors: [TensorSummary] = []
        tensors.reserveCapacity(Int(min(tensorCount, 1_000_000)))
        var unknownType = false
        var weightBytes: UInt64 = 0
        var minDataOffset: UInt64 = .max
        var typeCounts: [String: Int] = [:]

        for _ in 0..<tensorCount {
            let name = try cursor.readString()
            let nDims = try cursor.readU32()
            guard nDims >= 1 && nDims <= 8 else { throw ModelParseError("Bad dimension count for tensor \(name)") }
            var elements: UInt64 = 1
            for _ in 0..<nDims {
                let dim = try cursor.readU64()
                guard dim > 0 && dim <= 1 << 40 else { throw ModelParseError("Bad dimension for tensor \(name)") }
                elements &*= dim
            }
            let type = try cursor.readU32()
            let offset = try cursor.readU64()
            minDataOffset = min(minDataOffset, offset)
            if let info = ggmlTypeInfo(type) {
                let blocks = (elements + info.blockElements - 1) / info.blockElements
                let bytes = blocks &* info.blockBytes
                weightBytes &+= bytes
                tensors.append(TensorSummary(name: name, dtype: info.name, elementCount: elements, byteCount: bytes))
                typeCounts[info.name, default: 0] += 1
            } else {
                unknownType = true
                tensors.append(TensorSummary(name: name, dtype: "type\(type)", elementCount: elements, byteCount: 0))
            }
        }

        if unknownType, minDataOffset != .max, minDataOffset < fileSize {
            weightBytes = fileSize - minDataOffset
        }

        let dataStart = minDataOffset == .max ? UInt64(cursor.offset) : minDataOffset
        let quantization = typeCounts.max { $0.value < $1.value }?.key ?? "unknown"
        return GGUFHeader(version: version, tensorCount: tensorCount, metadata: metadata,
                          tensors: tensors, dataStart: dataStart,
                          estimatedWeightBytes: weightBytes, quantization: quantization)
    }

    private static func readValue(cursor: inout Cursor, type: UInt32) throws -> String {
        switch type {
        case 0: return String(try cursor.readU8())
        case 1: return String(Int8(bitPattern: try cursor.readU8()))
        case 2: return String(try cursor.readU16())
        case 3: return String(Int16(bitPattern: try cursor.readU16()))
        case 4: return String(try cursor.readU32())
        case 5: return String(try cursor.readI32())
        case 6: return String(try cursor.readF32())
        case 7: return try cursor.readU8() == 0 ? "false" : "true"
        case 8: return try cursor.readString()
        case 9:
            let elemType = try cursor.readU32()
            let len = try cursor.readU64()
            guard len <= 1_000_000 else { throw ModelParseError("Implausible array length") }
            var parts: [String] = []
            for _ in 0..<len { parts.append(try readValue(cursor: &cursor, type: elemType)) }
            return "[" + parts.joined(separator: ", ") + "]"
        case 10: return String(try cursor.readU64())
        case 11: return String(try cursor.readI64())
        case 12: return String(try cursor.readF64())
        default: throw ModelParseError("Unknown metadata value type \(type)")
        }
    }

    private struct Cursor {
        let data: Data
        var offset: Int = 0

        init(_ data: Data) { self.data = data }

        mutating func readBytes(_ count: Int) throws -> [UInt8] {
            guard offset + count <= data.count else { throw ModelParseError("Unexpected end of file") }
            let slice = data.subdata(in: offset..<(offset + count))
            offset += count
            return [UInt8](slice)
        }

        private mutating func readFixed<T>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            let bytes = try readBytes(size)
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }

        mutating func readU8() throws -> UInt8 { try readFixed(UInt8.self) }
        mutating func readU16() throws -> UInt16 { UInt16(littleEndian: try readFixed(UInt16.self)) }
        mutating func readU32() throws -> UInt32 { UInt32(littleEndian: try readFixed(UInt32.self)) }
        mutating func readU64() throws -> UInt64 { UInt64(littleEndian: try readFixed(UInt64.self)) }
        mutating func readI32() throws -> Int32 { Int32(littleEndian: try readFixed(Int32.self)) }
        mutating func readI64() throws -> Int64 { Int64(littleEndian: try readFixed(Int64.self)) }
        mutating func readF32() throws -> Float { Float(bitPattern: try readU32()) }
        mutating func readF64() throws -> Double { Double(bitPattern: try readU64()) }

        mutating func readString() throws -> String {
            let len = try readU64()
            guard len <= 1 << 24 else { throw ModelParseError("Implausible string length") }
            let bytes = try readBytes(Int(len))
            guard let s = String(bytes: bytes, encoding: .utf8) else { throw ModelParseError("Invalid UTF-8 string") }
            return s
        }
    }
}

/// Writes minimal valid GGUF byte buffers. Used by the -demo seed files and by
/// the unit tests. Produces a few KB, never a real model.
public enum DemoGGUFWriter {

    public struct TensorSpec {
        public var name: String
        public var dims: [UInt64]
        public var type: UInt32
        public init(name: String, dims: [UInt64], type: UInt32) {
            self.name = name; self.dims = dims; self.type = type
        }
    }

    public static func makeGGUF(version: UInt32 = 3,
                              metadata: [(String, (UInt32, Data))],
                              tensors: [TensorSpec],
                              dataBytes: Int = 0) -> Data {
        var out = Data()
        out.append(contentsOf: GGUFParser.magic)
        append(&out, version)
        append(&out, UInt64(tensors.count))
        append(&out, UInt64(metadata.count))
        for (key, value) in metadata {
            appendString(&out, key)
            append(&out, value.0)
            out.append(value.1)
        }
        var offset: UInt64 = 0
        for t in tensors {
            appendString(&out, t.name)
            append(&out, UInt32(t.dims.count))
            for d in t.dims { append(&out, d) }
            append(&out, t.type)
            append(&out, offset)
            let info = GGUFParser.ggmlTypeInfo(t.type)
            let elements = t.dims.reduce(UInt64(1)) { $0 &* $1 }
            let blockBytes = info.map { (elements + $0.blockElements - 1) / $0.blockElements &* $0.blockBytes } ?? UInt64(0)
            offset &+= blockBytes
        }
        // align data start to 32 bytes like real writers do
        let aligned = (UInt64(out.count) + 31) / 32 * 32
        out.append(Data(repeating: 0, count: Int(aligned - UInt64(out.count))))
        out.append(Data(repeating: 0, count: dataBytes))
        return out
    }

    public static func stringValue(_ s: String) -> (UInt32, Data) {
        var d = Data()
        appendString(&d, s)
        return (8, d) // STRING
    }

    public static func u32Value(_ v: UInt32) -> (UInt32, Data) {
        var d = Data()
        append(&d, v)
        return (4, d) // UINT32
    }

    private static func append<T>(_ out: inout Data, _ value: T) {
        var v = value
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
    }

    private static func appendString(_ out: inout Data, _ s: String) {
        let bytes = Array(s.utf8)
        append(&out, UInt64(bytes.count))
        out.append(contentsOf: bytes)
    }
}
