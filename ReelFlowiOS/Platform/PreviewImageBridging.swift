import SwiftUI
import CoreGraphics

protocol PreviewImageBridging {
    func makeImage(from cgImage: CGImage) -> Image
}

struct SwiftUIPreviewImageBridge: PreviewImageBridging {
    func makeImage(from cgImage: CGImage) -> Image {
        Image(decorative: cgImage, scale: 1)
    }
}
