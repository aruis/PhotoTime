import CoreImage
import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ComposedClip {
    let paperImage: CIImage
    let photoImage: CIImage
    let staticPhotoImage: CIImage?
    let staticCardImage: CIImage?
    let cardMotionProfile: CardMotionProfile?
    let textOverlay: CIImage
    let photoRect: CGRect
    let cardBounds: CGRect
}

struct CardMotionProfile {
    let startScale: CGFloat
    let endScale: CGFloat
    let panX: CGFloat
    let panY: CGFloat
}

final class FrameComposer {
    private let settings: RenderSettings
    private let layout: FrameLayout
    private let backgroundImage: CIImage
    private let strokeColor: CGColor
    private let textColor: PlatformColor

    nonisolated init(settings: RenderSettings) {
        self.settings = settings
        self.layout = LayoutEngine.makeLayout(outputSize: settings.outputSize, settings: settings)
        self.strokeColor = CGColor(
            red: CGFloat(settings.canvas.strokeGray),
            green: CGFloat(settings.canvas.strokeGray),
            blue: CGFloat(settings.canvas.strokeGray),
            alpha: 1
        )
        self.textColor = PlatformColor(white: CGFloat(settings.canvas.textGray), alpha: 1)

        let bg = CGFloat(settings.canvas.backgroundGray)
        backgroundImage = CIImage(color: CIColor(red: bg, green: bg, blue: bg, alpha: 1))
            .cropped(to: layout.canvas)
    }

    nonisolated func makeClip(_ asset: RenderAsset) -> ComposedClip {
        let orientedImage = adjustedImageForOrientationStrategy(asset.image)
        let rects = resolvedFrameRects(for: orientedImage)
        let paper = CGFloat(settings.canvas.paperWhite)
        let fittedPhoto = orientedImage
            .transformed(by: aspectFitTransform(imageExtent: orientedImage.extent, into: rects.photoRect))
            .cropped(to: rects.photoRect)
        let textOverlay = makeTextOverlay(
            text: asset.exif.resolvedPlateText(template: settings.plate.templateText),
            photoRect: rects.photoRect,
            plateTextRect: rects.plateTextRect
        )
        let cardBounds = rects.paperRect.union(rects.plateTextRect).integral
        let motionProfile = settings.enableKenBurns
            ? makeCardMotionProfile(
                assetURL: asset.url,
                imageExtent: orientedImage.extent,
                intensity: settings.kenBurnsIntensity
            )
            : nil
        return ComposedClip(
            paperImage: CIImage(color: CIColor(red: paper, green: paper, blue: paper, alpha: 1))
                .cropped(to: rects.paperRect),
            photoImage: orientedImage,
            staticPhotoImage: settings.enableKenBurns
                ? nil
                : fittedPhoto,
            staticCardImage: makeStaticCardImage(
                paperRect: rects.paperRect,
                fittedPhoto: fittedPhoto,
                textOverlay: textOverlay,
                cardBounds: cardBounds
            ),
            cardMotionProfile: motionProfile,
            textOverlay: textOverlay,
            photoRect: rects.photoRect,
            cardBounds: cardBounds
        )
    }

