import Testing
@testable import PhotoTime

struct RenderEditorConfigTests {
    @Test
    func clampKeepsConfigInsideSafeRange() {
        var config = RenderEditorConfig()
        config.outputWidth = 100
        config.outputHeight = 100
        config.fps = 0
        config.imageDuration = 0
        config.transitionDuration = 10
        config.canvasBackgroundGray = -1
        config.canvasPaperWhite = 2
        config.canvasStrokeGray = -2
        config.canvasTextGray = 3
        config.horizontalMargin = -10
        config.topMargin = 1000
        config.bottomMargin = 1000
        config.innerPadding = -8
        config.plateHeight = 999
        config.plateBaselineOffset = -5
        config.plateFontSize = 100
        config.prefetchRadius = -3
        config.prefetchMaxConcurrent = 0
        config.audioEnabled = true
        config.audioFilePath = "/tmp/test.m4a"
        config.audioVolume = 2

        config.clampToSafeRange()

        #expect(config.outputWidth == RenderEditorConfig.outputWidthRange.lowerBound)
        #expect(config.outputHeight == RenderEditorConfig.outputHeightRange.lowerBound)
        #expect(config.fps == RenderEditorConfig.fpsRange.lowerBound)
        #expect(config.imageDuration == RenderEditorConfig.imageDurationRange.lowerBound)
        #expect(config.transitionDuration < config.imageDuration)
        #expect(config.canvasBackgroundGray == RenderEditorConfig.grayRange.lowerBound)
        #expect(config.canvasPaperWhite == RenderEditorConfig.grayRange.upperBound)
        #expect(config.canvasStrokeGray == RenderEditorConfig.grayRange.lowerBound)
        #expect(config.canvasTextGray == RenderEditorConfig.grayRange.upperBound)
        #expect(config.horizontalMargin == RenderEditorConfig.horizontalMarginRange.lowerBound)
        #expect(config.topMargin == RenderEditorConfig.topMarginRange.upperBound)
        #expect(config.bottomMargin == RenderEditorConfig.bottomMarginRange.upperBound)
        #expect(config.innerPadding == RenderEditorConfig.innerPaddingRange.lowerBound)
        #expect(config.plateHeight == RenderEditorConfig.plateHeightRange.upperBound)
        #expect(config.plateBaselineOffset == RenderEditorConfig.plateBaselineOffsetRange.lowerBound)
        #expect(config.plateFontSize == RenderEditorConfig.plateFontSizeRange.upperBound)
        #expect(config.prefetchRadius == RenderEditorConfig.prefetchRadiusRange.lowerBound)
        #expect(config.prefetchMaxConcurrent == RenderEditorConfig.prefetchMaxConcurrentRange.lowerBound)
        #expect(config.audioVolume == RenderEditorConfig.audioVolumeRange.upperBound)
    }

