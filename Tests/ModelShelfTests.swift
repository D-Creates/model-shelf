import XCTest
@testable import ModelShelf

final class ModelShelfTests: XCTestCase {

    // MARK: - GGUF header parsing

    func testGGUFParseHeader() throws {
        let data = DemoGGUFWriter.makeGGUF(
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("demo")),
                ("general.name", DemoGGUFWriter.stringValue("Unit Test Model")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            tensors: [
                DemoGGUFWriter.TensorSpec(name: "a.weight", dims: [256], type: 12), // Q4_K
                DemoGGUFWriter.TensorSpec(name: "b.weight", dims: [64, 64], type: 12),
            ],
            dataBytes: 512)
        let header = try GGUFParser.parse(data: data)
        XCTAssertEqual(header.version, 3)
        XCTAssertEqual(header.tensorCount, 2)
        XCTAssertEqual(header.metadata["general.architecture"], "demo")
        XCTAssertEqual(header.metadata["general.name"], "Unit Test Model")
        XCTAssertEqual(header.metadata["general.quantization_version"], "2")
        XCTAssertEqual(header.tensors.count, 2)
        XCTAssertEqual(header.tensors[0].name, "a.weight")
        XCTAssertEqual(header.tensors[0].dtype, "Q4_K")
        XCTAssertEqual(header.tensors[0].elementCount, 256)
        // Q4_K: 256 elements -> 1 block of 144 bytes.
        XCTAssertEqual(header.tensors[0].byteCount, 144)
        // 64x64 = 4096 elements -> 16 blocks x 144 = 2304 bytes.
        XCTAssertEqual(header.tensors[1].byteCount, 2304)
        XCTAssertEqual(header.estimatedWeightBytes, 144 + 2304)
        XCTAssertEqual(header.quantization, "Q4_K")
    }

    func testGGUFParseF16() throws {
        let data = DemoGGUFWriter.makeGGUF(
            metadata: [],
            tensors: [DemoGGUFWriter.TensorSpec(name: "w", dims: [100], type: 1)], // F16
            dataBytes: 0)
        let header = try GGUFParser.parse(data: data)
        XCTAssertEqual(header.quantization, "F16")
        XCTAssertEqual(header.tensors[0].byteCount, 200) // 100 elems x 2 bytes
    }

