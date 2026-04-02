import AppKit
import SwiftUI
import ImageIO

enum AssetThumbnailPipeline {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    @MainActor
    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated static func renderThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }

    @MainActor
    static func cacheImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct AssetThumbnailView: View {
    let url: URL
    let height: CGFloat

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            if let cached = AssetThumbnailPipeline.cachedImage(for: url) {
                image = cached
                return
            }
            let target = Int(height * 2.5)
            let loaded = await Task.detached(priority: .utility) {
                AssetThumbnailPipeline.renderThumbnail(for: url, maxPixelSize: target)
            }.value
            guard !Task.isCancelled else { return }
            if let loaded {
                AssetThumbnailPipeline.cacheImage(loaded, for: url)
            }
            image = loaded
        }
    }
}

struct AssetReorderDropDelegate: DropDelegate {
    let destination: URL
    @Binding var dragging: URL?
    let canReorder: Bool
    let onMove: (URL, URL) -> Void

    func dropEntered(info: DropInfo) {
        guard canReorder else { return }
        guard let dragging, dragging != destination else { return }
        onMove(dragging, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        canReorder ? DropProposal(operation: .move) : DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
