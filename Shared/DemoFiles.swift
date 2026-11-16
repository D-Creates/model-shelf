import Foundation

/// Generates tiny fake model header files (a few KB, never real models) so the
/// app can be tested and screenshotted with -demo. No model is ever loaded.
public enum DemoFiles {

    public static func demoDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ModelShelfDemo", isDirectory: true)
    }

    /// Creates the demo folder and its fake files if missing. Returns the folder.
    @discardableResult
    public static func ensureDemoFiles() -> URL {
        let dir = demoDirectory()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Fake GGUF, Q4_K weights: 2 tensors x 4096 elements = 16 blocks x 144 B.
        let q4k = DemoGGUFWriter.makeGGUF(
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("demo")),
                ("general.name", DemoGGUFWriter.stringValue("Tiny Demo Q4_K")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            tensors: [
                DemoGGUFWriter.TensorSpec(name: "blk.0.attn.weight", dims: [64, 64], type: 12), // Q4_K
                DemoGGUFWriter.TensorSpec(name: "blk.0.ffn.weight", dims: [64, 64], type: 12),
            ],
            dataBytes: 2048)
        writeIfMissing(q4k, name: "tiny-q4k.gguf", in: dir)

        // Fake GGUF, Q8_0 weights.
        let q8 = DemoGGUFWriter.makeGGUF(
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("demo")),
                ("general.name", DemoGGUFWriter.stringValue("Tiny Demo Q8_0")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            tensors: [
                DemoGGUFWriter.TensorSpec(name: "blk.0.attn.weight", dims: [128, 32], type: 8), // Q8_0
                DemoGGUFWriter.TensorSpec(name: "output.weight", dims: [128, 32], type: 8),
            ],
            dataBytes: 1024)
        writeIfMissing(q8, name: "tiny-q8.gguf", in: dir)

        // Fake safetensors, F16.
        let f16 = DemoSafetensorsWriter.makeSafetensors(
            metadata: ["format": "pt", "demo": "true"],
            tensors: [
                DemoSafetensorsWriter.TensorSpec(name: "model.embed.weight", dtype: "F16", shape: [512, 16]),
                DemoSafetensorsWriter.TensorSpec(name: "model.layers.0.weight", dtype: "F16", shape: [256, 16]),
                DemoSafetensorsWriter.TensorSpec(name: "lm_head.weight", dtype: "F16", shape: [512, 16]),
            ])
        writeIfMissing(f16, name: "tiny-f16.safetensors", in: dir)

        // Fake safetensors, BF16.
        let bf16 = DemoSafetensorsWriter.makeSafetensors(
            metadata: ["format": "pt"],
            tensors: [
                DemoSafetensorsWriter.TensorSpec(name: "model.embed.weight", dtype: "BF16", shape: [256, 32]),
                DemoSafetensorsWriter.TensorSpec(name: "lm_head.weight", dtype: "BF16", shape: [256, 32]),
            ])
        writeIfMissing(bf16, name: "tiny-bf16.safetensors", in: dir)

        // Deliberately corrupt file: shows the "unreadable" row.
        writeIfMissing(Data("NOTAGGUF".utf8), name: "corrupt.gguf", in: dir)

        return dir
    }

    public static func storeShowcaseDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ModelShelfStoreDemo", isDirectory: true)
    }

    /// Deletes the demo folders (used by -resetData).
    public static func resetAll() {
        try? FileManager.default.removeItem(at: demoDirectory())
        try? FileManager.default.removeItem(at: storeShowcaseDirectory())
    }

    /// Creates header-only showcase models with APFS sparse sizes and sample notes/tags for App Store screenshots.
    public static func ensureStoreShowcaseFiles(
        deviceRAM: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> (folder: URL, entries: [String: ModelEntry]) {
        let dir = storeShowcaseDirectory()
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let ram = max(deviceRAM, 8 * 1024 * 1024 * 1024)

        let llamaPath = writeShowcaseGGUF(
            name: "llama-3.2-3b-instruct-q4_k.gguf",
            in: dir,
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("llama")),
                ("general.name", DemoGGUFWriter.stringValue("Llama 3.2 3B Instruct")),
                ("general.size_label", DemoGGUFWriter.stringValue("3B")),
                ("general.file_type", DemoGGUFWriter.stringValue("Q4_K_M")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            layerCount: 6,
            ggmlType: 12,
            blockBytes: 144,
            targetWeightBytes: UInt64(Double(ram) * 0.12)
        )

        let qwenPath = writeShowcaseGGUF(
            name: "qwen2.5-coder-7b-q4_k.gguf",
            in: dir,
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("qwen2")),
                ("general.name", DemoGGUFWriter.stringValue("Qwen 2.5 Coder 7B Instruct")),
                ("general.size_label", DemoGGUFWriter.stringValue("7B")),
                ("general.file_type", DemoGGUFWriter.stringValue("Q4_K_M")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            layerCount: 7,
            ggmlType: 12,
            blockBytes: 144,
            targetWeightBytes: UInt64(Double(ram) * 0.27)
        )

        let mistralPath = writeShowcaseGGUF(
            name: "mistral-nemo-12b-q5_k.gguf",
            in: dir,
            metadata: [
                ("general.architecture", DemoGGUFWriter.stringValue("llama")),
                ("general.name", DemoGGUFWriter.stringValue("Mistral Nemo 12B Instruct")),
                ("general.size_label", DemoGGUFWriter.stringValue("12B")),
                ("general.file_type", DemoGGUFWriter.stringValue("Q5_K_M")),
                ("general.quantization_version", DemoGGUFWriter.u32Value(2)),
            ],
            layerCount: 7,
            ggmlType: 13,
            blockBytes: 176,
            targetWeightBytes: UInt64(Double(ram) * 0.53)
        )

        let fluxPath = writeShowcaseSafetensors(
            name: "flux-1-schnell-bf16.safetensors",
            in: dir,
            metadata: [
                "architecture": "flux-schnell",
                "format": "pt",
                "license": "apache-2.0",
                "precision": "bfloat16",
            ],
            prefix: "transformer.blocks",
            layerCount: 8,
            dtype: "BF16",
            targetWeightBytes: UInt64(Double(ram) * 0.68)
        )

        _ = writeShowcaseSafetensors(
            name: "deepseek-r1-32b-f16.safetensors",
            in: dir,
            metadata: [
                "architecture": "qwen2",
                "format": "pt",
                "license": "mit",
                "precision": "float16",
            ],
            prefix: "model.layers",
            layerCount: 9,
            dtype: "F16",
            targetWeightBytes: UInt64(Double(ram) * 1.12)
        )

        // Truncated GGUF header -> surfaces "Unexpected end of file" with Unreadable badge.
        var truncated = Data(GGUFParser.magic)
        var ver: UInt32 = 3
        withUnsafeBytes(of: &ver) { truncated.append(contentsOf: $0) }
        truncated.append(contentsOf: [0x10, 0x00])
        try? truncated.write(to: dir.appendingPathComponent("incomplete-download.gguf"))

        let entries: [String: ModelEntry] = [
            llamaPath: ModelEntry(
                notes: "Lightweight daily chat assistant that leaves plenty of unified memory free.",
                tags: ["chat", "llama3", "q4_k", "fast"]
            ),
            qwenPath: ModelEntry(
                notes: "Fast local coding model — clean Swift and Python completions offline.",
                tags: ["coding", "swift", "q4_k", "favorite"]
            ),
            mistralPath: ModelEntry(
                notes: "Strong 12B long-context weights; close heavy apps before loading.",
                tags: ["long-context", "q5_k", "12b"]
            ),
            fluxPath: ModelEntry(
                notes: "4-step rectified flow weights in BF16 precision.",
                tags: ["image", "bf16", "safetensors"]
            ),
        ]
        return (dir, entries)
    }

    private static func writeShowcaseGGUF(
        name: String,
        in dir: URL,
        metadata: [(String, (UInt32, Data))],
        layerCount: Int,
        ggmlType: UInt32,
        blockBytes: UInt64,
        targetWeightBytes: UInt64
    ) -> String {
        var weightedTensors: [(String, Double)] = [("token_embd.weight", 1.8)]
        for i in 0..<layerCount {
            weightedTensors.append(("blk.\(i).attn_q.weight", 0.8))
            weightedTensors.append(("blk.\(i).attn_k.weight", 0.35))
            weightedTensors.append(("blk.\(i).ffn_gate.weight", 1.45))
            weightedTensors.append(("blk.\(i).ffn_down.weight", 1.4))
        }
        weightedTensors.append(("output.weight", 1.8))

        let weightSum = weightedTensors.reduce(0.0) { $0 + $1.1 }
        var actualWeightBytes: UInt64 = 0
        let specs: [DemoGGUFWriter.TensorSpec] = weightedTensors.map { name, ratio in
            let targetForTensor = Double(targetWeightBytes) * (ratio / weightSum)
            let blocks = max(16, UInt64(targetForTensor / Double(blockBytes)) / 16 * 16)
            let rows = max(1, blocks / 16)
            actualWeightBytes += (rows * 16) * blockBytes
            return DemoGGUFWriter.TensorSpec(name: name, dims: [4096, rows], type: ggmlType)
        }
        let header = DemoGGUFWriter.makeGGUF(metadata: metadata, tensors: specs, dataBytes: 0)
        return writeSparse(header, totalBytes: UInt64(header.count) + actualWeightBytes, name: name, in: dir)
    }

    private static func writeShowcaseSafetensors(
        name: String,
        in dir: URL,
        metadata: [String: String],
        prefix: String,
        layerCount: Int,
        dtype: String,
        targetWeightBytes: UInt64
    ) -> String {
        var tensorNames: [String] = ["\(prefix).embed.weight"]
        for i in 0..<layerCount {
            tensorNames.append("\(prefix).\(i).attn.q_proj.weight")
            tensorNames.append("\(prefix).\(i).attn.v_proj.weight")
            tensorNames.append("\(prefix).\(i).mlp.down_proj.weight")
        }
        tensorNames.append("lm_head.weight")

        let count = UInt64(tensorNames.count)
        let bytesPerElement = SafetensorsParser.dtypeSizes[dtype] ?? 2
        let rowBytes = 4096 * bytesPerElement
        let rows = max(1, (targetWeightBytes / count) / rowBytes)
        let tensorBytes = rows * rowBytes

        var entries: [String: Any] = ["__metadata__": metadata]
        var offset: UInt64 = 0
        for tName in tensorNames {
            entries[tName] = [
                "dtype": dtype,
                "shape": [NSNumber(value: 4096), NSNumber(value: rows)],
                "data_offsets": [NSNumber(value: offset), NSNumber(value: offset + tensorBytes)],
            ] as [String: Any]
            offset += tensorBytes
        }
        let json = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])) ?? Data("{}".utf8)
        var header = Data(capacity: 8 + json.count)
        var len = UInt64(json.count).littleEndian
        withUnsafeBytes(of: &len) { header.append(contentsOf: $0) }
        header.append(json)
        return writeSparse(header, totalBytes: UInt64(header.count) + offset, name: name, in: dir)
    }

    private static func writeSparse(_ header: Data, totalBytes: UInt64, name: String, in dir: URL) -> String {
        let url = dir.appendingPathComponent(name)
        try? header.write(to: url)
        if let fh = try? FileHandle(forWritingTo: url) {
            try? fh.truncate(atOffset: max(totalBytes, UInt64(header.count)))
            try? fh.close()
        }
        return url.path
    }

    private static func writeIfMissing(_ data: Data, name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }
    }
}
