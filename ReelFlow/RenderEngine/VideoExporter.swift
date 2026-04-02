import AVFoundation
import CoreImage
import CoreVideo
import Dispatch
import Foundation

enum VideoExporterError: LocalizedError {
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case missingPixelBufferPool
    case cancelled
    case writerFailed(String)
    case assetLoadFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter:
            return "无法创建 AVAssetWriter"
        case .cannotCreatePixelBuffer:
            return "无法创建像素缓冲区"
        case .missingPixelBufferPool:
            return "无法获取像素缓冲区池"
        case .cancelled:
            return "导出已取消"
        case .writerFailed(let message):
            return "视频导出失败: \(message)"
        case .assetLoadFailed(let index, let message):
            return "素材加载失败(index=\(index)): \(message)"
        }
    }
}

final class VideoExporter {
    private let settings: RenderSettings
    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    nonisolated init(settings: RenderSettings) {
        self.settings = settings
    }

    nonisolated func export(
        sourceURLs: [URL],
        targetMaxDimension: Int,
        timeline: TimelineEngine,
        composer: FrameComposer,
        to outputURL: URL,
        logger: RenderLogger,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw VideoExporterError.cannotCreateWriter
        }

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(settings.outputSize.width),
            AVVideoHeightKey: Int(settings.outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: Int(settings.fps)
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(settings.outputSize.width),
            kCVPixelBufferHeightKey as String: Int(settings.outputSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.canAdd(input) else {
            throw VideoExporterError.cannotCreateWriter
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = settings.fps
        let totalFrames = Int((timeline.totalDuration * TimeInterval(fps)).rounded(.up))
        let frameDuration = CMTime(value: 1, timescale: fps)
        let metricInterval = max(Int(fps), 1)
        let progressInterval = max(Int(fps / 4), 1)
        let assetProvider = AssetProvider(
            urls: sourceURLs,
            targetMaxDimension: targetMaxDimension,
            logger: logger,
            capacity: 4,
            prefetchMaxConcurrent: settings.prefetchMaxConcurrent
        )
        let clipCache = ClipCache(provider: assetProvider, composer: composer, capacity: 3)
        await logger.log(
            "video export started: fps=\(fps), totalFrames=\(totalFrames), prefetchRadius=\(settings.prefetchRadius), prefetchMaxConcurrent=\(settings.prefetchMaxConcurrent)"
        )

        var loadStageNanos: UInt64 = 0
        var composeStageNanos: UInt64 = 0
        var encodeStageNanos: UInt64 = 0
        let exportStartNanos = DispatchTime.now().uptimeNanoseconds

        for frameIndex in 0..<totalFrames {
            if Task.isCancelled {
                writer.cancelWriting()
                await logger.log("cancelled at frame \(frameIndex)")
                throw VideoExporterError.cancelled
            }

            while !input.isReadyForMoreMediaData {
                if Task.isCancelled {
                    writer.cancelWriting()
                    await logger.log("cancelled while waiting writer at frame \(frameIndex)")
                    throw VideoExporterError.cancelled
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let frameTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            let second = Double(frameIndex) / Double(fps)
            let snapshot = timeline.snapshot(at: second)
            if settings.prefetchRadius > 0, let maxClipIndex = snapshot.layers.map(\.clipIndex).max() {
                await assetProvider.prefetch(around: maxClipIndex, radius: settings.prefetchRadius)
            }

            let loadStart = DispatchTime.now().uptimeNanoseconds
            var layerClips: [(TimelineLayer, ComposedClip)] = []
            layerClips.reserveCapacity(snapshot.layers.count)
            for layer in snapshot.layers {
                do {
                    let clip = try await clipCache.clip(for: layer.clipIndex)
                    layerClips.append((layer, clip))
                } catch {
                    await logger.log("clip build failed at index \(layer.clipIndex): \(error.localizedDescription)")
                    throw VideoExporterError.assetLoadFailed(layer.clipIndex, error.localizedDescription)
                }
            }
            loadStageNanos &+= DispatchTime.now().uptimeNanoseconds &- loadStart

            let composeStart = DispatchTime.now().uptimeNanoseconds
            let image = composer.composeFrame(layerClips: layerClips)
            composeStageNanos &+= DispatchTime.now().uptimeNanoseconds &- composeStart

            if frameIndex.isMultiple(of: metricInterval) || frameIndex == totalFrames - 1 {
                let assetCached = await assetProvider.cachedCount
                let clipCached = await clipCache.cachedCount
                let inFlightLoads = await assetProvider.inFlightCount
                let loadAvg = Self.millis(from: loadStageNanos, frames: frameIndex + 1)
                let composeAvg = Self.millis(from: composeStageNanos, frames: frameIndex + 1)
                let encodeAvg = Self.millis(from: encodeStageNanos, frames: frameIndex + 1)
                if let snapshot = MemoryProbe.current() {
                    await logger.log(
                        String(
                            format: "metrics frame=%d/%d rss=%.1fMB assetCache=%d clipCache=%d inFlight=%d stageMs(load=%.2f compose=%.2f encode=%.2f)",
                            frameIndex + 1,
                            totalFrames,
                            snapshot.residentSizeMB,
                            assetCached,
                            clipCached,
                            inFlightLoads,
                            loadAvg,
                            composeAvg,
                            encodeAvg
                        )
                    )
                } else {
                    await logger.log(
                        String(
                            format: "metrics frame=%d/%d assetCache=%d clipCache=%d inFlight=%d stageMs(load=%.2f compose=%.2f encode=%.2f)",
                            frameIndex + 1,
                            totalFrames,
                            assetCached,
                            clipCached,
                            inFlightLoads,
                            loadAvg,
                            composeAvg,
                            encodeAvg
                        )
                    )
                }
            }

            do {
                let encodeStart = DispatchTime.now().uptimeNanoseconds
                try append(image: image, at: frameTime, adaptor: adaptor, writer: writer)
                encodeStageNanos &+= DispatchTime.now().uptimeNanoseconds &- encodeStart
            } catch {
                await logger.log("append failed at frame \(frameIndex): \(error.localizedDescription)")
                throw VideoExporterError.writerFailed("frame \(frameIndex): \(error.localizedDescription)")
            }
            if frameIndex.isMultiple(of: progressInterval) || frameIndex == totalFrames - 1 {
                progress(Double(frameIndex + 1) / Double(totalFrames))
            }
        }

        input.markAsFinished()

        if Task.isCancelled {
            writer.cancelWriting()
            await logger.log("cancelled before finishWriting")
            throw VideoExporterError.cancelled
        }

        await writer.finishWriting()
        if let error = writer.error {
            await logger.log("finishWriting failed: \(error.localizedDescription)")
            throw VideoExporterError.writerFailed(error.localizedDescription)
        }
        let wallClockNanos = DispatchTime.now().uptimeNanoseconds &- exportStartNanos
        await logger.log(
            String(
                format: "timing totals frames=%d wall=%.2fms load=%.2fms compose=%.2fms encode=%.2fms",
                totalFrames,
                Self.millis(from: wallClockNanos),
                Self.millis(from: loadStageNanos),
                Self.millis(from: composeStageNanos),
                Self.millis(from: encodeStageNanos)
            )
        )
        await logger.log("finishWriting completed")
    }

    nonisolated private static func millis(from nanos: UInt64, frames: Int? = nil) -> Double {
        guard nanos > 0 else { return 0 }
        let total = Double(nanos) / 1_000_000.0
        guard let frames, frames > 0 else { return total }
        return total / Double(frames)
    }

    nonisolated private func append(
        image: CIImage,
        at presentationTime: CMTime,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        writer: AVAssetWriter
    ) throws {
        guard let pool = adaptor.pixelBufferPool else {
            throw VideoExporterError.missingPixelBufferPool
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard let pixelBuffer else {
            throw VideoExporterError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        ciContext.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: settings.outputSize),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            throw VideoExporterError.writerFailed(writer.error?.localizedDescription ?? "append failed")
        }
    }
}