    func testGGUFMalformedMagic() {
        let data = Data("NOPE".utf8) + Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try GGUFParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Not a GGUF file (bad magic)"))
        }
    }

    func testGGUFTruncated() {
        let full = DemoGGUFWriter.makeGGUF(
            metadata: [("k", DemoGGUFWriter.stringValue("v"))],
            tensors: [DemoGGUFWriter.TensorSpec(name: "w", dims: [8], type: 0)],
            dataBytes: 0)
        let truncated = full.prefix(10)
        XCTAssertThrowsError(try GGUFParser.parse(data: Data(truncated)))
    }

    // MARK: - safetensors header parsing

    func testSafetensorsParseHeader() throws {
        let data = DemoSafetensorsWriter.makeSafetensors(
            metadata: ["format": "pt"],
            tensors: [
                DemoSafetensorsWriter.TensorSpec(name: "embed", dtype: "F16", shape: [512, 16]), // 16384 B
                DemoSafetensorsWriter.TensorSpec(name: "head", dtype: "BF16", shape: [512, 16]),  // 16384 B
            ])
        let header = try SafetensorsParser.parse(data: data)
        XCTAssertEqual(header.tensorCount, 2)
        XCTAssertEqual(header.metadata["format"], "pt")
        let embed = header.tensors.first { $0.name == "embed" }!
        XCTAssertEqual(embed.dtype, "F16")
        XCTAssertEqual(embed.elementCount, 512 * 16)
        XCTAssertEqual(embed.byteCount, 512 * 16 * 2)
        XCTAssertEqual(header.weightBytes, 2 * 512 * 16 * 2)
        XCTAssertTrue(header.dominantDtype == "F16" || header.dominantDtype == "BF16")
    }

    func testSafetensorsMalformedTooSmall() {
        XCTAssertThrowsError(try SafetensorsParser.parse(data: Data(repeating: 0, count: 4)))
    }

    func testSafetensorsMalformedHeaderLength() {
        var data = Data(repeating: 0, count: 64)
        // header length = huge
        var huge = UInt64(1) << 40
        withUnsafeBytes(of: &huge) { data.replaceSubrange(0..<8, with: $0) }
        XCTAssertThrowsError(try SafetensorsParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("safetensors header too large"))
        }
    }

    func testSafetensorsMalformedJSON() {
        var data = Data()
        var len = UInt64(5)
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(Data("{nope".utf8))
        XCTAssertThrowsError(try SafetensorsParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Invalid safetensors JSON header"))
        }
    }

    // MARK: - RAM estimate

    func testRAMEstimateAddsOverhead() {
        XCTAssertEqual(RAMEstimator.estimate(weightBytes: 1_000_000), 1_050_000)
        XCTAssertEqual(RAMEstimator.estimate(weightBytes: 0), 0)
    }

    // MARK: - Badge thresholds (device RAM = 16 GB)

    private let ram16GB: UInt64 = 16 * 1024 * 1024 * 1024

    func testBadgeFitsAtOrBelowHalf() {
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: ram16GB / 2, deviceRAM: ram16GB), .fits)
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: ram16GB / 4, deviceRAM: ram16GB), .fits)
    }

    func testBadgeTightUpTo85Percent() {
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: ram16GB / 2 + 1, deviceRAM: ram16GB), .tight)
        let exact85 = UInt64(Double(ram16GB) * 0.85)
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: exact85, deviceRAM: ram16GB), .tight)
    }

    func testBadgeTooBigAbove85Percent() {
        let justOver = UInt64(Double(ram16GB) * 0.85) + 1
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: justOver, deviceRAM: ram16GB), .tooBig)
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: ram16GB, deviceRAM: ram16GB), .tooBig)
    }

    func testBadgeZeroDeviceRAM() {
        XCTAssertEqual(RAMEstimator.badge(estimatedBytes: 1, deviceRAM: 0), .tooBig)
    }

    // MARK: - Scanner end to end with demo files

    func testScanDemoFolder() throws {
        let dir = DemoFiles.ensureDemoFiles()
        let result = ModelScanner.scan(folder: dir)
        XCTAssertEqual(result.models.count, 4, "4 parseable demo files expected")
        XCTAssertEqual(result.errors.count, 1, "corrupt.gguf expected to fail")
        let names = result.models.map(\.name)
        XCTAssertTrue(names.contains("tiny-q4k.gguf"))
        XCTAssertTrue(names.contains("tiny-f16.safetensors"))
        let q4k = result.models.first { $0.name == "tiny-q4k.gguf" }!
        XCTAssertEqual(q4k.kind, .gguf)
        XCTAssertEqual(q4k.tensorCount, 2)
        XCTAssertEqual(q4k.quantization, "Q4_K")
        XCTAssertEqual(q4k.badge, .fits) // a few KB on any device
        let f16 = result.models.first { $0.name == "tiny-f16.safetensors" }!
        XCTAssertEqual(f16.kind, .safetensors)
        XCTAssertEqual(f16.tensorCount, 3)
        XCTAssertEqual(f16.quantization, "F16")
        // 512*16*2 + 256*16*2 + 512*16*2 = 40960 weight bytes -> x1.05
        XCTAssertEqual(f16.estimatedRAMBytes, RAMEstimator.estimate(weightBytes: 40960))
    }

    func testScanEmptyFolder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelShelfEmptyTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let result = ModelScanner.scan(folder: dir)
        XCTAssertTrue(result.models.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }
}

final class ModelShelfEdgeCaseTests: XCTestCase {

    private func rawSafetensors(json: String, declaredLength: UInt64? = nil) -> Data {
        let body = Data(json.utf8)
        var len = declaredLength ?? UInt64(body.count)
        var data = Data()
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(body)
        return data
    }

    // MARK: - safetensors edge cases