    @Test
    func templateRoundTripPreservesEditableFields() {
        var config = RenderEditorConfig()
        config.outputWidth = 2560
        config.outputHeight = 1440
        config.fps = 24
        config.imageDuration = 2.5
        config.transitionDuration = 0.5
        config.enableCrossfade = false
        config.orientationStrategy = .forcePortrait
        config.frameStylePreset = .custom
        config.canvasBackgroundGray = 0.2
        config.canvasPaperWhite = 0.95
        config.canvasStrokeGray = 0.66
        config.canvasTextGray = 0.18
        config.horizontalMargin = 160
        config.topMargin = 66
        config.bottomMargin = 104
        config.innerPadding = 28
        config.plateEnabled = false
        config.plateHeight = 78
        config.plateBaselineOffset = 12
        config.plateFontSize = 22
        config.enableKenBurns = false
        config.prefetchRadius = 3
        config.prefetchMaxConcurrent = 4
        config.audioEnabled = true
        config.audioFilePath = "/tmp/bgm.m4a"
        config.audioVolume = 0.72
        config.audioLoopEnabled = true

        let rebuilt = RenderEditorConfig(template: config.template)

        #expect(rebuilt.outputWidth == config.outputWidth)
        #expect(rebuilt.outputHeight == config.outputHeight)
        #expect(rebuilt.fps == config.fps)
        #expect(rebuilt.imageDuration == config.imageDuration)
        #expect(rebuilt.transitionDuration == config.transitionDuration)
        #expect(rebuilt.enableCrossfade == config.enableCrossfade)
        #expect(rebuilt.orientationStrategy == config.orientationStrategy)
        #expect(rebuilt.frameStylePreset == config.frameStylePreset)
        #expect(rebuilt.canvasBackgroundGray == config.canvasBackgroundGray)
        #expect(rebuilt.canvasPaperWhite == config.canvasPaperWhite)
        #expect(rebuilt.canvasStrokeGray == config.canvasStrokeGray)
        #expect(rebuilt.canvasTextGray == config.canvasTextGray)
        #expect(rebuilt.horizontalMargin == config.horizontalMargin)
        #expect(rebuilt.topMargin == config.topMargin)
        #expect(rebuilt.bottomMargin == config.bottomMargin)
        #expect(rebuilt.innerPadding == config.innerPadding)
        #expect(rebuilt.plateEnabled == config.plateEnabled)
        #expect(rebuilt.plateHeight == config.plateHeight)
        #expect(rebuilt.plateBaselineOffset == config.plateBaselineOffset)
        #expect(rebuilt.plateFontSize == config.plateFontSize)
        #expect(rebuilt.enableKenBurns == config.enableKenBurns)
        #expect(rebuilt.prefetchRadius == config.prefetchRadius)
        #expect(rebuilt.prefetchMaxConcurrent == config.prefetchMaxConcurrent)
        #expect(rebuilt.audioEnabled == config.audioEnabled)
        #expect(rebuilt.audioFilePath == config.audioFilePath)
        #expect(rebuilt.audioVolume == config.audioVolume)
        #expect(rebuilt.audioLoopEnabled == config.audioLoopEnabled)
    }

    @Test
    func presetCanvasIsAppliedToRenderSettings() {
        var config = RenderEditorConfig()
        config.frameStylePreset = .contrast
        config.canvasBackgroundGray = 0.33
        config.canvasPaperWhite = 0.44
        config.canvasStrokeGray = 0.55
        config.canvasTextGray = 0.66

        let settings = config.renderSettings

        #expect(settings.canvas.backgroundGray == FrameStylePreset.contrast.canvas.backgroundGray)
        #expect(settings.canvas.paperWhite == FrameStylePreset.contrast.canvas.paperWhite)
        #expect(settings.canvas.strokeGray == FrameStylePreset.contrast.canvas.strokeGray)
        #expect(settings.canvas.textGray == FrameStylePreset.contrast.canvas.textGray)
    }

    @Test
    func layoutAndPlateSettingsAreAppliedToRenderSettings() {
        var config = RenderEditorConfig()
        config.horizontalMargin = 150
        config.topMargin = 55
        config.bottomMargin = 92
        config.innerPadding = 20
        config.plateEnabled = false
        config.plateHeight = 72
        config.plateBaselineOffset = 10
        config.plateFontSize = 21

        let settings = config.renderSettings

        #expect(settings.layout.horizontalMargin == 150)
        #expect(settings.layout.topMargin == 55)
        #expect(settings.layout.bottomMargin == 92)
        #expect(settings.layout.innerPadding == 20)
        #expect(settings.plate.enabled == false)
        #expect(settings.plate.height == 72)
        #expect(settings.plate.baselineOffset == 10)
        #expect(settings.plate.fontSize == 21)
    }

    @Test
    func audioEnabledWithoutFilePathIsInvalid() {
        var config = RenderEditorConfig()
        config.audioEnabled = true
        config.audioFilePath = " "

        #expect(config.invalidMessage?.contains("音频") == true)
    }
}