    nonisolated func composeFrame(layerClips: [(TimelineLayer, ComposedClip)]) -> CIImage {
        var frame = backgroundImage

        for (layer, clip) in layerClips {
            if let card = clip.staticCardImage {
                if settings.enableKenBurns {
                    let animatedCard = makeCardLayer(
                        image: card,
                        bounds: clip.cardBounds,
                        progress: layer.progress,
                        profile: clip.cardMotionProfile ?? fallbackCardMotionProfile(
                            for: layer.clipIndex,
                            intensity: settings.kenBurnsIntensity
                        )
                    )
                    frame = composite(animatedCard, opacity: layer.opacity, over: frame)
                } else {
                    frame = composite(card, opacity: layer.opacity, over: frame)
                }
            } else {
                frame = composite(clip.paperImage, opacity: layer.opacity, over: frame)
                let photo = clip.staticPhotoImage ?? makePhotoLayer(
                    image: clip.photoImage,
                    into: clip.photoRect,
                    progress: layer.progress,
                    index: layer.clipIndex
                )
                frame = composite(photo, opacity: layer.opacity, over: frame)
                frame = composite(clip.textOverlay, opacity: layer.opacity, over: frame)
            }
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

    nonisolated private func makeCardLayer(
        image: CIImage,
        bounds: CGRect,
        progress: Double,
        profile: CardMotionProfile
    ) -> CIImage {
        let eased = easedProgress(progress)
        let scale = profile.startScale + (profile.endScale - profile.startScale) * eased
        let translationX = profile.panX * (eased - 0.5)
        let translationY = profile.panY * (eased - 0.5)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        transform = transform.translatedBy(x: translationX, y: translationY)
        return image.transformed(by: transform)
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

    nonisolated private func makeStaticCardImage(
        paperRect: CGRect,
        fittedPhoto: CIImage,
        textOverlay: CIImage,
        cardBounds: CGRect
    ) -> CIImage {
        let transparent = CIImage(color: .clear).cropped(to: cardBounds)
        let paper = CIImage(color: CIColor(red: CGFloat(settings.canvas.paperWhite), green: CGFloat(settings.canvas.paperWhite), blue: CGFloat(settings.canvas.paperWhite), alpha: 1))
            .cropped(to: paperRect)
        let card = fittedPhoto
            .composited(over: paper.composited(over: transparent))
        return textOverlay
            .cropped(to: cardBounds)
            .composited(over: card)
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
            .font: PlatformDrawing.monospacedFont(ofSize: CGFloat(settings.plate.fontSize)),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]

        if settings.plate.enabled {
            #if canImport(AppKit)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            #else
            UIGraphicsPushContext(context)
            #endif
            (text as NSString).draw(in: plateTextRect, withAttributes: attributes)
            #if canImport(AppKit)
            NSGraphicsContext.restoreGraphicsState()
            #else
            UIGraphicsPopContext()
            #endif
        }

        guard let cgImage = context.makeImage() else {
            return CIImage.empty()
        }

        return CIImage(cgImage: cgImage)
    }

    nonisolated private func resolvedFrameRects(for orientedImage: CIImage) -> (paperRect: CGRect, photoRect: CGRect, plateTextRect: CGRect) {
        let frameMargin = CGFloat(settings.layout.innerPadding)
        let maxPaperRect = layout.paperRect
        let framePlateHeight = (settings.plate.enabled && settings.plate.placement == .frame)
            ? CGFloat(settings.plate.height)
            : 0

        let sideInset = frameMargin
        let topInset = frameMargin
        let bottomInset = frameMargin + framePlateHeight

        let maxPhotoRect = CGRect(
            x: maxPaperRect.minX + sideInset,
            y: maxPaperRect.minY + bottomInset,
            width: max(0, maxPaperRect.width - sideInset * 2),
            height: max(0, maxPaperRect.height - topInset - bottomInset)
        )
        let photoRect = fitRect(source: orientedImage.extent.size, inside: maxPhotoRect)
        let paperRect = CGRect(
            x: photoRect.minX - sideInset,
            y: photoRect.minY - bottomInset,
            width: photoRect.width + sideInset * 2,
            height: photoRect.height + topInset + bottomInset
        ).integral

        let plateTextRect: CGRect
        switch settings.plate.placement {
        case .frame:
            let band = CGRect(
                x: paperRect.minX + sideInset,
                y: paperRect.minY,
                width: max(0, paperRect.width - sideInset * 2),
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

    nonisolated private func easedProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    nonisolated private func makeCardMotionProfile(
        assetURL: URL,
        imageExtent: CGRect,
        intensity: KenBurnsIntensity
    ) -> CardMotionProfile {
        let seed = stableMotionSeed(for: assetURL)
        let aspectRatio = imageExtent.width / max(imageExtent.height, 1)
        let horizontalWeight: CGFloat
        let verticalWeight: CGFloat

        if aspectRatio > 1.18 {
            horizontalWeight = 1.0
            verticalWeight = 0.6
        } else if aspectRatio < 0.84 {
            horizontalWeight = 0.62
            verticalWeight = 1.0
        } else {
            horizontalWeight = 0.82
            verticalWeight = 0.82
        }

        let plateWeight: CGFloat = settings.plate.enabled ? 0.88 : 1.0
        let motionScale = intensity.motionScale * plateWeight
        let motionVariant = Int(seed % 6)
        let reverse = ((seed >> 1) & 1) == 1
        let prefersZoomOut = ((seed >> 2) & 1) == 1
        let horizontalDirection: CGFloat = ((seed >> 3) & 1) == 0 ? 1 : -1
        let verticalDirection: CGFloat = ((seed >> 4) & 1) == 0 ? 1 : -1
        let dampVertical = ((seed >> 5) & 1) == 1
        let diagonalDrift = ((seed >> 6) & 1) == 1
        let baseZoomRange = CGFloat(0.012 + seededUnit(seed, shift: 8) * 0.012)
        let basePanX = CGFloat(6 + seededUnit(seed, shift: 16) * 8) * horizontalWeight
        let basePanY = CGFloat(4 + seededUnit(seed, shift: 24) * 8) * verticalWeight

        let variantScale: CGFloat
        let zoomBehavior: ZoomBehavior
        switch motionVariant {
        case 0:
            variantScale = 0
            zoomBehavior = .hold
        case 1:
            variantScale = 0.45
            zoomBehavior = .in
        case 2:
            variantScale = 0.72
            zoomBehavior = .out
        case 3:
            variantScale = 0.88
            zoomBehavior = prefersZoomOut ? .out : .in
        default:
            variantScale = 1.0
            zoomBehavior = prefersZoomOut ? .out : .in
        }

        let resolvedMotionScale = motionScale * variantScale
        guard resolvedMotionScale > 0.001 else {
            return CardMotionProfile(startScale: 1, endScale: 1, panX: 0, panY: 0)
        }

        let zoomRange = baseZoomRange * resolvedMotionScale
        let panX = basePanX * resolvedMotionScale
        let panY = basePanY * resolvedMotionScale

        return CardMotionProfile(
            startScale: {
                switch zoomBehavior {
                case .hold:
                    return 1.0
                case .in:
                    return 1.0
                case .out:
                    return 1.0 + zoomRange
                }
            }(),
            endScale: {
                switch zoomBehavior {
                case .hold:
                    return 1.0
                case .in:
                    return 1.0 + zoomRange
                case .out:
                    return 1.0
                }
            }(),
            panX: (reverse ? -panX : panX) * horizontalDirection,
            panY: (dampVertical || diagonalDrift ? panY * 0.55 : panY) * verticalDirection
        )
    }

    nonisolated private func fallbackCardMotionProfile(
        for index: Int,
        intensity: KenBurnsIntensity
    ) -> CardMotionProfile {
        let variant = index % 4
        let motionScale = intensity.motionScale
        switch variant {
        case 0:
            return CardMotionProfile(startScale: 1.0, endScale: 1.0 + 0.022 * motionScale, panX: 12 * motionScale, panY: -6 * motionScale)
        case 1:
            return CardMotionProfile(startScale: 1.0 + 0.018 * motionScale, endScale: 1.0, panX: -10 * motionScale, panY: 8 * motionScale)
        case 2:
            return CardMotionProfile(startScale: 1.0, endScale: 1.0 + 0.028 * motionScale, panX: -8 * motionScale, panY: -10 * motionScale)
        default:
            return CardMotionProfile(startScale: 1.0 + 0.014 * motionScale, endScale: 1.0, panX: 10 * motionScale, panY: 6 * motionScale)
        }
    }

    nonisolated private func stableMotionSeed(for url: URL) -> UInt64 {
        let bytes = Array(url.standardizedFileURL.path.utf8)
        return bytes.reduce(1_469_598_103_934_665_603) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    nonisolated private func seededUnit(_ seed: UInt64, shift: UInt64) -> Double {
        let masked = (seed >> shift) & 0xFF
        return Double(masked) / 255.0
    }

    private enum ZoomBehavior {
        case hold
        case `in`
        case out
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
