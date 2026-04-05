import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class IOSExportViewModel: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var previewImage: CGImage?
    @Published var previewStatusMessage = "请选择照片后生成预览"
    @Published var previewErrorMessage: String?
    @Published var workflow = ExportWorkflowModel()
    @Published var config = MobileRenderConfiguration()
    @Published var latestOutputURL: URL?
    @Published var saveStatusMessage: String?
    @Published var importStatusMessage: String?
    @Published var reviewIssues: [PreflightIssue] = []

    private let mediaPicker: MediaPicking
    private let exportDelivery: ExportDelivery
    private let makeEngine: (RenderSettings) -> any RenderingEngineClient
    private var didApplyDebugScenario = false

    init(
        mediaPicker: MediaPicking = PhotosPickerMediaPicker(),
        exportDelivery: ExportDelivery = PhotoLibraryExportDelivery(),
        makeEngine: @escaping (RenderSettings) -> any RenderingEngineClient = { settings in
            RenderEngine(settings: settings)
        }
    ) {
        self.mediaPicker = mediaPicker
        self.exportDelivery = exportDelivery
        self.makeEngine = makeEngine
    }

    var canGeneratePreview: Bool {
        !imageURLs.isEmpty && !workflow.isBusy
    }

    var canExport: Bool {
        !imageURLs.isEmpty && !workflow.isBusy
    }

    var selectedCountText: String {
        imageURLs.isEmpty ? "尚未选择照片" : "已选择 \(imageURLs.count) 张照片"
    }

    func importPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        do {
            let urls = try await mediaPicker.materializeImageFiles(from: items)
            imageURLs = urls
            previewImage = nil
            latestOutputURL = nil
            previewErrorMessage = nil
            saveStatusMessage = nil
            importStatusMessage = "已导入 \(urls.count) 张照片"
            reviewIssues = []
            await generatePreview()
        } catch {
            importStatusMessage = error.localizedDescription
        }
    }

    func generatePreview() async {
        guard !imageURLs.isEmpty else { return }
        guard workflow.beginPreview() else { return }
        previewStatusMessage = "预览生成中..."
        previewErrorMessage = nil

        let report = ExportPreflightScanner.scan(imageURLs: imageURLs)
        reviewIssues = report.reviewIssues
        if report.hasBlockingIssues {
            workflow.finishPreviewFailure(message: "照片存在无法导出的阻塞问题。")
            previewErrorMessage = report.blockingIssues.first?.message
            return
        }

        do {
            let engine = makeEngine(interactivePreviewSettings())
            let cgImage = try await engine.previewFrame(imageURLs: imageURLs, at: 0)
            previewImage = cgImage
            previewStatusMessage = "预览已更新"
            workflow.finishPreviewSuccess()
        } catch {
            previewErrorMessage = error.localizedDescription
            workflow.finishPreviewFailure(message: "预览生成失败")
        }
    }

    func exportVideo() async {
        guard !imageURLs.isEmpty else { return }
        guard workflow.beginExport(isRetry: false) else { return }
        latestOutputURL = nil
        saveStatusMessage = nil

        let report = ExportPreflightScanner.scan(imageURLs: imageURLs)
        reviewIssues = report.reviewIssues
        if report.hasBlockingIssues {
            previewErrorMessage = report.blockingIssues.first?.message
            workflow.finishExportFailure(message: "导出失败：存在阻塞问题")
            return
        }

        let outputURL = Self.makeOutputURL()
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let engine = makeEngine(config.makeRenderSettings(bundle: .main))
            try await engine.export(imageURLs: imageURLs, outputURL: outputURL) { [weak self] value in
                Task { @MainActor in
                    self?.workflow.updateExportProgress(value)
                }
            }
            latestOutputURL = outputURL
            workflow.finishExportSuccess(
                message: ExportStatusMessageBuilder.success(
                    outputFilename: outputURL.lastPathComponent,
                    logPath: RenderLogger.resolvedLogURL(for: outputURL).path,
                    audioAttached: false
                )
            )
        } catch {
            previewErrorMessage = error.localizedDescription
            workflow.finishExportFailure(message: "导出失败：\(error.localizedDescription)")
        }
    }

    func saveLatestVideoToPhotos() async {
        guard let latestOutputURL else { return }
        do {
            try await exportDelivery.saveVideoToPhotoLibrary(at: latestOutputURL)
            saveStatusMessage = "已保存到相册"
        } catch {
            saveStatusMessage = error.localizedDescription
        }
    }

    func applyDebugScenarioIfNeeded() async {
        #if DEBUG
        guard !didApplyDebugScenario else { return }
        didApplyDebugScenario = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ios-ui-test-scenario"), arguments.indices.contains(index + 1) else {
            return
        }
        let scenario = arguments[index + 1]
        switch scenario {
        case "ready":
            imageURLs = (try? Self.makeDebugImages()) ?? []
            importStatusMessage = "测试场景：已注入样例照片"
            config.shutterSoundEnabled = true
            if !imageURLs.isEmpty {
                await generatePreview()
            }
        default:
            break
        }
        #endif
    }

    private func interactivePreviewSettings() -> RenderSettings {
        let base = config.makeRenderSettings(bundle: .main)
        let maxDimension: CGFloat = 1280
        let currentMax = max(base.outputSize.width, base.outputSize.height)
        guard currentMax > maxDimension else { return base }

        let scale = maxDimension / currentMax
        return RenderSettings(
            outputSize: CGSize(width: max(2, floor(base.outputSize.width * scale / 2) * 2), height: max(2, floor(base.outputSize.height * scale / 2) * 2)),
            fps: base.fps,
            imageDuration: base.imageDuration,
            transitionDuration: base.transitionDuration,
            transitionEnabled: base.transitionEnabled,
            transitionStyle: base.transitionStyle,
            transitionDipDuration: base.transitionDipDuration,
            orientationStrategy: base.orientationStrategy,
            enableKenBurns: base.enableKenBurns,
            kenBurnsIntensity: base.kenBurnsIntensity,
            prefetchRadius: base.prefetchRadius,
            prefetchMaxConcurrent: base.prefetchMaxConcurrent,
            layout: base.layout,
            plate: base.plate,
            canvas: base.canvas,
            audioTrack: nil,
            shutterSoundTrack: base.shutterSoundTrack
        )
    }

    private static func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ReelFlowiOS-Exports", isDirectory: true)
            .appendingPathComponent("ReelFlow-\(UUID().uuidString).mp4")
    }

    #if DEBUG
    private static func makeDebugImages() throws -> [URL] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReelFlowiOS-Debug", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let colors: [UIColor] = [.systemOrange, .systemTeal]
        return try colors.enumerated().map { index, color in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1440, height: 900))
            let image = renderer.image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: CGSize(width: 1440, height: 900)))
                let title = NSString(string: "Frame \(index + 1)")
                title.draw(
                    at: CGPoint(x: 64, y: 64),
                    withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 72),
                        .foregroundColor: UIColor.white
                    ]
                )
            }
            let url = root.appendingPathComponent("debug-\(index).png")
            guard let data = image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url, options: .atomic)
            return url
        }
    }
    #endif
}
