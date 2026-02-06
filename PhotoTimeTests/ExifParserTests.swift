import ImageIO
import Testing
@testable import PhotoTime

struct ExifParserTests {
    @Test
    func missingExifFallsBackToPlaceholder() {
        let parsed = ExifParser.parse(from: [:])
        #expect(parsed.plateText.contains("--"))
    }

    @Test
    func parseCommonExifFields() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.005,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFocalLength: 35.0
            ]
        ]

        let parsed = ExifParser.parse(from: properties)

        #expect(parsed.shutter == "1/200s")
        #expect(parsed.aperture == "f/2.8")
        #expect(parsed.iso == "400")
        #expect(parsed.focalLength == "35mm")
    }
}
