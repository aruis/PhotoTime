import Foundation

struct DiagnosticsBundleInput {
    let destinationRoot: URL
    let statsFileURL: URL
    let logsDirectoryURL: URL
    let latestLogURL: URL?
    let configSnapshotLines: [String]
}

enum DiagnosticsBundleBuilder {
    static func createBundle(
        input: DiagnosticsBundleInput,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: input.destinationRoot, withIntermediateDirectories: true)

        let bundleDir = input.destinationRoot.appendingPathComponent("phototime-diagnostics-\(timestamp(now))", isDirectory: true)
        try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        try writeEnvironmentFile(to: bundleDir.appendingPathComponent("environment.txt"))
        try copyStatsFile(from: input.statsFileURL, to: bundleDir, fileManager: fileManager)
        try copyLatestLogs(from: input.logsDirectoryURL, to: bundleDir, fileManager: fileManager)
        try writeConfigSnapshot(
            to: bundleDir.appendingPathComponent("config-snapshot.txt"),
            lines: input.configSnapshotLines,
            latestLogURL: input.latestLogURL
        )
        try writeManifest(to: bundleDir.appendingPathComponent("manifest.txt"), bundleDir: bundleDir, fileManager: fileManager)

        return bundleDir
    }

    private static func writeEnvironmentFile(to fileURL: URL) throws {
        let processInfo = ProcessInfo.processInfo
        let os = processInfo.operatingSystemVersion
        let lines = [
            "generated_at=\(iso8601(Date()))",
            "hostname=\(processInfo.hostName)",
            "os=macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "process=\(processInfo.processName)",
            "pid=\(processInfo.processIdentifier)"
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func copyStatsFile(from sourceURL: URL, to bundleDir: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: sourceURL.path) {
            let target = bundleDir.appendingPathComponent("export-failure-stats.json")
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: sourceURL, to: target)
            return
        }

        let missing = bundleDir.appendingPathComponent("export-failure-stats.missing.txt")
        try "stats file not found: \(sourceURL.path)\n".write(to: missing, atomically: true, encoding: .utf8)
    }

    private static func copyLatestLogs(from logsDirectoryURL: URL, to bundleDir: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: logsDirectoryURL.path) else {
            let missing = bundleDir.appendingPathComponent("logs.missing.txt")
            try "logs directory not found: \(logsDirectoryURL.path)\n".write(to: missing, atomically: true, encoding: .utf8)
            return
        }

        let logsOutDir = bundleDir.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsOutDir, withIntermediateDirectories: true)

        let files = try fileManager.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let renderLogs = files.filter { $0.pathExtension == "log" && $0.lastPathComponent.hasSuffix(".render.log") }
        let latestFive = renderLogs
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
            .prefix(5)

        for source in latestFive {
            let target = logsOutDir.appendingPathComponent(source.lastPathComponent)
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: source, to: target)
        }

        if latestFive.isEmpty {
            let empty = bundleDir.appendingPathComponent("logs.empty.txt")
            try "no render logs found in: \(logsDirectoryURL.path)\n".write(to: empty, atomically: true, encoding: .utf8)
        }
    }

    private static func writeConfigSnapshot(to fileURL: URL, lines: [String], latestLogURL: URL?) throws {
        var content: [String] = []
        if let latestLogURL {
            content.append("latest_log=\(latestLogURL.path)")
        } else {
            content.append("latest_log=(none)")
        }
        content.append("")
        content.append(contentsOf: lines)
        try content.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func writeManifest(to fileURL: URL, bundleDir: URL, fileManager: FileManager) throws {
        let enumerator = fileManager.enumerator(at: bundleDir, includingPropertiesForKeys: nil)
        var files: [String] = []
        while let entry = enumerator?.nextObject() as? URL {
            let path = entry.path
            guard !path.hasSuffix("/") else { continue }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                files.append(path.replacingOccurrences(of: bundleDir.path + "/", with: ""))
            }
        }
        files.sort()

        var lines: [String] = ["bundle_dir=\(bundleDir.path)", "files:"]
        lines.append(contentsOf: files)
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
