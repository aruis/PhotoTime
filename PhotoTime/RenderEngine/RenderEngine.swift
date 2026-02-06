import Foundation

enum RenderEngineError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请至少选择一张图片"
        }
    }
}

final class RenderEngine {
    private let settings: RenderSettings

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

        let assets = try ImageLoader.load(urls: imageURLs)
        let timeline = TimelineEngine(
            itemCount: assets.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.transitionDuration
        )

        let composer = FrameComposer(settings: settings)
        let clips = composer.prepareClips(assets)

        let exporter = VideoExporter(settings: settings)
        try await exporter.export(clips: clips, timeline: timeline, composer: composer, to: outputURL, progress: progress)
    }
}
