import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTime

@Suite(.serialized)
@MainActor
struct RenderEngineSmokeTests {
    nonisolated private static let stressCounts = [30, 60, 100]
    nonisolated private static let stressRepeats = 2

    @Test
    func previewPipelineProducesImage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 3)
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.4,
            transitionDuration: 0.1,
            enableKenBurns: false
        )

        let engine = RenderEngine(settings: settings)
        let cgImage = try await engine.previewFrame(imageURLs: imageURLs)
        #expect(cgImage.width == 1280)
        #expect(cgImage.height == 720)
    }

    @Test
    func previewPipelineSupportsSeeking() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreviewSeek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 5)
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.5,
            transitionDuration: 0.1,
            enableKenBurns: false
        )

        let engine = RenderEngine(settings: settings)
        let cgImage = try await engine.previewFrame(imageURLs: imageURLs, at: 1.2)
        #expect(cgImage.width == 1280)
        #expect(cgImage.height == 720)
    }

    @Test
    func previewAfterSettingsChangeMatchesExportFirstFrame() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreviewSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 4)
        let outputURL = tempDir.appendingPathComponent("settings-consistency.mp4")
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.7,
            transitionDuration: 0.25,
            enableKenBurns: true,
            layout: LayoutSettings(horizontalMargin: 150, topMargin: 64, bottomMargin: 90, innerPadding: 22),
            plate: PlateSettings(enabled: true, height: 82, baselineOffset: 15, fontSize: 22, placement: .frame),
            canvas: CanvasSettings(backgroundGray: 0.12, paperWhite: 0.96, strokeGray: 0.78, textGray: 0.18)
        )

        let engine = RenderEngine(settings: settings)
        let preview = try await engine.previewFrame(imageURLs: imageURLs, at: 0)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }
        let exported = try Self.extractVideoFrame(url: outputURL, at: 0)
        let diff = try Self.diffStats(lhs: preview, rhs: exported)

        #expect(diff.mean <= 0.10)
        #expect(diff.p95 <= 0.30)
        #expect(diff.max <= 0.70)
    }

    @Test
    func previewFailureDoesNotBlockSubsequentExport() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreviewRecover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 3)
        let outputURL = tempDir.appendingPathComponent("recover.mp4")
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.5,
            transitionDuration: 0.1,
            enableKenBurns: false
        )

        let engine = RenderEngine(settings: settings)
        var previewFailed = false
        do {
            _ = try await engine.previewFrame(imageURLs: [], at: 0)
        } catch {
            previewFailed = true
        }
        #expect(previewFailed)

        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test(arguments: [false, true])
    func previewFramesMatchExportedFramesAtKeyTimes(enableKenBurns: Bool) async throws {
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.6,
            transitionDuration: 0.2,
            enableKenBurns: enableKenBurns
        )
        let thresholds = ConsistencyThresholds(
            mean: 0.10,
            p95: enableKenBurns ? 0.30 : 0.25,
            max: enableKenBurns ? 0.70 : 0.60
        )
        try await runPreviewExportConsistency(
            settings: settings,
            imageCount: 4,
            thresholds: thresholds,
            label: "kenBurns=\(enableKenBurns ? "on" : "off")"
        )
    }

    @Test(arguments: [0, 1, 2])
    func previewFramesMatchExportedFramesForStyleVariants(variant: Int) async throws {
        let outputSize = CGSize(width: 1280, height: 720)
        let fps: Int32 = 15
        let imageDuration = 0.6
        let transitionDuration = 0.2
        let enableKenBurns = false
        let prefetchRadius = 1
        let prefetchMaxConcurrent = 2
        let defaultLayout = LayoutSettings.default
        let defaultPlate = PlateSettings.default
        let defaultCanvas = CanvasSettings.default

        let settings: RenderSettings
        let label: String
        switch variant {
        case 0:
            settings = RenderSettings(
                outputSize: outputSize,
                fps: fps,
                imageDuration: imageDuration,
                transitionDuration: transitionDuration,
                enableKenBurns: enableKenBurns,
                prefetchRadius: prefetchRadius,
                prefetchMaxConcurrent: prefetchMaxConcurrent,
                layout: LayoutSettings(horizontalMargin: 120, topMargin: 50, bottomMargin: 72, innerPadding: 16),
                plate: PlateSettings(enabled: true, height: 76, baselineOffset: 14, fontSize: 20, placement: .frame),
                canvas: defaultCanvas
            )
            label = "compact-layout"
        case 1:
            settings = RenderSettings(
                outputSize: outputSize,
                fps: fps,
                imageDuration: imageDuration,
                transitionDuration: transitionDuration,
                enableKenBurns: enableKenBurns,
                prefetchRadius: prefetchRadius,
                prefetchMaxConcurrent: prefetchMaxConcurrent,
                layout: LayoutSettings(horizontalMargin: 180, topMargin: 72, bottomMargin: 88, innerPadding: 24),
                plate: PlateSettings(enabled: false, height: 96, baselineOffset: 18, fontSize: 26, placement: .frame),
                canvas: defaultCanvas
            )
            label = "no-plate"
        default:
            settings = RenderSettings(
                outputSize: outputSize,
                fps: fps,
                imageDuration: imageDuration,
                transitionDuration: transitionDuration,
                enableKenBurns: enableKenBurns,
                prefetchRadius: prefetchRadius,
                prefetchMaxConcurrent: prefetchMaxConcurrent,
                layout: defaultLayout,
                plate: defaultPlate,
                canvas: CanvasSettings(backgroundGray: 0.15, paperWhite: 0.95, strokeGray: 0.72, textGray: 0.25)
            )
            label = "contrast-canvas"
        }

        try await runPreviewExportConsistency(
            settings: settings,
            imageCount: 4,
            thresholds: ConsistencyThresholds(mean: 0.10, p95: 0.28, max: 0.65),
            label: label
        )
    }

    private func runPreviewExportConsistency(
        settings: RenderSettings,
        imageCount: Int,
        thresholds: ConsistencyThresholds,
        label: String
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreviewConsistency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: imageCount)
        let outputURL = tempDir.appendingPathComponent("consistency.mp4")

        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.effectiveTransitionDuration
        )

        let fps = settings.fps
        let imageDuration = settings.imageDuration
        let transitionDuration = settings.effectiveTransitionDuration
        let sampleTimes = [
            Self.alignToFrame(0, fps: fps),
            Self.alignToFrame(imageDuration - transitionDuration * 0.5, fps: fps),
            Self.alignToFrame(max(timeline.totalDuration - (1.0 / Double(fps)), 0), fps: fps)
        ]

        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }

        for time in sampleTimes {
            let preview = try await engine.previewFrame(imageURLs: imageURLs, at: time)
            let exported = try Self.extractVideoFrame(url: outputURL, at: time)
            let diff = try Self.diffStats(lhs: preview, rhs: exported)
            print(
                String(
                    format: "Preview/export consistency label=%@ t=%.3fs mean=%.4f p95=%.4f max=%.4f",
                    label,
                    time,
                    diff.mean,
                    diff.p95,
                    diff.max
                )
            )

            #expect(diff.mean <= thresholds.mean)
            #expect(diff.p95 <= thresholds.p95)
            #expect(diff.max <= thresholds.max)
        }
    }

    @Test
    func exportPipelineProducesVideoFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 6)
        let outputURL = tempDir.appendingPathComponent("smoke.mp4")

        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.4,
            transitionDuration: 0.1,
            enableKenBurns: false
        )

        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }

        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)

        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("[run:"))
        #expect(logText.contains("run id: "))
        #expect(logText.contains("input summary: "))
        #expect(logText.contains("settings output="))
        #expect(logText.contains("timing totals"))
        #expect(logText.contains("stageMs(load="))
        #expect(logText.contains("prefetchMaxConcurrent="))
        #expect(logText.contains("audio track: disabled"))
        #expect(!logText.contains("audio mux start"))
    }

    @Test
    func exportPipelineIncludesAudioTrackWhenConfigured() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeAudioSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 4)
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        try writeToneAudio(to: audioURL, duration: 2.2)
        let outputURL = tempDir.appendingPathComponent("smoke-audio.mp4")

        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.5,
            transitionDuration: 0.1,
            enableKenBurns: false,
            audioTrack: AudioTrackSettings(sourceURL: audioURL, volume: 0.8)
        )

        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }

        let asset = AVAsset(url: outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("audio track: enabled"))
        #expect(logText.contains("loop=off"))
        #expect(logText.contains("audio mux completed"))
    }

    @Test
    func exportPipelineKeepsShortAudioWithoutLoop() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeAudioNoLoop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 6)
        let audioURL = tempDir.appendingPathComponent("short-noloop.caf")
        try writeToneAudio(to: audioURL, duration: 0.35)
        let outputURL = tempDir.appendingPathComponent("smoke-audio-noloop.mp4")

        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.45,
            transitionDuration: 0.1,
            enableKenBurns: false,
            audioTrack: AudioTrackSettings(sourceURL: audioURL, volume: 1, loopEnabled: false)
        )

        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }

        let asset = AVAsset(url: outputURL)
        let videoDuration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        let audioDuration = audioTracks.first?.timeRange.duration.seconds ?? 0
        #expect(audioDuration > 0.2)
        #expect(audioDuration + 0.2 < videoDuration)

        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("loop=off"))
    }

    @Test
    func exportPipelineLoopsAudioTrackWhenEnabled() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeAudioLoop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: 6)
        let audioURL = tempDir.appendingPathComponent("short-tone.caf")
        try writeToneAudio(to: audioURL, duration: 0.35)
        let outputURL = tempDir.appendingPathComponent("smoke-audio-loop.mp4")

        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 15,
            imageDuration: 0.45,
            transitionDuration: 0.1,
            enableKenBurns: false,
            audioTrack: AudioTrackSettings(sourceURL: audioURL, volume: 1, loopEnabled: true)
        )

        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }

        let asset = AVAsset(url: outputURL)
        let videoDuration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)

        let audioDuration = audioTracks.first?.timeRange.duration.seconds ?? 0
        #expect(audioDuration > 0.9)
        #expect(abs(audioDuration - videoDuration) < 0.2)

        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("loop=on"))
    }

    @Test(arguments: stressCounts)
    func exportPipelineStressSequence(imageCount: Int) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeStress-\(imageCount)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: imageCount)
        let outputURL = tempDir.appendingPathComponent("stress-\(imageCount).mp4")

        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 12,
            imageDuration: 0.10,
            transitionDuration: 0.04,
            enableKenBurns: false
        )

        let start = Date()
        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)

        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("timing totals"))
        #expect(logText.contains("stageMs(load="))

        print("Stress \(imageCount) images elapsed=\(String(format: "%.1f", elapsedMs))ms outputBytes=\(size)")
    }

    @Test
    func exportPipelineStressReport() async throws {
        var runs: [StressRunResult] = []
        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeStressReports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
        let reportURL = reportDir.appendingPathComponent("latest-stress-report.json")
        let previousReport = try Self.loadStressReport(at: reportURL)

        for imageCount in Self.stressCounts {
            for attempt in 1...Self.stressRepeats {
                let run = try await runStressExport(imageCount: imageCount, attempt: attempt)
                runs.append(run)
                print(
                    "Stress report run count=\(imageCount) attempt=\(attempt) elapsed=\(String(format: "%.1f", run.elapsedMs))ms wall=\(String(format: "%.1f", run.timingTotals.wallMs))ms"
                )
            }
        }

        let summaries = Self.stressCounts.map { count -> StressSummary in
            let matching = runs.filter { $0.imageCount == count }
            let elapsedSamples = matching.map(\.elapsedMs)
            let wallSamples = matching.map(\.timingTotals.wallMs)
            return StressSummary(
                imageCount: count,
                runs: matching.count,
                elapsedAvgMs: Self.average(elapsedSamples),
                elapsedP95Ms: Self.p95(elapsedSamples),
                wallAvgMs: Self.average(wallSamples),
                wallP95Ms: Self.p95(wallSamples)
            )
        }

        let comparisons = Self.makeComparisons(current: summaries, previous: previousReport?.summaries ?? [])
        let thresholds = StressRegressionThresholds.default
        let regressionSummaries = Self.makeRegressionSummaries(
            comparisons: comparisons,
            thresholds: thresholds
        )
        let report = StressReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            repeatsPerCount: Self.stressRepeats,
            runs: runs,
            summaries: summaries,
            comparisonToPrevious: StressComparison(
                previousGeneratedAt: previousReport?.generatedAt,
                summaries: comparisons
            ),
            regressionGate: StressRegressionGate(
                thresholds: thresholds,
                summaries: regressionSummaries
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: reportURL, options: .atomic)

        let reportText = String(decoding: data, as: UTF8.self)
        print("Stress report path: \(reportURL.path)")
        print(reportText)
        print(Self.humanReadableSummary(summaries))
        print(Self.humanReadableComparison(comparisons, previousGeneratedAt: previousReport?.generatedAt))
        print(
            Self.humanReadableRegressionGate(
                regressionSummaries,
                thresholds: thresholds,
                previousGeneratedAt: previousReport?.generatedAt
            )
        )

        #expect(FileManager.default.fileExists(atPath: reportURL.path))
        #expect(!runs.isEmpty)
        #expect(summaries.count == Self.stressCounts.count)
        #expect(summaries.allSatisfy { $0.elapsedAvgMs > 0 && $0.wallAvgMs > 0 })
    }

    private func makeTestImages(in dir: URL, count: Int) throws -> [URL] {
        var urls: [URL] = []
        urls.reserveCapacity(count)

        for index in 0..<count {
            let url = dir.appendingPathComponent("img-\(index).png")
            try writeImage(to: url, index: index)
            urls.append(url)
        }

        return urls
    }

    private func writeImage(to url: URL, index: Int) throws {
        let width = 2400
        let height = 1600

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 1)
        }

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.15, 0.35, 0.75),
            (0.75, 0.25, 0.25),
            (0.18, 0.62, 0.32),
            (0.78, 0.55, 0.22)
        ]
        let color = colors[index % colors.count]
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        context.setLineWidth(16)
        context.stroke(CGRect(x: 80, y: 80, width: width - 160, height: height - 160))

        guard let image = context.makeImage() else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 2)
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 3)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 4)
        }
    }

    private func writeToneAudio(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 30)
        }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 31)
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 32)
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

    private func runStressExport(imageCount: Int, attempt: Int) async throws -> StressRunResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeStressReport-\(imageCount)-\(attempt)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURLs = try makeTestImages(in: tempDir, count: imageCount)
        let outputURL = tempDir.appendingPathComponent("stress-report-\(imageCount)-\(attempt).mp4")
        let settings = RenderSettings(
            outputSize: CGSize(width: 1280, height: 720),
            fps: 12,
            imageDuration: 0.10,
            transitionDuration: 0.04,
            enableKenBurns: false
        )

        let start = Date()
        let engine = RenderEngine(settings: settings)
        try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { _ in }
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let logURL = outputURL.deletingPathExtension().appendingPathExtension("render.log")
        let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        #expect(logText.contains("timing totals"))
        #expect(logText.contains("stageMs(load="))

        let totals = try parseTimingTotals(logText)
        return StressRunResult(
            imageCount: imageCount,
            attempt: attempt,
            elapsedMs: elapsedMs,
            timingTotals: totals
        )
    }

    private func parseTimingTotals(_ logText: String) throws -> TimingTotals {
        let pattern = #"timing totals frames=(\d+) wall=([0-9.]+)ms load=([0-9.]+)ms compose=([0-9.]+)ms encode=([0-9.]+)ms"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(logText.startIndex..<logText.endIndex, in: logText)
        guard let match = regex.matches(in: logText, options: [], range: range).last else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "missing timing totals"])
        }

        func double(at index: Int) throws -> Double {
            let captureRange = match.range(at: index)
            guard
                captureRange.location != NSNotFound,
                let swiftRange = Range(captureRange, in: logText),
                let value = Double(logText[swiftRange])
            else {
                throw NSError(domain: "RenderEngineSmokeTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "invalid timing totals capture"])
            }
            return value
        }

        return TimingTotals(
            wallMs: try double(at: 2),
            loadMs: try double(at: 3),
            composeMs: try double(at: 4),
            encodeMs: try double(at: 5)
        )
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func p95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = Int(ceil(Double(sorted.count) * 0.95)) - 1
        let index = max(0, min(position, sorted.count - 1))
        return sorted[index]
    }

    private static func alignToFrame(_ second: TimeInterval, fps: Int32) -> TimeInterval {
        let frame = (second * Double(fps)).rounded()
        return frame / Double(fps)
    }

    private static func extractVideoFrame(url: URL, at second: TimeInterval) throws -> CGImage {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: second, preferredTimescale: 600)
        return try generator.copyCGImage(at: time, actualTime: nil)
    }

    private static func diffStats(lhs: CGImage, rhs: CGImage) throws -> ImageDiffStats {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "image size mismatch"])
        }

        let lhsBytes = try rgbaBytes(from: lhs)
        let rhsBytes = try rgbaBytes(from: rhs)
        guard lhsBytes.count == rhsBytes.count else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "image byte size mismatch"])
        }

        var channelDiffs: [Double] = []
        channelDiffs.reserveCapacity((lhs.width * lhs.height) * 3)

        for index in stride(from: 0, to: lhsBytes.count, by: 4) {
            let dr = abs(Int(lhsBytes[index]) - Int(rhsBytes[index]))
            let dg = abs(Int(lhsBytes[index + 1]) - Int(rhsBytes[index + 1]))
            let db = abs(Int(lhsBytes[index + 2]) - Int(rhsBytes[index + 2]))
            channelDiffs.append(Double(dr) / 255.0)
            channelDiffs.append(Double(dg) / 255.0)
            channelDiffs.append(Double(db) / 255.0)
        }

        let mean = channelDiffs.reduce(0, +) / Double(channelDiffs.count)
        let maxDiff = channelDiffs.max() ?? 0
        return ImageDiffStats(mean: mean, p95: p95(channelDiffs), max: maxDiff)
    }

    private static func rgbaBytes(from image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "RenderEngineSmokeTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "cannot create compare context"])
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func humanReadableSummary(_ summaries: [StressSummary]) -> String {
        let header = "Stress Summary (ms): count | elapsed avg/p95 | wall avg/p95"
        let lines = summaries
            .sorted { $0.imageCount < $1.imageCount }
            .map {
                String(
                    format: "%3d | %8.1f / %8.1f | %8.1f / %8.1f",
                    $0.imageCount,
                    $0.elapsedAvgMs,
                    $0.elapsedP95Ms,
                    $0.wallAvgMs,
                    $0.wallP95Ms
                )
            }
        return ([header] + lines).joined(separator: "\n")
    }

    private static func humanReadableComparison(_ comparisons: [StressSummaryComparison], previousGeneratedAt: String?) -> String {
        guard !comparisons.isEmpty else {
            return "Stress Delta (%): no previous report found"
        }

        let previous = previousGeneratedAt ?? "unknown"
        let header = "Stress Delta (% vs previous @ \(previous)): count | elapsed avg/p95 | wall avg/p95"
        let lines = comparisons
            .sorted { $0.imageCount < $1.imageCount }
            .map {
                String(
                    format: "%3d | %+8.2f / %+8.2f | %+8.2f / %+8.2f",
                    $0.imageCount,
                    $0.elapsedAvgChangePercent,
                    $0.elapsedP95ChangePercent,
                    $0.wallAvgChangePercent,
                    $0.wallP95ChangePercent
                )
            }
        return ([header] + lines).joined(separator: "\n")
    }

    private static func humanReadableRegressionGate(
        _ summaries: [StressRegressionSummary],
        thresholds: StressRegressionThresholds,
        previousGeneratedAt: String?
    ) -> String {
        guard !summaries.isEmpty else {
            return "Stress Regression Gate: no previous report found"
        }

        let previous = previousGeneratedAt ?? "unknown"
        let header = String(
            format: "Stress Regression Gate (vs previous @ %@): elapsed avg<=%.1f%% p95<=%.1f%% | wall avg<=%.1f%% p95<=%.1f%%",
            previous,
            thresholds.elapsedAvgMaxIncreasePercent,
            thresholds.elapsedP95MaxIncreasePercent,
            thresholds.wallAvgMaxIncreasePercent,
            thresholds.wallP95MaxIncreasePercent
        )

        let lines = summaries
            .sorted { $0.imageCount < $1.imageCount }
            .map { summary in
                if summary.withinBudget {
                    return "\(summary.imageCount): OK"
                }
                let reasons = summary.triggeredMetrics.joined(separator: ",")
                return "\(summary.imageCount): REGRESSION [\(reasons)]"
            }

        return ([header] + lines).joined(separator: "\n")
    }

    private static func loadStressReport(at url: URL) throws -> StressReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(StressReport.self, from: data)
    }

    private static func makeComparisons(current: [StressSummary], previous: [StressSummary]) -> [StressSummaryComparison] {
        let previousByCount = Dictionary(uniqueKeysWithValues: previous.map { ($0.imageCount, $0) })
        return current.compactMap { currentSummary in
            guard let previousSummary = previousByCount[currentSummary.imageCount] else { return nil }
            return StressSummaryComparison(
                imageCount: currentSummary.imageCount,
                elapsedAvgChangePercent: percentChange(current: currentSummary.elapsedAvgMs, previous: previousSummary.elapsedAvgMs),
                elapsedP95ChangePercent: percentChange(current: currentSummary.elapsedP95Ms, previous: previousSummary.elapsedP95Ms),
                wallAvgChangePercent: percentChange(current: currentSummary.wallAvgMs, previous: previousSummary.wallAvgMs),
                wallP95ChangePercent: percentChange(current: currentSummary.wallP95Ms, previous: previousSummary.wallP95Ms)
            )
        }
    }

    private static func makeRegressionSummaries(
        comparisons: [StressSummaryComparison],
        thresholds: StressRegressionThresholds
    ) -> [StressRegressionSummary] {
        comparisons.map { item in
            var triggered: [String] = []
            if item.elapsedAvgChangePercent > thresholds.elapsedAvgMaxIncreasePercent {
                triggered.append("elapsedAvg")
            }
            if item.elapsedP95ChangePercent > thresholds.elapsedP95MaxIncreasePercent {
                triggered.append("elapsedP95")
            }
            if item.wallAvgChangePercent > thresholds.wallAvgMaxIncreasePercent {
                triggered.append("wallAvg")
            }
            if item.wallP95ChangePercent > thresholds.wallP95MaxIncreasePercent {
                triggered.append("wallP95")
            }

            return StressRegressionSummary(
                imageCount: item.imageCount,
                withinBudget: triggered.isEmpty,
                triggeredMetrics: triggered
            )
        }
    }

    private static func percentChange(current: Double, previous: Double) -> Double {
        guard previous != 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }
}

