import Foundation
import ImageIO

enum ExifParser {
    nonisolated static func parse(from properties: [CFString: Any]) -> ExifInfo {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        let fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber]
        let focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        let dateOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        let cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        let lensModel = formatCamera(exif[kCGImagePropertyExifLensModel] as? String)
            ?? formatCamera(exifAux[kCGImagePropertyExifAuxLensModel] as? String)

        return ExifInfo(
            shutter: formatShutter(exposureTime),
            aperture: formatAperture(fNumber),
            iso: formatISO(isoArray?.first?.intValue),
            focalLength: formatFocalLength(focalLength),
            date: formatDate(dateOriginal),
            camera: formatCamera(cameraModel),
            lens: lensModel
        )
    }

    nonisolated private static func formatShutter(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        if value >= 1 {
            return String(format: "%.1fs", value)
        }

        let reciprocal = Int((1.0 / value).rounded())
        return "1/\(reciprocal)s"
    }

    nonisolated private static func formatAperture(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "f/%.1f", value)
    }

    nonisolated private static func formatISO(_ value: Int?) -> String? {
        guard let value else { return nil }
        return "\(value)"
    }

    nonisolated private static func formatFocalLength(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.0fmm", value)
    }

    nonisolated private static func formatDate(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let day = String(value.prefix(10))
        return day.replacingOccurrences(of: ":", with: "-")
    }

    nonisolated private static func formatCamera(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
