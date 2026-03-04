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

    @Test
    func plateTemplateReplacesKnownTokens() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.01,
                kCGImagePropertyExifFNumber: 4.0,
                kCGImagePropertyExifISOSpeedRatings: [200],
                kCGImagePropertyExifFocalLength: 50.0,
                kCGImagePropertyExifDateTimeOriginal: "2026:03:03 12:00:00",
                kCGImagePropertyExifLensModel: "XF23mmF2 R WR"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: "X100V"
            ]
        ]

        let parsed = ExifParser.parse(from: properties)
        let text = parsed.resolvedPlateText(template: "{camera}/{lens} {date} S {shutter} A {aperture} ISO {iso} F {focal}")

        #expect(text == "X100V/XF23mmF2 R WR 2026-03-03 S 1/100s A f/4.0 ISO 200 F 50mm")
    }

    @Test
    func lensModelFallsBackToExifAux() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifAuxDictionary: [
                kCGImagePropertyExifAuxLensModel: "iPhone 26mm equivalent f/1.8"
            ]
        ]

        let parsed = ExifParser.parse(from: properties)

        #expect(parsed.lens == "iPhone 26mm equivalent f/1.8")
    }

    @Test
    func emptyTemplateFallsBackToDefaultTemplate() {
        let parsed = ExifParser.parse(from: [:])
        let text = parsed.resolvedPlateText(template: "   ")

        #expect(text == parsed.plateText)
    }
}
