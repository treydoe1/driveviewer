import Foundation

struct DiskCapacity {
    let total: Int64
    let available: Int64

    static func startupDisk() -> DiskCapacity? {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskCapacity(total: Int64(total), available: max(0, available))
    }

    var availablePercent: Double {
        min(100, max(0, Double(available) * 100 / Double(total)))
    }

    var percentLabel: String { String(format: "%.1f%%", availablePercent) }
}
