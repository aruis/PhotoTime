import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var outputURL: URL?
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var statusMessage = "请选择图片并设置导出路径"
    @Published var previewImage: NSImage?
    @Published var previewSecond: Double = 0
    @Published var outputWidth: Int = 1920
    @Published var outputHeight: Int = 1080
    @Published var fps: Int = 30
    @Published var imageDuration: Double = 3.0
    @Published var transitionDuration: Double = 0.6
    @Published var enableKenBurns: Bool = true
    @Published var prefetchRadius: Int = 1
    @Published var prefetchMaxConcurrent: Int = 2
    private var exportTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageURLs = panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        previewImage = nil
        previewSecond = 0
        statusMessage = "已选择 \(imageURLs.count) 张图片"
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "PhotoTime-Output.mp4"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        statusMessage = "导出路径: \(url.path)"
    }

    func importTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let template = try JSONDecoder().decode(RenderTemplate.self, from: data)
            guard template.schemaVersion == RenderTemplate.currentSchemaVersion else {
                statusMessage = "模板版本不支持: v\(template.schemaVersion)"
                return
            }
            apply(template: template)
            statusMessage = "已导入模板: \(url.lastPathComponent)"
        } catch {
            statusMessage = "模板导入失败: \(error.localizedDescription)"
        }
    }

    func exportTemplate() {
        guard isSettingsValid else {
            statusMessage = invalidSettingsMessage ?? "参数无效"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PhotoTime-Template-v\(RenderTemplate.currentSchemaVersion).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let template = makeSettings().template
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(template)
            try data.write(to: url, options: .atomic)
            statusMessage = "模板已保存: \(url.path)"
        } catch {
            statusMessage = "模板保存失败: \(error.localizedDescription)"
        }
    }

    func export() {
        guard !isExporting else { return }
        guard !imageURLs.isEmpty else {
            statusMessage = "请先选择图片"
            return
        }
        guard let outputURL else {
            statusMessage = "请先选择导出路径"
            return
        }
        guard isSettingsValid else {
            statusMessage = invalidSettingsMessage ?? "参数无效"
            return
        }

        isExporting = true
        progress = 0
        statusMessage = "开始导出..."

        let urls = imageURLs
        let destination = outputURL
        let logURL = destination.deletingPathExtension().appendingPathExtension("render.log")

        let settings = makeSettings()

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let engine = RenderEngine(settings: settings)
                try await engine.export(imageURLs: urls, outputURL: destination) { value in
                    Task { @MainActor in
                        self.progress = value
                    }
                }

                statusMessage = "导出完成: \(destination.lastPathComponent)\n日志: \(logURL.path)"
            } catch {
                statusMessage = makeErrorStatus(error: error, logURL: logURL)
            }

            isExporting = false
            exportTask = nil
        }
    }

    func generatePreview() {
        guard previewTask == nil else { return }
        guard !imageURLs.isEmpty else {
            statusMessage = "请先选择图片"
            return
        }
        guard isSettingsValid else {
            statusMessage = invalidSettingsMessage ?? "参数无效"
            return
        }

        let urls = imageURLs
        let settings = makeSettings()
        let second = previewSecond
        statusMessage = "生成预览中..."

        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { previewTask = nil }

            do {
                let engine = RenderEngine(settings: settings)
                let cgImage = try await engine.previewFrame(imageURLs: urls, at: second)
                previewImage = NSImage(cgImage: cgImage, size: settings.outputSize)
                statusMessage = "预览已更新"
            } catch {
                if let renderError = error as? RenderEngineError {
                    statusMessage = "[\(renderError.code)] \(renderError.localizedDescription)"
                } else {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func schedulePreviewRegeneration() {
        guard !isExporting else { return }
        guard !imageURLs.isEmpty else { return }
        guard isSettingsValid else { return }
        guard previewTask == nil else { return }

        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                previewTask = nil
                return
            }
            previewTask = nil
            generatePreview()
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        exportTask?.cancel()
        statusMessage = "正在取消导出..."
    }

    private var isSettingsValid: Bool {
        invalidSettingsMessage == nil
    }

    private var invalidSettingsMessage: String? {
        if outputWidth < 640 || outputHeight < 360 {
            return "分辨率过低，请至少设置为 640x360"
        }
        if fps < 1 {
            return "FPS 必须大于 0"
        }
        if imageDuration <= 0 {
            return "单图时长必须大于 0"
        }
        if transitionDuration < 0 || transitionDuration >= imageDuration {
            return "转场时长必须满足 0 <= 转场 < 单图时长"
        }
        return nil
    }

    private func makeSettings() -> RenderSettings {
        RenderSettings(
            outputSize: CGSize(width: outputWidth, height: outputHeight),
            fps: Int32(fps),
            imageDuration: imageDuration,
            transitionDuration: transitionDuration,
            enableKenBurns: enableKenBurns,
            prefetchRadius: prefetchRadius,
            prefetchMaxConcurrent: prefetchMaxConcurrent
        )
    }

    private func apply(template: RenderTemplate) {
        let settings = RenderSettings(template: template)
        outputWidth = min(max(Int(settings.outputSize.width.rounded()), 640), 3840)
        outputHeight = min(max(Int(settings.outputSize.height.rounded()), 360), 2160)
        fps = min(max(Int(settings.fps), 1), 60)
        imageDuration = min(max(settings.imageDuration, 0.2), 10.0)
        transitionDuration = min(max(settings.transitionDuration, 0), 2.0)
        if transitionDuration >= imageDuration {
            transitionDuration = max(0, imageDuration - 0.05)
        }
        enableKenBurns = settings.enableKenBurns
        prefetchRadius = min(max(settings.prefetchRadius, 0), 4)
        prefetchMaxConcurrent = min(max(settings.prefetchMaxConcurrent, 1), 8)
        previewSecond = min(previewSecond, previewMaxSecond)
    }

    var previewMaxSecond: Double {
        guard !imageURLs.isEmpty else { return 0 }
        let settings = makeSettings()
        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.transitionDuration
        )
        return max(timeline.totalDuration - 0.001, 0)
    }

    private func makeErrorStatus(error: Error, logURL: URL) -> String {
        if let renderError = error as? RenderEngineError {
            return "[\(renderError.code)] \(renderError.localizedDescription)\n日志: \(logURL.path)"
        }
        return "\(error.localizedDescription)\n日志: \(logURL.path)"
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ExportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PhotoTime MVP")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button("选择图片") { viewModel.chooseImages() }
                    .disabled(viewModel.isExporting)
                Button("选择导出路径") { viewModel.chooseOutput() }
                    .disabled(viewModel.isExporting)
                Button("导入模板") { viewModel.importTemplate() }
                    .disabled(viewModel.isExporting)
                Button("保存模板") { viewModel.exportTemplate() }
                    .disabled(viewModel.isExporting)
                Button("生成预览") { viewModel.generatePreview() }
                    .disabled(viewModel.isExporting)
                Button("导出 MP4") { viewModel.export() }
                    .disabled(viewModel.isExporting)
                Button("取消导出") { viewModel.cancelExport() }
                    .disabled(!viewModel.isExporting)
            }

            if let preview = viewModel.previewImage {
                GroupBox("预览") {
                    HStack(spacing: 12) {
                        Text("时间: \(viewModel.previewSecond, specifier: "%.2f")s")
                        Slider(
                            value: $viewModel.previewSecond,
                            in: 0...max(viewModel.previewMaxSecond, 0.001)
                        )
                        .onChange(of: viewModel.previewSecond) { _, _ in
                            viewModel.schedulePreviewRegeneration()
                        }
                        .disabled(viewModel.isExporting || viewModel.imageURLs.isEmpty)
                    }
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .padding(.vertical, 4)
                }
            }

            if !viewModel.imageURLs.isEmpty {
                Text("已选文件")
                    .font(.headline)
                List(viewModel.imageURLs, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
                .frame(height: 220)
            }

            if viewModel.isExporting {
                ProgressView(value: viewModel.progress)
                    .frame(maxWidth: .infinity)
            }

            GroupBox("性能设置") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("预取半径: \(viewModel.prefetchRadius)", value: $viewModel.prefetchRadius, in: 0...4)
                        .disabled(viewModel.isExporting)
                    Stepper("预取并发: \(viewModel.prefetchMaxConcurrent)", value: $viewModel.prefetchMaxConcurrent, in: 1...8)
                        .disabled(viewModel.isExporting)
                }
                .padding(.vertical, 4)
            }

            GroupBox("导出设置") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Stepper("宽: \(viewModel.outputWidth)", value: $viewModel.outputWidth, in: 640...3840, step: 2)
                            .disabled(viewModel.isExporting)
                        Stepper("高: \(viewModel.outputHeight)", value: $viewModel.outputHeight, in: 360...2160, step: 2)
                            .disabled(viewModel.isExporting)
                    }
                    Stepper("FPS: \(viewModel.fps)", value: $viewModel.fps, in: 1...60)
                        .disabled(viewModel.isExporting)
                    HStack(spacing: 12) {
                        Text("单图时长: \(viewModel.imageDuration, specifier: "%.2f")s")
                        Slider(value: $viewModel.imageDuration, in: 0.2...10.0, step: 0.1)
                            .disabled(viewModel.isExporting)
                    }
                    HStack(spacing: 12) {
                        Text("转场时长: \(viewModel.transitionDuration, specifier: "%.2f")s")
                        Slider(value: $viewModel.transitionDuration, in: 0.0...2.0, step: 0.05)
                            .disabled(viewModel.isExporting)
                    }
                    Toggle("启用 Ken Burns", isOn: $viewModel.enableKenBurns)
                        .disabled(viewModel.isExporting)
                }
                .padding(.vertical, 4)
            }

            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

#Preview {
    ContentView()
}
