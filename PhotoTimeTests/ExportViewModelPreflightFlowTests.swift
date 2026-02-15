import CoreGraphics
import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTime

@MainActor
struct ExportViewModelPreflightFlowTests {
    @Test
    func viewModelHasDefaultOutputURLOnInit() async throws {
        let viewModel = ExportViewModel()
        #expect(viewModel.outputURL != nil)
        #expect(viewModel.outputURL?.pathExtension.lowercased() == "mp4")
    }

    @Test
    func flowStepMarksOutputReadyWhenDefaultPathExists() async throws {
        let viewModel = ExportViewModel()
        let outputStep = viewModel.flowSteps.first { $0.id == "select-output" }

        #expect(outputStep != nil)
        #expect(outputStep?.done == true)
    }

    @Test
    func firstRunHintAllowsDirectExportWithoutPreview() async throws {
        let viewModel = ExportViewModel()
        viewModel.imageURLs = [URL(fileURLWithPath: "/tmp/demo.jpg")]

        #expect(viewModel.hasOutputPath == true)
        #expect(viewModel.hasPreviewFrame == false)
        #expect(viewModel.nextActionHint.contains("直接导出 MP4") == true)

        let previewStep = viewModel.flowSteps.first { $0.id == "preview" }
        #expect(previewStep?.title.contains("可选") == true)
        #expect(previewStep?.done == true)
    }

    @Test
    func startAudioPreviewFailsWhenAudioDisabled() async throws {
        let viewModel = ExportViewModel()
        viewModel.config.audioEnabled = false
        viewModel.config.audioFilePath = "/tmp/a.m4a"

        let started = viewModel.startAudioPreview()

        #expect(started == false)
        #expect(viewModel.isAudioPreviewPlaying == false)
        #expect(viewModel.audioStatusMessage?.contains("启用背景音频") == true)
    }

    @Test
    func startAudioPreviewFailsWhenFileMissing() async throws {
        let viewModel = ExportViewModel()
        viewModel.config.audioEnabled = true
        viewModel.config.audioFilePath = "/tmp/not-exists-\(UUID().uuidString).m4a"

        let started = viewModel.startAudioPreview()

        #expect(started == false)
        #expect(viewModel.isAudioPreviewPlaying == false)
        #expect(viewModel.audioStatusMessage?.contains("不存在") == true)
    }

    @Test
    func importDroppedAudioTrackAcceptsValidAudio() async throws {
        let viewModel = ExportViewModel()
        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("bgm.m4a")
        try Data([1, 2, 3]).write(to: audioURL, options: .atomic)

        let imported = viewModel.importDroppedAudioTrack([audioURL])

        #expect(imported == true)
        #expect(viewModel.config.audioEnabled == true)
        #expect(viewModel.config.audioFilePath == audioURL.path)
        #expect(viewModel.audioStatusMessage?.contains("音频已就绪") == true)
    }

    @Test
    func selectedAudioDurationLoadsAfterValidImport() async throws {
        let viewModel = ExportViewModel()
        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("tone.caf")
        try Self.writeToneAudio(to: audioURL, duration: 0.45)

        let imported = viewModel.importDroppedAudioTrack([audioURL])

        #expect(imported == true)
        try await Self.waitUntil {
            await MainActor.run { viewModel.selectedAudioDuration != nil }
        }
        #expect((viewModel.selectedAudioDuration ?? 0) > 0.3)
    }

    @Test
    func selectedAudioDurationClearsAfterRemovingTrack() async throws {
        let viewModel = ExportViewModel()
        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("tone.caf")
        try Self.writeToneAudio(to: audioURL, duration: 0.45)

        let imported = viewModel.importDroppedAudioTrack([audioURL])
        #expect(imported == true)
        try await Self.waitUntil {
            await MainActor.run { viewModel.selectedAudioDuration != nil }
        }

        viewModel.clearAudioTrack()
        #expect(viewModel.selectedAudioDuration == nil)
    }

    @Test
    func importDroppedAudioTrackRejectsInvalidFile() async throws {
        let viewModel = ExportViewModel()
        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let textURL = tempDir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: textURL, options: .atomic)

        let imported = viewModel.importDroppedAudioTrack([textURL])

