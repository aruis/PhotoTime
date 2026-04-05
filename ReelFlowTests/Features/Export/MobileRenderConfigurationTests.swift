import Testing
@testable import ReelFlow

struct MobileRenderConfigurationTests {
    @Test
    func mapsSimplePresetsToRenderSettings() {
        var config = MobileRenderConfiguration()
        config.resolution = .hd720
        config.fps = 24
        config.duration = .quick
        config.transition = .soft
        config.kenBurns = .subtle
        config.shutterSoundEnabled = false

        let settings = config.makeRenderSettings()

        #expect(settings.outputSize.width == 1280)
        #expect(settings.outputSize.height == 720)
        #expect(settings.fps == 24)
        #expect(settings.imageDuration == 1.5)
        #expect(settings.transitionEnabled)
        #expect(settings.transitionDuration == 0.4)
        #expect(settings.enableKenBurns)
        #expect(settings.shutterSoundTrack == nil)
    }

    @Test
    func disablesTransitionAndKenBurnsWhenOff() {
        var config = MobileRenderConfiguration()
        config.transition = .off
        config.kenBurns = .off
        config.shutterSoundEnabled = false

        let settings = config.makeRenderSettings()

        #expect(!settings.transitionEnabled)
        #expect(settings.transitionDuration == 0)
        #expect(settings.transitionDipDuration == 0)
        #expect(!settings.enableKenBurns)
    }
}
