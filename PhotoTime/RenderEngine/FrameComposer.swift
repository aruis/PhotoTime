import AppKit
import CoreImage
import Foundation

struct ComposedClip {
    let photoImage: CIImage
    let textOverlay: CIImage
}

final class FrameComposer {
    private let settings: RenderSettings
    private let layout: FrameLayout
    private let backgroundImage: CIImage
    private let paperImage: CIImage

    nonisolated init(settings: RenderSettings) {
        self.settings = settings
        self.layout = LayoutEngine.makeLayout(outputSize: settings.outputSize)

        backgroundImage = CIImage(color: CIColor(red: 0.09, green: 0.09, blue: 0.1, alpha: 1))
            .cropped(to: layout.canvas)

        paperImage = CIImage(color: CIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1))
            .cropped(to: layout.paperRect)
    }

    nonisolated func makeClip(_ asset: RenderAsset) -> ComposedClip {
        ComposedClip(
            photoImage: asset.image,
            textOverlay: makeTextOverlay(text: asset.exif.plateText)
        )
    }

    nonisolated func composeFrame(layerClips: [(TimelineLayer, ComposedClip)]) -> CIImage {
        var frame = paperImage.composited(over: backgroundImage)

        for (layer, clip) in layerClips {
            let photo = makePhotoLayer(image: clip.photoImage, progress: layer.progress, index: layer.clipIndex)
            let alphaPhoto = applyOpacity(photo, opacity: layer.opacity)
            frame = alphaPhoto.composited(over: frame)
        }

        // Draw text and frame strokes above the photo.
        for (layer, clip) in layerClips {
            let alphaOverlay = applyOpacity(clip.textOverlay, opacity: layer.opacity)
            frame = alphaOverlay.composited(over: frame)
        }

        return frame.cropped(to: layout.canvas)
    }

    nonisolated private func makePhotoLayer(image: CIImage, progress: Double, index: Int) -> CIImage {
        let fitted = image.transformed(by: aspectFillTransform(imageExtent: image.extent, into: layout.photoRect))
        let transformed: CIImage

        if settings.enableKenBurns {
            let scale = 1.0 + 0.04 * progress
            let panX = CGFloat((progress - 0.5) * 30 * (index.isMultiple(of: 2) ? 1 : -1))
            let panY = CGFloat((progress - 0.5) * 18)

            let center = CGPoint(x: layout.photoRect.midX, y: layout.photoRect.midY)
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: center.x, y: center.y)
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            transform = transform.translatedBy(x: panX, y: panY)
            transformed = fitted.transformed(by: transform)
        } else {
            transformed = fitted
        }

        return transformed.cropped(to: layout.photoRect)
    }

    nonisolated private func aspectFillTransform(imageExtent: CGRect, into rect: CGRect) -> CGAffineTransform {
        let scale = max(rect.width / imageExtent.width, rect.height / imageExtent.height)
        let scaledWidth = imageExtent.width * scale
        let scaledHeight = imageExtent.height * scale

        let x = rect.midX - scaledWidth / 2
        let y = rect.midY - scaledHeight / 2

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: x - imageExtent.minX * scale, y: y - imageExtent.minY * scale)
        transform = transform.scaledBy(x: scale, y: scale)
        return transform
    }

    nonisolated private func applyOpacity(_ image: CIImage, opacity: Float) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
        ])
    }

    nonisolated private func makeTextOverlay(text: String) -> CIImage {
        let width = Int(settings.outputSize.width)
        let height = Int(settings.outputSize.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage.empty()
        }

        context.setStrokeColor(CGColor(red: 0.82, green: 0.82, blue: 0.8, alpha: 1))
        context.setLineWidth(1)
        context.stroke(layout.paperRect)
        context.stroke(layout.photoRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 26, weight: .medium),
            .foregroundColor: NSColor(white: 0.15, alpha: 1),
            .paragraphStyle: paragraph
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(in: layout.plateTextRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return CIImage.empty()
        }

        return CIImage(cgImage: cgImage)
    }
}
