import CoreGraphics
import Foundation

enum PlaceholderImageFactory {
    static func makeSolidImage(size: CGSize, gray: CGFloat = 0.88) -> CGImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        return context.makeImage()
    }
}
