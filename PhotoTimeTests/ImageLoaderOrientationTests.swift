import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTime

struct ImageLoaderOrientationTests {
    @Test
    func imageLoaderAppliesExifOrientationOnce() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeOrientation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let normalURL = tempDir.appendingPathComponent("normal.jpg")
        let rotatedURL = tempDir.appendingPathComponent("rotated.jpg")

        try Self.writeJPEG(to: normalURL, width: 120, height: 80, exifOrientation: 1)
        try Self.writeJPEG(to: rotatedURL, width: 120, height: 80, exifOrientation: 6)

        let normalAsset = try ImageLoader.load(url: normalURL, targetMaxDimension: 512)
        let rotatedAsset = try ImageLoader.load(url: rotatedURL, targetMaxDimension: 512)

        #expect(normalAsset.image.extent.width > normalAsset.image.extent.height)
        #expect(rotatedAsset.image.extent.height > rotatedAsset.image.extent.width)
    }

    private static func writeJPEG(to url: URL, width: Int, height: Int, exifOrientation: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ImageLoaderOrientationTests", code: 1)
        }

        context.setFillColor(CGColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw NSError(domain: "ImageLoaderOrientationTests", code: 2)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ImageLoaderOrientationTests", code: 3)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: exifOrientation
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageLoaderOrientationTests", code: 4)
        }
    }
}
