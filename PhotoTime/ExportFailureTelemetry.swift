import Foundation

struct ExportFailureStatsSnapshot: Sendable {
    var updatedAt: Date
    var counts: [String: Int]
}

actor ExportFailureTelemetry {
    static let shared = ExportFailureTelemetry(storeURL: defaultStoreURL())

    private let storeURL: URL
    private var counts: [String: Int]

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.counts = Self.loadCounts(from: storeURL)
    }

    func record(_ context: ExportFailureContext) {
        let key = Self.makeKey(stage: context.stage, code: context.code)
        counts[key, default: 0] += 1
        persist()
    }

    func snapshot() -> ExportFailureStatsSnapshot {
        ExportFailureStatsSnapshot(updatedAt: Date(), counts: counts)
    }

    nonisolated static func defaultStoreURL() -> URL {
        let base = (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        )
        let dir = base.appendingPathComponent("PhotoTime/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("export-failure-stats.json")
    }

    private func persist() {
        let payload: [String: Any] = [
            "updatedAt": Date().timeIntervalSince1970,
            "counts": counts
        ]
        guard JSONSerialization.isValidJSONObject(payload) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: storeURL, options: .atomic)
    }

    nonisolated private static func makeKey(stage: ExportFailureStage, code: String?) -> String {
        let normalizedCode = code ?? "E_UNKNOWN"
        return "\(stage.rawValue)|\(normalizedCode)"
    }

    nonisolated private static func loadCounts(from url: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        guard let rawCounts = payload["counts"] as? [String: Any] else { return [:] }

        var parsed: [String: Int] = [:]
        parsed.reserveCapacity(rawCounts.count)
        for (key, value) in rawCounts {
            if let intValue = value as? Int {
                parsed[key] = intValue
            } else if let number = value as? NSNumber {
                parsed[key] = number.intValue
            }
        }
        return parsed
    }
}
