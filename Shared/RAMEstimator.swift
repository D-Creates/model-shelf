import Foundation

/// Estimated RAM need and the fits/tight/too-big badge vs the device RAM.
public enum RAMEstimator {

    /// Overhead on top of raw weight bytes (allocator slack, mmap pages).
    public static let overheadFactor: Double = 1.05

    /// Fraction of device RAM at or below which a model counts as "fits".
    public static let fitsThreshold: Double = 0.50
    /// Fraction of device RAM at or below which a model counts as "tight".
    public static let tightThreshold: Double = 0.85

    /// Estimated RAM need = weight bytes plus overhead.
    public static func estimate(weightBytes: UInt64) -> UInt64 {
        UInt64(Double(weightBytes) * overheadFactor)
    }

    /// Badge for an estimated RAM need on a device with `deviceRAM` bytes.
    public static func badge(estimatedBytes: UInt64,
                             deviceRAM: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Badge {
        guard deviceRAM > 0 else { return .tooBig }
        let e = Double(estimatedBytes)
        let r = Double(deviceRAM)
        if e <= r * fitsThreshold { return .fits }
        if e <= r * tightThreshold { return .tight }
        return .tooBig
    }
}
