import CoreGraphics
import Foundation

struct FrameLayout {
    let canvas: CGRect
    let paperRect: CGRect
    let photoRect: CGRect
    let plateTextRect: CGRect
}

enum LayoutEngine {
    nonisolated static func makeLayout(outputSize: CGSize, settings: RenderSettings) -> FrameLayout {
        let canvas = CGRect(origin: .zero, size: outputSize)

        let horizontalMargin = CGFloat(settings.layout.horizontalMargin)
        let topMargin = CGFloat(settings.layout.topMargin)
        let bottomMargin = CGFloat(settings.layout.bottomMargin)
        let innerPadding = CGFloat(settings.layout.innerPadding)

        let paperWidth = outputSize.width - horizontalMargin * 2
        let paperHeight = outputSize.height - topMargin - bottomMargin
        let paperRect = CGRect(
            x: (outputSize.width - paperWidth) / 2,
            y: bottomMargin,
            width: paperWidth,
            height: paperHeight
        )

        // Frame should directly wrap the photo; canvas relation is controlled by top/bottom/horizontal margins.
        let photoRect = paperRect

        let plateHeight = settings.plate.enabled ? CGFloat(settings.plate.height) : 0
        let plateTextHeight = max(plateHeight - CGFloat(settings.plate.baselineOffset) * 2, 0)
        let plateTextRect = CGRect(
            x: photoRect.minX + innerPadding,
            y: photoRect.minY + CGFloat(settings.plate.baselineOffset),
            width: photoRect.width - innerPadding * 2,
            height: plateTextHeight
        )

        return FrameLayout(canvas: canvas, paperRect: paperRect, photoRect: photoRect, plateTextRect: plateTextRect)
    }
}