private struct TimingTotals: Codable {
    let wallMs: Double
    let loadMs: Double
    let composeMs: Double
    let encodeMs: Double
}

private struct StressRunResult: Codable {
    let imageCount: Int
    let attempt: Int
    let elapsedMs: Double
    let timingTotals: TimingTotals
}

private struct StressSummary: Codable {
    let imageCount: Int
    let runs: Int
    let elapsedAvgMs: Double
    let elapsedP95Ms: Double
    let wallAvgMs: Double
    let wallP95Ms: Double
}

private struct StressReport: Codable {
    let generatedAt: String
    let repeatsPerCount: Int
    let runs: [StressRunResult]
    let summaries: [StressSummary]
    let comparisonToPrevious: StressComparison?
    let regressionGate: StressRegressionGate?
}

private struct ImageDiffStats {
    let mean: Double
    let p95: Double
    let max: Double
}

private struct ConsistencyThresholds {
    let mean: Double
    let p95: Double
    let max: Double
}

private struct StressComparison: Codable {
    let previousGeneratedAt: String?
    let summaries: [StressSummaryComparison]
}

private struct StressSummaryComparison: Codable {
    let imageCount: Int
    let elapsedAvgChangePercent: Double
    let elapsedP95ChangePercent: Double
    let wallAvgChangePercent: Double
    let wallP95ChangePercent: Double
}

private struct StressRegressionGate: Codable {
    let thresholds: StressRegressionThresholds
    let summaries: [StressRegressionSummary]
}

private struct StressRegressionThresholds: Codable {
    let elapsedAvgMaxIncreasePercent: Double
    let elapsedP95MaxIncreasePercent: Double
    let wallAvgMaxIncreasePercent: Double
    let wallP95MaxIncreasePercent: Double

    static let `default` = StressRegressionThresholds(
        elapsedAvgMaxIncreasePercent: 20,
        elapsedP95MaxIncreasePercent: 25,
        wallAvgMaxIncreasePercent: 20,
        wallP95MaxIncreasePercent: 25
    )
}

private struct StressRegressionSummary: Codable {
    let imageCount: Int
    let withinBudget: Bool
    let triggeredMetrics: [String]
}
