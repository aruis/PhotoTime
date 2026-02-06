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
            enableKenBurns: true,
            prefetchRadius: 2,
            prefetchMaxConcurrent: 3
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
        #expect(rebuilt.enableKenBurns)
        #expect(rebuilt.prefetchRadius == 2)
        #expect(rebuilt.prefetchMaxConcurrent == 3)
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

        #expect(settings.prefetchRadius == 0)
        #expect(settings.prefetchMaxConcurrent == 1)
    }
}
