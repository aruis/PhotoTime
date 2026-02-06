import CoreGraphics
import CoreImage
import Foundation

struct RenderSettings {
    let outputSize: CGSize
    let fps: Int32
    let imageDuration: TimeInterval
    let transitionDuration: TimeInterval
    let enableKenBurns: Bool
    let prefetchRadius: Int
    let prefetchMaxConcurrent: Int

    nonisolated init(
        outputSize: CGSize,
        fps: Int32,
        imageDuration: TimeInterval,
        transitionDuration: TimeInterval,
        enableKenBurns: Bool,
        prefetchRadius: Int = 1,
        prefetchMaxConcurrent: Int = 2
    ) {
        self.outputSize = outputSize
        self.fps = fps
        self.imageDuration = imageDuration
        self.transitionDuration = transitionDuration
        self.enableKenBurns = enableKenBurns
        self.prefetchRadius = max(0, prefetchRadius)
        self.prefetchMaxConcurrent = max(1, prefetchMaxConcurrent)
    }

    nonisolated static let mvp = RenderSettings(
        outputSize: CGSize(width: 1920, height: 1080),
        fps: 30,
        imageDuration: 3.0,
        transitionDuration: 0.6,
        enableKenBurns: true,
        prefetchRadius: 1,
        prefetchMaxConcurrent: 2
    )

    nonisolated init(template: RenderTemplate) {
        self.init(
            outputSize: CGSize(width: template.output.width, height: template.output.height),
            fps: template.output.fps,
            imageDuration: template.timeline.imageDuration,
            transitionDuration: template.timeline.transitionDuration,
            enableKenBurns: template.motion.enableKenBurns,
            prefetchRadius: template.performance.prefetchRadius,
            prefetchMaxConcurrent: template.performance.prefetchMaxConcurrent
        )
    }

    nonisolated var template: RenderTemplate {
        RenderTemplate(
            output: .init(
                width: Int(outputSize.width.rounded()),
                height: Int(outputSize.height.rounded()),
                fps: fps
            ),
            timeline: .init(
                imageDuration: imageDuration,
                transitionDuration: transitionDuration
            ),
            motion: .init(enableKenBurns: enableKenBurns),
            performance: .init(
                prefetchRadius: prefetchRadius,
                prefetchMaxConcurrent: prefetchMaxConcurrent
            )
        )
    }
}

struct RenderTemplate: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let output: Output
    let timeline: Timeline
    let motion: Motion
    let performance: Performance

    init(
        schemaVersion: Int = RenderTemplate.currentSchemaVersion,
        output: Output,
        timeline: Timeline,
        motion: Motion,
        performance: Performance
    ) {
        self.schemaVersion = schemaVersion
        self.output = output
        self.timeline = timeline
        self.motion = motion
        self.performance = performance
    }

    struct Output: Codable, Sendable {
        let width: Int
        let height: Int
        let fps: Int32
    }

    struct Timeline: Codable, Sendable {
        let imageDuration: TimeInterval
        let transitionDuration: TimeInterval
    }

    struct Motion: Codable, Sendable {
        let enableKenBurns: Bool
    }

    struct Performance: Codable, Sendable {
        let prefetchRadius: Int
        let prefetchMaxConcurrent: Int
    }
}

struct ExifInfo: Sendable {
    let shutter: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?

    nonisolated var plateText: String {
        let shutterValue = shutter ?? "--"
        let apertureValue = aperture ?? "--"
        let isoValue = iso ?? "--"
        let focalValue = focalLength ?? "--"
        return "S \(shutterValue)   A \(apertureValue)   ISO \(isoValue)   F \(focalValue)"
    }
}

struct RenderAsset {
    let url: URL
    let image: CIImage
    let exif: ExifInfo
}
