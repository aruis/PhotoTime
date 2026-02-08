import CoreGraphics
import Foundation

protocol RenderingEngineClient {
    func export(
        imageURLs: [URL],
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws

    func previewFrame(imageURLs: [URL], at second: TimeInterval) async throws -> CGImage
}

extension RenderEngine: RenderingEngineClient {}
