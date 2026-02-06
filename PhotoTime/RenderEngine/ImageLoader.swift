import CoreImage
import Foundation
import ImageIO

enum ImageLoaderError: LocalizedError {
    case unsupportedImage(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage(let url):
            return "无法读取图片: \(url.lastPathComponent)"
        }
    }
}

enum ImageLoader {
    nonisolated static func load(urls: [URL]) throws -> [RenderAsset] {
        try urls.map(load(url:))
    }

    nonisolated static func load(url: URL) throws -> RenderAsset {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        guard var image = CIImage(contentsOf: url, options: [
            .applyOrientationProperty: true
        ]) else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        if let orientationRaw = properties[kCGImagePropertyOrientation] as? UInt32 {
            image = image.oriented(forExifOrientation: Int32(orientationRaw))
        }

        return RenderAsset(url: url, image: image, exif: ExifParser.parse(from: properties))
    }
}
