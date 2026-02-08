import Foundation
import CoreImage
import CoreGraphics
import ImageIO

enum RenderEngineError: LocalizedError {
    case emptyInput
    case cancelled
    case imageLoadFailed(String)
    case assetLoadFailed(index: Int, message: String)
    case exportFailed(String)
    case previewFailed(String)

    var code: String {
        switch self {
        case .emptyInput:
            return "E_INPUT_EMPTY"
        case .cancelled:
            return "E_EXPORT_CANCELLED"
        case .imageLoadFailed, .assetLoadFailed:
            return "E_IMAGE_LOAD"
        case .exportFailed:
            return "E_EXPORT_PIPELINE"
        case .previewFailed:
            return "E_PREVIEW_PIPELINE"
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请至少选择一张图片"
        case .cancelled:
            return "导出已取消"
        case .imageLoadFailed(let message):
            return "图片加载失败: \(message)"
        case .assetLoadFailed(let index, let message):
            return "素材加载失败(index=\(index)): \(message)"
        case .exportFailed(let message):
            return "视频导出失败: \(message)"
        case .previewFailed(let message):
            return "预览生成失败: \(message)"
        }
    }
}

final class RenderEngine {
    private let settings: RenderSettings
    private let previewContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    nonisolated init(settings: RenderSettings = .mvp) {
        self.settings = settings
    }

    nonisolated func export(
        imageURLs: [URL],
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !imageURLs.isEmpty else {
            throw RenderEngineError.emptyInput
        }

        let logURL = outputURL
            .deletingPathExtension()
            .appendingPathExtension("render.log")
        let runID = UUID().uuidString
        let logger = RenderLogger(fileURL: logURL, runID: runID)
        await logger.log("start export")
        await logger.log("run id: \(runID)")
        await logger.log("input count: \(imageURLs.count)")
        await logger.log("input summary: \(Self.makeInputSummary(urls: imageURLs))")
        await logger.log("output: \(outputURL.path)")
        await logger.log(
            String(
                format: "settings output=%dx%d fps=%d imageDuration=%.2fs transition=%.2fs(%@) kenBurns=%@ prefetchRadius=%d prefetchMaxConcurrent=%d",
                Int(settings.outputSize.width),
                Int(settings.outputSize.height),
                Int(settings.fps),
                settings.imageDuration,
                settings.transitionDuration,
                settings.transitionEnabled ? settings.transitionStyle.rawValue : "off",
                settings.enableKenBurns ? "on" : "off",
                settings.prefetchRadius,
                settings.prefetchMaxConcurrent
            )
        )
        await logger.log(
            String(
                format: "layout h=%.1f top=%.1f bottom=%.1f inner=%.1f plate=%@ height=%.1f base=%.1f font=%.1f canvas(bg=%.2f paper=%.2f stroke=%.2f text=%.2f)",
                settings.layout.horizontalMargin,
                settings.layout.topMargin,
                settings.layout.bottomMargin,
                settings.layout.innerPadding,
                settings.plate.enabled ? "on" : "off",
                settings.plate.height,
                settings.plate.baselineOffset,
                settings.plate.fontSize,
                settings.canvas.backgroundGray,
                settings.canvas.paperWhite,
                settings.canvas.strokeGray,
                settings.canvas.textGray
            )
        )
        let targetMaxDimension = Int(max(settings.outputSize.width, settings.outputSize.height) * 1.4)
        await logger.log("decode max dimension: \(targetMaxDimension)")
        await logger.log("image loading mode: lazy windowed prefetch")

        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.effectiveTransitionDuration
        )
        await logger.log("timeline total duration: \(timeline.totalDuration)s")

        let composer = FrameComposer(settings: settings)

