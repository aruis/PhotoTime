import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTime

struct ExportPreflightTests {
    @Test
    func preflightDetectsMissingFileAsBlocking() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingURL = tempDir.appendingPathComponent("missing.jpg")
        let report = ExportPreflightScanner.scan(imageURLs: [missingURL])

        #expect(report.scannedCount == 1)
        #expect(report.hasBlockingIssues)
        #expect(report.blockingIssues.count == 1)
        #expect(report.blockingIssues.first?.fileName == "missing.jpg")
    }

    @Test
    func preflightDetectsCorruptedImageAsBlocking() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badURL = tempDir.appendingPathComponent("bad.png")
        try Data("not-image".utf8).write(to: badURL, options: .atomic)

        let report = ExportPreflightScanner.scan(imageURLs: [badURL])
        #expect(report.hasBlockingIssues)
        #expect(report.blockingIssues.count == 1)
    }

    @Test
    func preflightMarksLowResolutionAsReviewIssue() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lowURL = tempDir.appendingPathComponent("low.png")
        try Self.writeImage(to: lowURL, width: 200, height: 200)

        let report = ExportPreflightScanner.scan(imageURLs: [lowURL])
        #expect(!report.hasBlockingIssues)
        #expect(report.reviewIssues.count == 1)
        #expect(report.reviewIssues.first?.severity == .shouldReview)
    }

    @Test
    func preflightPassesNormalImage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimePreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let goodURL = tempDir.appendingPathComponent("good.png")
        try Self.writeImage(to: goodURL, width: 1200, height: 800)

        let report = ExportPreflightScanner.scan(imageURLs: [goodURL])
        #expect(report.issues.isEmpty)
        #expect(!report.hasBlockingIssues)
    }

    private static func writeImage(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ExportPreflightTests", code: 1)
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw NSError(domain: "ExportPreflightTests", code: 2)
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ExportPreflightTests", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ExportPreflightTests", code: 4)
        }
    }
}
