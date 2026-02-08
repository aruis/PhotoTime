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
        config.prefetchRadius = -3
        config.prefetchMaxConcurrent = 0

        config.clampToSafeRange()

        #expect(config.outputWidth == RenderEditorConfig.outputWidthRange.lowerBound)
        #expect(config.outputHeight == RenderEditorConfig.outputHeightRange.lowerBound)
        #expect(config.fps == RenderEditorConfig.fpsRange.lowerBound)
        #expect(config.imageDuration == RenderEditorConfig.imageDurationRange.lowerBound)
        #expect(config.transitionDuration < config.imageDuration)
        #expect(config.prefetchRadius == RenderEditorConfig.prefetchRadiusRange.lowerBound)
        #expect(config.prefetchMaxConcurrent == RenderEditorConfig.prefetchMaxConcurrentRange.lowerBound)
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
        config.enableKenBurns = false
        config.prefetchRadius = 3
        config.prefetchMaxConcurrent = 4

        let rebuilt = RenderEditorConfig(template: config.template)

        #expect(rebuilt.outputWidth == config.outputWidth)
        #expect(rebuilt.outputHeight == config.outputHeight)
        #expect(rebuilt.fps == config.fps)
        #expect(rebuilt.imageDuration == config.imageDuration)
        #expect(rebuilt.transitionDuration == config.transitionDuration)
        #expect(rebuilt.enableCrossfade == config.enableCrossfade)
        #expect(rebuilt.enableKenBurns == config.enableKenBurns)
        #expect(rebuilt.prefetchRadius == config.prefetchRadius)
        #expect(rebuilt.prefetchMaxConcurrent == config.prefetchMaxConcurrent)
    }
}