    func testSafetensorsEmptyHeaderLength() {
        XCTAssertThrowsError(try SafetensorsParser.parse(data: Data(repeating: 0, count: 8))) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Empty safetensors header"))
        }
    }

    func testSafetensorsTruncatedHeader() {
        let data = rawSafetensors(json: "{\"a\":", declaredLength: 100)
        XCTAssertThrowsError(try SafetensorsParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Truncated safetensors header"))
        }
    }

    func testSafetensorsBadTensorEntry() {
        let data = rawSafetensors(json: "{\"w\":{\"dtype\":\"F32\",\"shape\":[2]}}")
        XCTAssertThrowsError(try SafetensorsParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Bad tensor entry w"))
        }
    }

    func testSafetensorsReversedOffsets() {
        let data = rawSafetensors(json: "{\"w\":{\"dtype\":\"F32\",\"shape\":[2],\"data_offsets\":[8,0]}}")
        XCTAssertThrowsError(try SafetensorsParser.parse(data: data)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Bad data_offsets for w"))
        }
    }

    func testSafetensorsNoTensors() throws {
        let header = try SafetensorsParser.parse(data: rawSafetensors(json: "{}"))
        XCTAssertEqual(header.tensorCount, 0)
        XCTAssertTrue(header.tensors.isEmpty)
        XCTAssertTrue(header.metadata.isEmpty)
        XCTAssertEqual(header.weightBytes, 0)
        XCTAssertEqual(header.dominantDtype, "unknown")
    }

    func testSafetensorsDominantDtypeAndWeightBytes() throws {
        let data = DemoSafetensorsWriter.makeSafetensors(tensors: [
            DemoSafetensorsWriter.TensorSpec(name: "a", dtype: "F32", shape: [4, 4]), // 64 B
            DemoSafetensorsWriter.TensorSpec(name: "b", dtype: "F32", shape: [8]),    // 32 B
            DemoSafetensorsWriter.TensorSpec(name: "c", dtype: "F16", shape: [10]),   // 20 B
        ])
        let header = try SafetensorsParser.parse(data: data)
        XCTAssertEqual(header.tensorCount, 3)
        XCTAssertEqual(header.dominantDtype, "F32")
        XCTAssertEqual(header.weightBytes, 64 + 32 + 20)
        XCTAssertTrue(header.metadata.isEmpty)
        XCTAssertEqual(header.tensors.first { $0.name == "a" }?.elementCount, 16)
    }

    // MARK: - Badge

    func testBadgeLabelsAndAccessibilityIds() {
        XCTAssertEqual(Badge.fits.label, "Fits")
        XCTAssertEqual(Badge.tight.label, "Tight")
        XCTAssertEqual(Badge.tooBig.label, "Too big")
        XCTAssertEqual(Badge.fits.accessibilityId, "badge.fits")
        XCTAssertEqual(Badge.tooBig.accessibilityId, "badge.tooBig")
    }

    // MARK: - Scanner

    func testScannerUnsupportedExtensionThrows() {
        let url = URL(fileURLWithPath: "/tmp/model.bin")
        XCTAssertThrowsError(try ModelScanner.parse(fileURL: url, path: url.path, name: "model.bin",
                                                    ext: "bin", fileSize: 0)) { error in
            XCTAssertEqual(error as? ModelParseError, ModelParseError("Unsupported extension bin"))
        }
    }

    func testScanMissingFolderReportsError() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelShelfMissing-\(UUID().uuidString)", isDirectory: true)
        let result = ModelScanner.scan(folder: dir)
        XCTAssertTrue(result.models.isEmpty)
        XCTAssertEqual(result.errors[dir.path], "Folder not readable")
    }

    func testScanSkipsOtherFilesAndSortsByName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelShelfMixedTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let st = DemoSafetensorsWriter.makeSafetensors(tensors: [
            DemoSafetensorsWriter.TensorSpec(name: "w", dtype: "F32", shape: [4]),
        ])
        try st.write(to: dir.appendingPathComponent("zeta.SAFETENSORS"))
        try st.write(to: dir.appendingPathComponent("alpha.safetensors"))
        try Data("hello".utf8).write(to: dir.appendingPathComponent("readme.txt"))
        let result = ModelScanner.scan(folder: dir)
        XCTAssertEqual(result.models.map(\.name), ["alpha.safetensors", "zeta.SAFETENSORS"])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.models.first?.fileSize, UInt64(st.count))
        XCTAssertEqual(result.models.first?.estimatedRAMBytes, RAMEstimator.estimate(weightBytes: 16))
    }

    // MARK: - ModelEntry

    func testModelEntryCodableRoundTrip() throws {
        let entry = ModelEntry(notes: "fast on M2", tags: ["chat", "q4"])
        let decoded = try JSONDecoder().decode(ModelEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(ModelEntry(), ModelEntry(notes: "", tags: []))
    }

    func testShelfTabMetadata() {
        XCTAssertEqual(ShelfTab.allCases, [.library, .settings])
        XCTAssertEqual(ShelfTab.library.title, "Library")
        XCTAssertEqual(ShelfTab.settings.title, "Settings")
        XCTAssertEqual(ShelfTab.library.accessibilityId, "tab.Library")
        XCTAssertEqual(ShelfTab.settings.accessibilityId, "tab.Settings")
    }
}
