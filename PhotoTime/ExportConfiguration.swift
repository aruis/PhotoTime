import CoreGraphics
import Foundation

enum FrameStylePreset: String, CaseIterable, Sendable {
    case classic
    case soft
    case contrast
    case gallery
    case custom

    var displayName: String {
        switch self {
        case .classic:
            return "经典暗底"
        case .soft:
            return "柔和浅灰"
        case .contrast:
            return "高对比"
        case .gallery:
            return "画廊暖白"
        case .custom:
            return "自定义"
        }
    }

    var canvas: CanvasSettings {
        switch self {
        case .classic:
            return .init(backgroundGray: 0.09, paperWhite: 0.98, strokeGray: 0.82, textGray: 0.15)
        case .soft:
            return .init(backgroundGray: 0.16, paperWhite: 0.97, strokeGray: 0.78, textGray: 0.22)
        case .contrast:
            return .init(backgroundGray: 0.05, paperWhite: 0.99, strokeGray: 0.72, textGray: 0.1)
        case .gallery:
            return .init(backgroundGray: 0.2, paperWhite: 0.95, strokeGray: 0.68, textGray: 0.18)
        case .custom:
            return .default
        }
    }

    nonisolated static func infer(from canvas: CanvasSettings) -> FrameStylePreset {
        for preset in Self.allCases where preset != .custom {
            if preset.matches(canvas: canvas) {
                return preset
            }
        }
        return .custom
    }

    private func matches(canvas: CanvasSettings) -> Bool {
        let candidate = self.canvas
        return Self.isClose(candidate.backgroundGray, canvas.backgroundGray)
            && Self.isClose(candidate.paperWhite, canvas.paperWhite)
            && Self.isClose(candidate.strokeGray, canvas.strokeGray)
            && Self.isClose(candidate.textGray, canvas.textGray)
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000_1
    }
}

struct RenderEditorConfig: Sendable {
    var outputWidth: Int = 1920
    var outputHeight: Int = 1080
    var fps: Int = 30
    var imageDuration: Double = 3.0
    var transitionDuration: Double = 0.6
    var enableCrossfade: Bool = true
    var orientationStrategy: PhotoOrientationStrategy = .followAsset
    var enableKenBurns: Bool = true
    var frameStylePreset: FrameStylePreset = .classic
    var canvasBackgroundGray: Double = CanvasSettings.default.backgroundGray
    var canvasPaperWhite: Double = CanvasSettings.default.paperWhite
    var canvasStrokeGray: Double = CanvasSettings.default.strokeGray
    var canvasTextGray: Double = CanvasSettings.default.textGray
    var horizontalMargin: Double = LayoutSettings.default.horizontalMargin
    var topMargin: Double = LayoutSettings.default.topMargin
    var bottomMargin: Double = LayoutSettings.default.bottomMargin
    var innerPadding: Double = LayoutSettings.default.innerPadding
    var plateEnabled: Bool = PlateSettings.default.enabled
    var plateHeight: Double = PlateSettings.default.height
    var plateBaselineOffset: Double = PlateSettings.default.baselineOffset
    var plateFontSize: Double = PlateSettings.default.fontSize
    var platePlacement: PlatePlacement = PlateSettings.default.placement
    var prefetchRadius: Int = 1
    var prefetchMaxConcurrent: Int = 2

    static let outputWidthRange = 640...3840
    static let outputHeightRange = 360...2160
    static let fpsRange = 1...60
    static let imageDurationRange = 0.2...10.0
    static let transitionDurationRange = 0.0...2.0
    static let grayRange = 0.0...1.0
    static let horizontalMarginRange = 0.0...360.0
    static let topMarginRange = 0.0...220.0
    static let bottomMarginRange = 0.0...260.0
    static let innerPaddingRange = 0.0...80.0
    static let plateHeightRange = 48.0...180.0
    static let plateBaselineOffsetRange = 0.0...36.0
    static let plateFontSizeRange = 12.0...42.0
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
        orientationStrategy = settings.orientationStrategy
        enableKenBurns = settings.enableKenBurns
        frameStylePreset = FrameStylePreset.infer(from: settings.canvas)
        canvasBackgroundGray = settings.canvas.backgroundGray
        canvasPaperWhite = settings.canvas.paperWhite
        canvasStrokeGray = settings.canvas.strokeGray
        canvasTextGray = settings.canvas.textGray
        horizontalMargin = settings.layout.horizontalMargin
        topMargin = settings.layout.topMargin
        bottomMargin = settings.layout.bottomMargin
        innerPadding = settings.layout.innerPadding
        plateEnabled = settings.plate.enabled
        plateHeight = settings.plate.height
        plateBaselineOffset = settings.plate.baselineOffset
        plateFontSize = settings.plate.fontSize
        platePlacement = settings.plate.placement
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
        canvasBackgroundGray = min(max(canvasBackgroundGray, Self.grayRange.lowerBound), Self.grayRange.upperBound)
        canvasPaperWhite = min(max(canvasPaperWhite, Self.grayRange.lowerBound), Self.grayRange.upperBound)
        canvasStrokeGray = min(max(canvasStrokeGray, Self.grayRange.lowerBound), Self.grayRange.upperBound)
        canvasTextGray = min(max(canvasTextGray, Self.grayRange.lowerBound), Self.grayRange.upperBound)
        horizontalMargin = min(max(horizontalMargin, Self.horizontalMarginRange.lowerBound), Self.horizontalMarginRange.upperBound)
        topMargin = min(max(topMargin, Self.topMarginRange.lowerBound), Self.topMarginRange.upperBound)
        bottomMargin = min(max(bottomMargin, Self.bottomMarginRange.lowerBound), Self.bottomMarginRange.upperBound)
        innerPadding = min(max(innerPadding, Self.innerPaddingRange.lowerBound), Self.innerPaddingRange.upperBound)
        plateHeight = min(max(plateHeight, Self.plateHeightRange.lowerBound), Self.plateHeightRange.upperBound)
        plateBaselineOffset = min(max(plateBaselineOffset, Self.plateBaselineOffsetRange.lowerBound), Self.plateBaselineOffsetRange.upperBound)
        plateFontSize = min(max(plateFontSize, Self.plateFontSizeRange.lowerBound), Self.plateFontSizeRange.upperBound)
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
            orientationStrategy: orientationStrategy,
            enableKenBurns: enableKenBurns,
            prefetchRadius: prefetchRadius,
            prefetchMaxConcurrent: prefetchMaxConcurrent,
            layout: LayoutSettings(
                horizontalMargin: horizontalMargin,
                topMargin: topMargin,
                bottomMargin: bottomMargin,
                innerPadding: innerPadding
            ),
            plate: PlateSettings(
                enabled: plateEnabled,
                height: plateHeight,
                baselineOffset: plateBaselineOffset,
                fontSize: plateFontSize,
                placement: platePlacement
            ),
            canvas: resolvedCanvasSettings
        )
    }

    var template: RenderTemplate {
        renderSettings.template
    }

    private var resolvedCanvasSettings: CanvasSettings {
        if frameStylePreset == .custom {
            return CanvasSettings(
                backgroundGray: canvasBackgroundGray,
                paperWhite: canvasPaperWhite,
                strokeGray: canvasStrokeGray,
                textGray: canvasTextGray
            )
        }
        return frameStylePreset.canvas
    }
}
