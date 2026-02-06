import CoreGraphics
import CoreImage
import Foundation

struct RenderSettings {
    let outputSize: CGSize
    let fps: Int32
    let imageDuration: TimeInterval
    let transitionDuration: TimeInterval
    let enableKenBurns: Bool

    nonisolated static let mvp = RenderSettings(
        outputSize: CGSize(width: 1920, height: 1080),
        fps: 30,
        imageDuration: 3.0,
        transitionDuration: 0.6,
        enableKenBurns: true
    )
}

struct ExifInfo: Sendable {
    let shutter: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?

    nonisolated var plateText: String {
        let shutterValue = shutter ?? "--"
        let apertureValue = aperture ?? "--"
        let isoValue = iso ?? "--"
        let focalValue = focalLength ?? "--"
        return "S \(shutterValue)   A \(apertureValue)   ISO \(isoValue)   F \(focalValue)"
    }
}

struct RenderAsset {
    let url: URL
    let image: CIImage
    let exif: ExifInfo
}
