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
    nonisolated static func load(urls: [URL], targetMaxDimension: Int) throws -> [RenderAsset] {
        try urls.map { try load(url: $0, targetMaxDimension: targetMaxDimension) }
    }

    nonisolated static func load(url: URL, targetMaxDimension: Int) throws -> RenderAsset {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetMaxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            .map({ CIImage(cgImage: $0) }) else {
            throw ImageLoaderError.unsupportedImage(url)
        }

        return RenderAsset(url: url, image: image, exif: ExifParser.parse(from: properties))
    }
}
