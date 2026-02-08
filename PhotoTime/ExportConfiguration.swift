import CoreGraphics
import Foundation

struct RenderEditorConfig: Sendable {
    var outputWidth: Int = 1920
    var outputHeight: Int = 1080
    var fps: Int = 30
    var imageDuration: Double = 3.0
    var transitionDuration: Double = 0.6
    var enableCrossfade: Bool = true
    var enableKenBurns: Bool = true
    var prefetchRadius: Int = 1
    var prefetchMaxConcurrent: Int = 2

    static let outputWidthRange = 640...3840
    static let outputHeightRange = 360...2160
    static let fpsRange = 1...60
    static let imageDurationRange = 0.2...10.0
    static let transitionDurationRange = 0.0...2.0
    static let prefetchRadiusRange = 0...4
    static let prefetchMaxConcurrentRange = 1...8

    init() {}

    init(template: RenderTemplate) {
        let settings = RenderSettings(template: template)
        self.init(settings: settings)
    }

    init(settings: RenderSettings) {
        outputWidth = Int(settings.outputSize.width.rounded())
        outputHeight = Int(settings.outputSize.height.rounded())
        fps = Int(settings.fps)
        imageDuration = settings.imageDuration
        transitionDuration = settings.transitionDuration
        enableCrossfade = settings.transitionEnabled
        enableKenBurns = settings.enableKenBurns
        prefetchRadius = settings.prefetchRadius
        prefetchMaxConcurrent = settings.prefetchMaxConcurrent
        clampToSafeRange()
    }

    mutating func clampToSafeRange() {
        outputWidth = min(max(outputWidth, Self.outputWidthRange.lowerBound), Self.outputWidthRange.upperBound)
        outputHeight = min(max(outputHeight, Self.outputHeightRange.lowerBound), Self.outputHeightRange.upperBound)
        fps = min(max(fps, Self.fpsRange.lowerBound), Self.fpsRange.upperBound)
        imageDuration = min(max(imageDuration, Self.imageDurationRange.lowerBound), Self.imageDurationRange.upperBound)
        transitionDuration = min(max(transitionDuration, Self.transitionDurationRange.lowerBound), Self.transitionDurationRange.upperBound)
        if transitionDuration >= imageDuration {
            transitionDuration = max(0, imageDuration - 0.05)
        }
        prefetchRadius = min(max(prefetchRadius, Self.prefetchRadiusRange.lowerBound), Self.prefetchRadiusRange.upperBound)
        prefetchMaxConcurrent = min(max(prefetchMaxConcurrent, Self.prefetchMaxConcurrentRange.lowerBound), Self.prefetchMaxConcurrentRange.upperBound)
    }

    var invalidMessage: String? {
        if !Self.outputWidthRange.contains(outputWidth) || !Self.outputHeightRange.contains(outputHeight) {
            return "分辨率过低，请至少设置为 640x360"
        }
        if !Self.fpsRange.contains(fps) {
            return "FPS 必须大于 0"
        }
        if imageDuration <= 0 {
            return "单图时长必须大于 0"
        }
        if enableCrossfade && (transitionDuration < 0 || transitionDuration >= imageDuration) {
            return "转场时长必须满足 0 <= 转场 < 单图时长"
        }
        return nil
    }

    var renderSettings: RenderSettings {
        RenderSettings(
            outputSize: CGSize(width: outputWidth, height: outputHeight),
            fps: Int32(fps),
            imageDuration: imageDuration,
            transitionDuration: transitionDuration,
            transitionEnabled: enableCrossfade,
            enableKenBurns: enableKenBurns,
            prefetchRadius: prefetchRadius,
            prefetchMaxConcurrent: prefetchMaxConcurrent
        )
    }

    var template: RenderTemplate {
        renderSettings.template
    }
}
