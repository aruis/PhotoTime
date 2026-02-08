import CoreGraphics
import Foundation
import Testing
@testable import PhotoTime

struct RenderTemplateTests {
    @Test
    func templateRoundTripPreservesSettings() throws {
        let settings = RenderSettings(
            outputSize: CGSize(width: 2560, height: 1440),
            fps: 24,
            imageDuration: 2.5,
            transitionDuration: 0.5,
            transitionEnabled: false,
            transitionStyle: .crossfade,
            enableKenBurns: true,
            prefetchRadius: 2,
            prefetchMaxConcurrent: 3,
            layout: LayoutSettings(horizontalMargin: 160, topMargin: 60, bottomMargin: 84, innerPadding: 20),
            plate: PlateSettings(enabled: true, height: 88, baselineOffset: 16, fontSize: 24),
            canvas: CanvasSettings(backgroundGray: 0.12, paperWhite: 0.97, strokeGray: 0.8, textGray: 0.2)
        )

        let template = settings.template
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(RenderTemplate.self, from: data)
        let rebuilt = RenderSettings(template: decoded)

        #expect(decoded.schemaVersion == RenderTemplate.currentSchemaVersion)
        #expect(Int(rebuilt.outputSize.width) == 2560)
        #expect(Int(rebuilt.outputSize.height) == 1440)
        #expect(rebuilt.fps == 24)
        #expect(rebuilt.imageDuration == 2.5)
        #expect(rebuilt.transitionDuration == 0.5)
        #expect(rebuilt.transitionEnabled == false)
        #expect(rebuilt.effectiveTransitionDuration == 0)
        #expect(rebuilt.transitionStyle == .crossfade)
        #expect(rebuilt.enableKenBurns)
        #expect(rebuilt.prefetchRadius == 2)
        #expect(rebuilt.prefetchMaxConcurrent == 3)
        #expect(rebuilt.layout.horizontalMargin == 160)
        #expect(rebuilt.layout.topMargin == 60)
        #expect(rebuilt.layout.bottomMargin == 84)
        #expect(rebuilt.layout.innerPadding == 20)
        #expect(rebuilt.plate.enabled)
        #expect(rebuilt.plate.height == 88)
        #expect(rebuilt.plate.baselineOffset == 16)
        #expect(rebuilt.plate.fontSize == 24)
        #expect(rebuilt.canvas.backgroundGray == 0.12)
        #expect(rebuilt.canvas.paperWhite == 0.97)
        #expect(rebuilt.canvas.strokeGray == 0.8)
        #expect(rebuilt.canvas.textGray == 0.2)
    }

    @Test
    func templateDecodeUsesRenderSettingsSafetyClamp() throws {
        let json = """
        {
          "schemaVersion": 1,
          "output": {
            "width": 1920,
            "height": 1080,
            "fps": 30
          },
          "timeline": {
            "imageDuration": 3,
            "transitionDuration": 0.6
          },
          "motion": {
            "enableKenBurns": false
          },
          "performance": {
            "prefetchRadius": -10,
            "prefetchMaxConcurrent": 0
          }
        }
        """

        let decoded = try JSONDecoder().decode(RenderTemplate.self, from: Data(json.utf8))
        let settings = RenderSettings(template: decoded)

        #expect(decoded.schemaVersion == 1)
        #expect(settings.prefetchRadius == 0)
        #expect(settings.prefetchMaxConcurrent == 1)
        #expect(settings.transitionStyle == .crossfade)
        #expect(settings.transitionEnabled == true)
        #expect(settings.layout.horizontalMargin == LayoutSettings.default.horizontalMargin)
        #expect(settings.layout.topMargin == LayoutSettings.default.topMargin)
        #expect(settings.layout.bottomMargin == LayoutSettings.default.bottomMargin)
        #expect(settings.layout.innerPadding == LayoutSettings.default.innerPadding)
        #expect(settings.plate.enabled == PlateSettings.default.enabled)
        #expect(settings.plate.height == PlateSettings.default.height)
        #expect(settings.plate.baselineOffset == PlateSettings.default.baselineOffset)
        #expect(settings.plate.fontSize == PlateSettings.default.fontSize)
        #expect(settings.canvas.backgroundGray == CanvasSettings.default.backgroundGray)
        #expect(settings.canvas.paperWhite == CanvasSettings.default.paperWhite)
        #expect(settings.canvas.strokeGray == CanvasSettings.default.strokeGray)
        #expect(settings.canvas.textGray == CanvasSettings.default.textGray)
    }

    @Test
    func templateDecodeTransitionMissingEnabledDefaultsToTrue() throws {
        let json = """
        {
          "schemaVersion": 2,
          "output": {
            "width": 1920,
            "height": 1080,
            "fps": 30
          },
          "timeline": {
            "imageDuration": 3,
            "transitionDuration": 0.6
          },
          "transition": {
            "style": "crossfade"
          },
          "motion": {
            "enableKenBurns": true
          },
          "performance": {
            "prefetchRadius": 1,
            "prefetchMaxConcurrent": 2
          }
        }
        """

        let decoded = try JSONDecoder().decode(RenderTemplate.self, from: Data(json.utf8))
        let settings = RenderSettings(template: decoded)

        #expect(settings.transitionEnabled == true)
        #expect(settings.effectiveTransitionDuration == settings.transitionDuration)
    }
}