        do {
            let exporter = VideoExporter(settings: settings)
            try await exporter.export(
                sourceURLs: imageURLs,
                targetMaxDimension: targetMaxDimension,
                timeline: timeline,
                composer: composer,
                to: outputURL,
                logger: logger,
                progress: progress
            )
            await logger.log("export completed")
        } catch is CancellationError {
            await logger.log("export cancelled")
            await cleanupPartialOutput(at: outputURL, logger: logger)
            throw RenderEngineError.cancelled
        } catch VideoExporterError.cancelled {
            await logger.log("export cancelled")
            await cleanupPartialOutput(at: outputURL, logger: logger)
            throw RenderEngineError.cancelled
        } catch let error as VideoExporterError {
            await logger.log("export failed: \(error.localizedDescription)")
            await cleanupPartialOutput(at: outputURL, logger: logger)
            switch error {
            case .assetLoadFailed(let index, let message):
                throw RenderEngineError.assetLoadFailed(index: index, message: message)
            default:
                throw RenderEngineError.exportFailed(error.localizedDescription)
            }
        } catch {
            await logger.log("export failed: \(error.localizedDescription)")
            await cleanupPartialOutput(at: outputURL, logger: logger)
            throw RenderEngineError.exportFailed(error.localizedDescription)
        }
    }

    nonisolated func previewFrame(imageURLs: [URL], at second: TimeInterval = 0) async throws -> CGImage {
        guard !imageURLs.isEmpty else {
            throw RenderEngineError.emptyInput
        }

        let targetMaxDimension = Int(max(settings.outputSize.width, settings.outputSize.height) * 1.4)
        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.effectiveTransitionDuration
        )
        let composer = FrameComposer(settings: settings)

        let clampedSecond = max(0, min(second, max(timeline.totalDuration - 0.001, 0)))
        let snapshot = timeline.snapshot(at: clampedSecond)

        do {
            var layerClips: [(TimelineLayer, ComposedClip)] = []
            layerClips.reserveCapacity(snapshot.layers.count)

            for layer in snapshot.layers {
                let asset = try ImageLoader.load(url: imageURLs[layer.clipIndex], targetMaxDimension: targetMaxDimension)
                layerClips.append((layer, composer.makeClip(asset)))
            }

            let image = composer.composeFrame(layerClips: layerClips)
            guard let cgImage = previewContext.createCGImage(image, from: CGRect(origin: .zero, size: settings.outputSize)) else {
                throw RenderEngineError.previewFailed("无法创建预览图像")
            }
            return cgImage
        } catch let error as RenderEngineError {
            throw error
        } catch {
            throw RenderEngineError.previewFailed(error.localizedDescription)
        }
    }

    nonisolated private func cleanupPartialOutput(at outputURL: URL, logger: RenderLogger) async {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            await logger.log("cleanup skipped: no partial file")
            return
        }

        do {
            try FileManager.default.removeItem(at: outputURL)
            await logger.log("cleanup partial output: removed \(outputURL.lastPathComponent)")
        } catch {
            await logger.log("cleanup failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func makeInputSummary(urls: [URL]) -> String {
        var extensionCounts: [String: Int] = [:]
        var totalBytes: UInt64 = 0
        var widthMin = Int.max
        var widthMax = 0
        var heightMin = Int.max
        var heightMax = 0
        var dimensionCount = 0

        for url in urls {
            let ext = url.pathExtension.lowercased()
            extensionCounts[ext.isEmpty ? "(none)" : ext, default: 0] += 1

            if
                let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize,
                fileSize > 0
            {
                totalBytes += UInt64(fileSize)
            }

            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width > 0,
                height > 0
            else {
                continue
            }

            dimensionCount += 1
            widthMin = min(widthMin, width)
            widthMax = max(widthMax, width)
            heightMin = min(heightMin, height)
            heightMax = max(heightMax, height)
        }

        let extensionSummary = extensionCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")

        let dimensionsSummary: String
        if dimensionCount > 0 {
            dimensionsSummary = "\(widthMin)x\(heightMin)-\(widthMax)x\(heightMax)"
        } else {
            dimensionsSummary = "unknown"
        }

        let totalMB = Double(totalBytes) / 1_048_576.0
        return String(
            format: "formats={%@} dimensions=%@ sampled=%d/%d totalBytes=%.2fMB",
            extensionSummary,
            dimensionsSummary,
            dimensionCount,
            urls.count,
            totalMB
        )
    }
}
