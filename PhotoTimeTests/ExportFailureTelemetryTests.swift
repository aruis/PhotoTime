import Foundation
import Testing
@testable import PhotoTime

struct ExportFailureTelemetryTests {
    @Test
    func recordsCountsByStageAndCode() async throws {
        let storeURL = try tempStoreURL()
        let telemetry = ExportFailureTelemetry(storeURL: storeURL)

        await telemetry.record(
            ExportFailureContext(
                code: "E_IMAGE_LOAD",
                stage: .export,
                message: "asset failure",
                failedAssetNames: ["a.jpg"],
                logPath: "/tmp/log-a.render.log",
                rawDescription: "asset failure"
            )
        )
        await telemetry.record(
            ExportFailureContext(
                code: "E_IMAGE_LOAD",
                stage: .export,
                message: "asset failure",
                failedAssetNames: ["b.jpg"],
                logPath: "/tmp/log-b.render.log",
                rawDescription: "asset failure"
            )
        )
        await telemetry.record(
            ExportFailureContext(
                code: nil,
                stage: .export,
                message: "unknown",
                failedAssetNames: [],
                logPath: "",
                rawDescription: "unknown"
            )
        )
        await telemetry.record(
            ExportFailureContext(
                code: "E_PREVIEW_PIPELINE",
                stage: .preview,
                message: "preview failed",
                failedAssetNames: [],
                logPath: "",
                rawDescription: "preview failed"
            )
        )

        let snapshot = await telemetry.snapshot()
        #expect(snapshot.counts["export|E_IMAGE_LOAD"] == 2)
        #expect(snapshot.counts["export|E_UNKNOWN"] == 1)
        #expect(snapshot.counts["preview|E_PREVIEW_PIPELINE"] == 1)
    }

    @Test
    func restoresCountsFromDisk() async throws {
        let storeURL = try tempStoreURL()
        let writer = ExportFailureTelemetry(storeURL: storeURL)
        await writer.record(
            ExportFailureContext(
                code: "E_EXPORT_PIPELINE",
                stage: .export,
                message: "pipeline failed",
                failedAssetNames: [],
                logPath: "/tmp/log.render.log",
                rawDescription: "pipeline failed"
            )
        )

        let reader = ExportFailureTelemetry(storeURL: storeURL)
        let snapshot = await reader.snapshot()
        #expect(snapshot.counts["export|E_EXPORT_PIPELINE"] == 1)
    }

    private func tempStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phototime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("export-failure-stats.json")
    }
}
