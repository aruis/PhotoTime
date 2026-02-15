import Foundation
import Testing
@testable import PhotoTime

struct DiagnosticsBundleBuilderTests {
    @Test
    func createsBundleWithStatsAndRecentLogs() throws {
        let fm = FileManager.default
        let root = try tempDir(prefix: "diag-builder")
        let destinationRoot = root.appendingPathComponent("bundles", isDirectory: true)
        let statsURL = root.appendingPathComponent("export-failure-stats.json")
        let logsDir = root.appendingPathComponent("logs", isDirectory: true)
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        try """
        {"counts":{"export|E_IMAGE_LOAD":2}}
        """.write(to: statsURL, atomically: true, encoding: .utf8)

        let oldLog = logsDir.appendingPathComponent("old.render.log")
        let newLog = logsDir.appendingPathComponent("new.render.log")
        try "old".write(to: oldLog, atomically: true, encoding: .utf8)
        try "new".write(to: newLog, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: oldLog.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newLog.path)

        let bundleURL = try DiagnosticsBundleBuilder.createBundle(
            input: DiagnosticsBundleInput(
                destinationRoot: destinationRoot,
                statsFileURL: statsURL,
                logsDirectoryURL: logsDir,
                latestLogURL: newLog,
                configSnapshotLines: ["workflow_state=failed", "image_count=3"]
            ),
            now: Date(timeIntervalSince1970: 1234)
        )

        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("environment.txt").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("export-failure-stats.json").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("logs/new.render.log").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("logs/old.render.log").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("manifest.txt").path))
        #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("config-snapshot.txt").path))
    }

    private func tempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
