import AVFoundation
import CoreImage
import CoreVideo
import Foundation

enum VideoExporterError: LocalizedError {
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case missingPixelBufferPool
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter:
            return "无法创建 AVAssetWriter"
        case .cannotCreatePixelBuffer:
            return "无法创建像素缓冲区"
        case .missingPixelBufferPool:
            return "无法获取像素缓冲区池"
        case .writerFailed(let message):
            return "视频导出失败: \(message)"
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
        clips: [ComposedClip],
        timeline: TimelineEngine,
        composer: FrameComposer,
        to outputURL: URL,
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

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let frameTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            let second = Double(frameIndex) / Double(fps)
            let snapshot = timeline.snapshot(at: second)
            let image = composer.composeFrame(clips: clips, timelineLayers: snapshot.layers)

            try append(image: image, at: frameTime, adaptor: adaptor, writer: writer)
            progress(Double(frameIndex + 1) / Double(totalFrames))
        }

        input.markAsFinished()

        await writer.finishWriting()
        if let error = writer.error {
            throw VideoExporterError.writerFailed(error.localizedDescription)
        }
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
