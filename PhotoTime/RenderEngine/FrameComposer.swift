import AppKit
import CoreImage
import Foundation

struct ComposedClip {
    let paperImage: CIImage
    let photoImage: CIImage
    let staticPhotoImage: CIImage?
    let textOverlay: CIImage
    let photoRect: CGRect
}

final class FrameComposer {
    private let settings: RenderSettings
    private let layout: FrameLayout
    private let backgroundImage: CIImage
    private let strokeColor: CGColor
    private let textColor: NSColor

    nonisolated init(settings: RenderSettings) {
        self.settings = settings
        self.layout = LayoutEngine.makeLayout(outputSize: settings.outputSize, settings: settings)
        self.strokeColor = CGColor(
            red: CGFloat(settings.canvas.strokeGray),
            green: CGFloat(settings.canvas.strokeGray),
            blue: CGFloat(settings.canvas.strokeGray),
            alpha: 1
        )
        self.textColor = NSColor(white: CGFloat(settings.canvas.textGray), alpha: 1)

        let bg = CGFloat(settings.canvas.backgroundGray)
        backgroundImage = CIImage(color: CIColor(red: bg, green: bg, blue: bg, alpha: 1))
            .cropped(to: layout.canvas)
    }

    nonisolated func makeClip(_ asset: RenderAsset) -> ComposedClip {
        let orientedImage = adjustedImageForOrientationStrategy(asset.image)
        let rects = resolvedFrameRects(for: orientedImage)
        let paper = CGFloat(settings.canvas.paperWhite)
        return ComposedClip(
            paperImage: CIImage(color: CIColor(red: paper, green: paper, blue: paper, alpha: 1))
                .cropped(to: rects.paperRect),
            photoImage: orientedImage,
            staticPhotoImage: settings.enableKenBurns
                ? nil
                : orientedImage
                    .transformed(by: aspectFitTransform(imageExtent: orientedImage.extent, into: rects.photoRect))
                    .cropped(to: rects.photoRect),
            textOverlay: makeTextOverlay(
                text: asset.exif.plateText,
                photoRect: rects.photoRect,
                plateTextRect: rects.plateTextRect
            ),
            photoRect: rects.photoRect
        )
    }

    nonisolated func composeFrame(layerClips: [(TimelineLayer, ComposedClip)]) -> CIImage {
        var frame = backgroundImage

        for (layer, clip) in layerClips {
            frame = composite(clip.paperImage, opacity: layer.opacity, over: frame)
            let photo = clip.staticPhotoImage ?? makePhotoLayer(
                image: clip.photoImage,
                into: clip.photoRect,
                progress: layer.progress,
                index: layer.clipIndex
            )
            frame = composite(photo, opacity: layer.opacity, over: frame)
        }

        // Draw text and frame strokes above the photo.
        for (layer, clip) in layerClips {
            frame = composite(clip.textOverlay, opacity: layer.opacity, over: frame)
        }

        return frame.cropped(to: layout.canvas)
    }

    nonisolated private func makePhotoLayer(image: CIImage, into photoRect: CGRect, progress: Double, index: Int) -> CIImage {
        let fitted = image.transformed(by: aspectFitTransform(imageExtent: image.extent, into: photoRect))
        let transformed: CIImage

        if settings.enableKenBurns {
            let scale = 1.0 + 0.04 * progress
            let panX = CGFloat((progress - 0.5) * 30 * (index.isMultiple(of: 2) ? 1 : -1))
            let panY = CGFloat((progress - 0.5) * 18)

            let center = CGPoint(x: photoRect.midX, y: photoRect.midY)
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: center.x, y: center.y)
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            transform = transform.translatedBy(x: panX, y: panY)
            transformed = fitted.transformed(by: transform)
        } else {
            transformed = fitted
        }

        return transformed.cropped(to: photoRect)
    }

    nonisolated private func adjustedImageForOrientationStrategy(_ image: CIImage) -> CIImage {
        switch settings.orientationStrategy {
        case .followAsset:
            return image
        case .forceLandscape:
            return image.extent.height > image.extent.width ? rotateByQuarterTurn(image) : image
        case .forcePortrait:
            return image.extent.width > image.extent.height ? rotateByQuarterTurn(image) : image
        }
    }

    nonisolated private func rotateByQuarterTurn(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.rotated(by: .pi / 2)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return image.transformed(by: transform)
    }

    nonisolated private func aspectFitTransform(imageExtent: CGRect, into rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / imageExtent.width, rect.height / imageExtent.height)
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

    nonisolated private func composite(_ image: CIImage, opacity: Float, over base: CIImage) -> CIImage {
        if opacity <= 0.001 {
            return base
        }
        if opacity >= 0.999 {
            return image.composited(over: base)
        }
        return applyOpacity(image, opacity: opacity).composited(over: base)
    }

    nonisolated private func makeTextOverlay(
        text: String,
        photoRect: CGRect,
        plateTextRect: CGRect
    ) -> CIImage {
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

        context.setStrokeColor(strokeColor)
        context.setLineWidth(1)
        context.stroke(photoRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: CGFloat(settings.plate.fontSize), weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]

        if settings.plate.enabled {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (text as NSString).draw(in: plateTextRect, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let cgImage = context.makeImage() else {
            return CIImage.empty()
        }

        return CIImage(cgImage: cgImage)
    }

    nonisolated private func resolvedFrameRects(for orientedImage: CIImage) -> (paperRect: CGRect, photoRect: CGRect, plateTextRect: CGRect) {
        let frameMargin = CGFloat(settings.layout.innerPadding)
        let maxPaperRect = layout.paperRect
        let maxPhotoRect = maxPaperRect.insetBy(dx: frameMargin, dy: frameMargin)
        let photoRect = fitRect(source: orientedImage.extent.size, inside: maxPhotoRect)
        let paperRect = photoRect.insetBy(dx: -frameMargin, dy: -frameMargin)

        let plateTextRect: CGRect
        switch settings.plate.placement {
        case .frame:
            let band = CGRect(
                x: paperRect.minX + frameMargin,
                y: paperRect.minY,
                width: max(0, paperRect.width - frameMargin * 2),
                height: max(0, photoRect.minY - paperRect.minY)
            )
            plateTextRect = CGRect(
                x: band.minX,
                y: band.minY + CGFloat(settings.plate.baselineOffset),
                width: band.width,
                height: max(0, band.height - CGFloat(settings.plate.baselineOffset) * 2)
            )
        case .canvasBottom:
            let band = CGRect(
                x: maxPaperRect.minX + frameMargin,
                y: 0,
                width: max(0, maxPaperRect.width - frameMargin * 2),
                height: max(0, maxPaperRect.minY)
            )
            plateTextRect = CGRect(
                x: band.minX,
                y: band.minY + CGFloat(settings.plate.baselineOffset),
                width: band.width,
                height: max(0, band.height - CGFloat(settings.plate.baselineOffset) * 2)
            )
        }
        return (paperRect, photoRect, plateTextRect)
    }

    nonisolated private func fitRect(source: CGSize, inside target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return target
        }
        let scale = min(target.width / source.width, target.height / source.height)
        let width = source.width * scale
        let height = source.height * scale
        let x = target.midX - width / 2
        let y = target.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

}
