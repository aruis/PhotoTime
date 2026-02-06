import CoreGraphics
import Foundation

struct FrameLayout {
    let canvas: CGRect
    let paperRect: CGRect
    let photoRect: CGRect
    let plateTextRect: CGRect
}

enum LayoutEngine {
    nonisolated static func makeLayout(outputSize: CGSize) -> FrameLayout {
        let canvas = CGRect(origin: .zero, size: outputSize)

        let horizontalMargin: CGFloat = 180
        let topMargin: CGFloat = 72
        let bottomMargin: CGFloat = 96
        let plateHeight: CGFloat = 96
        let innerPadding: CGFloat = 24

        let paperWidth = outputSize.width - horizontalMargin * 2
        let paperHeight = outputSize.height - topMargin - bottomMargin
        let paperRect = CGRect(
            x: (outputSize.width - paperWidth) / 2,
            y: bottomMargin,
            width: paperWidth,
            height: paperHeight
        )

        let photoRect = CGRect(
            x: paperRect.minX + innerPadding,
            y: paperRect.minY + plateHeight + innerPadding,
            width: paperRect.width - innerPadding * 2,
            height: paperRect.height - plateHeight - innerPadding * 2
        )

        let plateTextRect = CGRect(
            x: paperRect.minX + innerPadding,
            y: paperRect.minY + 18,
            width: paperRect.width - innerPadding * 2,
            height: plateHeight - 36
        )

        return FrameLayout(canvas: canvas, paperRect: paperRect, photoRect: photoRect, plateTextRect: plateTextRect)
    }
}