        #expect(imported == false)
        #expect(viewModel.config.audioEnabled == false)
        #expect(viewModel.config.audioFilePath.isEmpty)
        #expect(viewModel.audioStatusMessage?.contains("音频") == true)
    }

    @Test
    func exportBlocksWhenPreflightHasMustFixIssues() async throws {
        let recorder = ExportCallRecorder()
        let engine = TestRenderingEngine(recorder: recorder)
        let viewModel = ExportViewModel(makeEngine: { _ in engine })

        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingURL = tempDir.appendingPathComponent("missing.jpg")
        let outputURL = tempDir.appendingPathComponent("out.mp4")
        viewModel.imageURLs = [missingURL]
        viewModel.outputURL = outputURL

        viewModel.export()

        #expect(viewModel.preflightReport?.hasBlockingIssues == true)
        #expect(viewModel.statusMessage.contains("必须修复"))
        #expect(!viewModel.isExporting)
        #expect(await recorder.exportCallCount() == 0)
    }

    @Test
    func exportContinuesWhenPreflightHasOnlyReviewIssues() async throws {
        let recorder = ExportCallRecorder()
        let engine = TestRenderingEngine(recorder: recorder)
        let viewModel = ExportViewModel(makeEngine: { _ in engine })

        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lowResURL = tempDir.appendingPathComponent("low.png")
        try Self.writeImage(to: lowResURL, width: 200, height: 200)
        let outputURL = tempDir.appendingPathComponent("out.mp4")
        viewModel.imageURLs = [lowResURL]
        viewModel.outputURL = outputURL

        viewModel.export()
        try await Self.waitUntil {
            await recorder.exportCallCount() == 1
        }

        #expect(viewModel.preflightReport?.hasBlockingIssues == false)
        #expect(await recorder.lastExportImageNames() == ["low.png"])
    }

    @Test
    func exportBlocksWhenOutputPathIsNotWritable() async throws {
        let recorder = ExportCallRecorder()
        let engine = TestRenderingEngine(recorder: recorder)
        let viewModel = ExportViewModel(makeEngine: { _ in engine })

        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("good.png")
        try Self.writeImage(to: imageURL, width: 1200, height: 800)
        viewModel.imageURLs = [imageURL]
        viewModel.outputURL = URL(fileURLWithPath: "/System/Library/PhotoTime-Blocked-\(UUID().uuidString).mp4")

        viewModel.export()

        #expect(viewModel.statusMessage.contains("导出路径不可写"))
        #expect(await recorder.exportCallCount() == 0)
    }

    @Test
    func skipPreflightIssuesExportsOnlyNonBlockingAssets() async throws {
        let recorder = ExportCallRecorder()
        let engine = TestRenderingEngine(recorder: recorder)
        let viewModel = ExportViewModel(makeEngine: { _ in engine })

        let tempDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingURL = tempDir.appendingPathComponent("missing.jpg")
        let goodURL = tempDir.appendingPathComponent("good.png")
        try Self.writeImage(to: goodURL, width: 1200, height: 800)
        let outputURL = tempDir.appendingPathComponent("out.mp4")
        viewModel.imageURLs = [missingURL, goodURL]
        viewModel.outputURL = outputURL

        viewModel.export()
        #expect(viewModel.preflightReport?.hasBlockingIssues == true)
        #expect(await recorder.exportCallCount() == 0)

        viewModel.exportSkippingPreflightIssues()
        try await Self.waitUntil {
            await recorder.exportCallCount() == 1
        }

        #expect(await recorder.lastExportImageNames() == ["good.png"])
        #expect(viewModel.skippedAssetNamesFromPreflight == ["missing.jpg"])
    }

    private static func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeVMPreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private static func writeImage(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 1)
        }

        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 2)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 4)
        }
    }

    private static func writeToneAudio(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 30)
        }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 31)
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 32)
        }

        let frequency = 440.0
        let amplitude: Float = 0.2
        for index in 0..<Int(frameCount) {
            let t = Double(index) / sampleRate
            channelData[index] = sin(2.0 * .pi * frequency * t).isFinite
                ? Float(sin(2.0 * .pi * frequency * t)) * amplitude
                : 0
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        stepNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while true {
            if await condition() {
                return
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if now - start >= timeoutNanoseconds {
                throw NSError(domain: "ExportViewModelPreflightFlowTests", code: 5)
            }
            try await Task.sleep(nanoseconds: stepNanoseconds)
        }
    }
}

private actor ExportCallRecorder {
    private var exportCalls: [[URL]] = []

    func recordExportCall(imageURLs: [URL]) {
        exportCalls.append(imageURLs)
    }

    func exportCallCount() -> Int {
        exportCalls.count
    }

    func lastExportImageNames() -> [String] {
        exportCalls.last?.map(\.lastPathComponent) ?? []
    }
}

private final class TestRenderingEngine: RenderingEngineClient {
    private let recorder: ExportCallRecorder

    init(recorder: ExportCallRecorder) {
        self.recorder = recorder
    }

    func export(
        imageURLs: [URL],
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        await recorder.recordExportCall(imageURLs: imageURLs)
        progress(1)
    }

    func previewFrame(imageURLs: [URL], at second: TimeInterval) async throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "TestRenderingEngine", code: 1)
        }
        return image
    }
}
