import Foundation
import Testing
@testable import PhotoTime

@MainActor
struct ExportViewModelLogHandlingTests {
    @Test
    func openLatestLogCreatesFallbackForDebugFailureLog() async throws {
        let viewModel = ExportViewModel()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTime-LogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("phototime-debug-failure.render.log")
        try? FileManager.default.removeItem(at: logURL)
        viewModel.lastLogURL = logURL

        viewModel.openLatestLog()

        #expect(FileManager.default.fileExists(atPath: logURL.path))
        #expect(!viewModel.statusMessage.contains("日志文件不存在"))
    }
}
