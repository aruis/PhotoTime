import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var outputURL: URL?
    @Published var previewImage: NSImage?
    @Published var previewSecond: Double = 0
    @Published var previewStatusMessage: String = "未生成预览"
    @Published var previewErrorMessage: String?
    @Published var failedAssetNames: [String] = []
    @Published var preflightReport: PreflightReport?
    @Published var skippedAssetNamesFromPreflight: [String] = []
    @Published var config = RenderEditorConfig()
    @Published var recoveryAdvice: RecoveryAdvice?
    @Published private var workflow = ExportWorkflowModel()

    private let makeEngine: (RenderSettings) -> any RenderingEngineClient
    private var exportTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var lastFailedRequest: ExportRequest?
    private var pendingRequestFromPreflight: ExportRequest?
    private var lastLogURL: URL?
    private var lastSuccessfulOutputURL: URL?

    init(makeEngine: @escaping (RenderSettings) -> any RenderingEngineClient = { settings in
        RenderEngine(settings: settings)
    }) {
        self.makeEngine = makeEngine
        applyUITestScenarioIfNeeded()
    }

    var isBusy: Bool {
        workflow.isBusy
    }

    var isExporting: Bool {
        workflow.isExporting
    }

    var isPreviewGenerating: Bool {
        workflow.state == .previewing
    }

    var progress: Double {
        workflow.progress
    }

    var statusMessage: String {
        workflow.statusMessage
    }

    var validationMessage: String? {
        invalidSettingsMessage
    }

    var hasFailureCard: Bool {
        workflow.state == .failed && recoveryAdvice != nil
    }

    var hasSuccessCard: Bool {
        workflow.state == .succeeded && lastSuccessfulOutputURL != nil
    }

    var latestLogPath: String? {
        lastLogURL?.path
    }

    var latestOutputFilename: String? {
        lastSuccessfulOutputURL?.lastPathComponent
    }

    var canRetryLastExport: Bool {
        !isBusy && lastFailedRequest != nil
    }

    var hasBlockingPreflightIssues: Bool {
        preflightReport?.hasBlockingIssues == true
    }

    var actionAvailability: ExportActionAvailability {
        ExportActionAvailability(
            workflowState: workflow.state,
            hasRetryTask: lastFailedRequest != nil
        )
    }

    var configSignature: String {
        [
            "\(config.outputWidth)",
            "\(config.outputHeight)",
            "\(config.fps)",
            String(format: "%.3f", config.imageDuration),
            String(format: "%.3f", config.transitionDuration),
            config.enableCrossfade ? "1" : "0",
            config.enableKenBurns ? "1" : "0",
            "\(config.prefetchRadius)",
            "\(config.prefetchMaxConcurrent)"
        ].joined(separator: "|")
    }

    func chooseImages() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageURLs = panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        previewImage = nil
        previewSecond = 0
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        preflightReport = nil
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        workflow.setIdleMessage("已选择 \(imageURLs.count) 张图片")

        // Generate first preview frame automatically to avoid blank preview area after import.
        if !imageURLs.isEmpty, isSettingsValid {
            generatePreview()
        }
    }

    func chooseOutput() {
        guard !isBusy else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "PhotoTime-Output.mp4"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        workflow.setIdleMessage("导出路径: \(url.path)")
    }

    func importTemplate() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let template = try JSONDecoder().decode(RenderTemplate.self, from: data)
            guard template.schemaVersion > 0, template.schemaVersion <= RenderTemplate.currentSchemaVersion else {
                workflow.setIdleMessage("模板版本不支持: v\(template.schemaVersion)")
                return
            }
            apply(template: template)
            workflow.setIdleMessage("已导入模板: \(url.lastPathComponent)")
        } catch {
            workflow.setIdleMessage("模板导入失败: \(error.localizedDescription)")
        }
    }

    func exportTemplate() {
        guard !isBusy else { return }
        config.clampToSafeRange()

        guard isSettingsValid else {
            workflow.setIdleMessage(invalidSettingsMessage ?? "参数无效")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PhotoTime-Template-v\(RenderTemplate.currentSchemaVersion).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config.template)
            try data.write(to: url, options: .atomic)
            workflow.setIdleMessage("模板已保存: \(url.path)")
        } catch {
            workflow.setIdleMessage("模板保存失败: \(error.localizedDescription)")
        }
    }

    func export() {
        guard !isBusy else { return }
        guard !imageURLs.isEmpty else {
            workflow.setIdleMessage("请先选择图片")
            return
        }
        guard let outputURL else {
            workflow.setIdleMessage("请先选择导出路径")
            return
        }

        config.clampToSafeRange()
        guard isSettingsValid else {
            workflow.setIdleMessage(invalidSettingsMessage ?? "参数无效")
            return
        }

        let request = ExportRequest(
            imageURLs: imageURLs,
            outputURL: outputURL,
            settings: config.renderSettings
        )

        let report = ExportPreflightScanner.scan(imageURLs: request.imageURLs)
        preflightReport = report
        skippedAssetNamesFromPreflight = []

        guard !report.hasBlockingIssues else {
            pendingRequestFromPreflight = request
            workflow.setIdleMessage(
                "导出前检查发现 \(report.blockingIssues.count) 个必须修复问题。可点击“跳过问题素材并导出”。"
            )
            return
        }

        pendingRequestFromPreflight = nil
        startExport(request: request, fromRetry: false)
    }

    func exportSkippingPreflightIssues() {
        guard !isBusy else { return }
        guard let request = pendingRequestFromPreflight, let report = preflightReport else { return }

        let blockingIndexes = report.blockingIndexes
        let filtered = request.imageURLs.enumerated().compactMap { pair -> URL? in
            blockingIndexes.contains(pair.offset) ? nil : pair.element
        }

        guard !filtered.isEmpty else {
            workflow.setIdleMessage("问题素材过多，过滤后没有可导出的图片。")
            return
        }

        skippedAssetNamesFromPreflight = request.imageURLs.enumerated().compactMap { pair -> String? in
            blockingIndexes.contains(pair.offset) ? pair.element.lastPathComponent : nil
        }

        pendingRequestFromPreflight = nil
        let filteredRequest = ExportRequest(
            imageURLs: filtered,
            outputURL: request.outputURL,
            settings: request.settings
        )
        workflow.setIdleMessage("已跳过 \(skippedAssetNamesFromPreflight.count) 张问题素材，开始导出。")
        startExport(request: filteredRequest, fromRetry: false)
    }

    func retryLastExport() {
        guard !isBusy else { return }
        guard let request = lastFailedRequest else {
            workflow.setIdleMessage("没有可重试的导出任务")
            return
        }
        startExport(request: request, fromRetry: true)
    }

    func generatePreview() {
        guard previewTask == nil else { return }
        guard !imageURLs.isEmpty else {
            workflow.setIdleMessage("请先选择图片")
            return
        }

        config.clampToSafeRange()
        guard isSettingsValid else {
            workflow.setIdleMessage(invalidSettingsMessage ?? "参数无效")
            return
        }

        guard workflow.beginPreview() else { return }
        previewStatusMessage = "预览生成中..."
        previewErrorMessage = nil

        let urls = imageURLs
        let settings = config.renderSettings
        let second = previewSecond

        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { previewTask = nil }

            do {
                let engine = makeEngine(settings)
                let cgImage = try await engine.previewFrame(imageURLs: urls, at: second)
                previewImage = NSImage(cgImage: cgImage, size: settings.outputSize)
                previewStatusMessage = "预览已更新 (\(String(format: "%.2f", second))s)"
                previewErrorMessage = nil
                workflow.finishPreviewSuccess()
            } catch {
                if let renderError = error as? RenderEngineError {
                    previewStatusMessage = "预览生成失败"
                    previewErrorMessage = "[\(renderError.code)] \(renderError.localizedDescription)"
                    workflow.finishPreviewFailure(message: "[\(renderError.code)] \(renderError.localizedDescription)")
                } else {
                    previewStatusMessage = "预览生成失败"
                    previewErrorMessage = error.localizedDescription
                    workflow.finishPreviewFailure(message: error.localizedDescription)
                }
            }
        }
    }

    func schedulePreviewRegeneration() {
        guard !isBusy else { return }
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
        workflow.requestCancel()
    }

    func handleConfigChanged() {
        config.clampToSafeRange()
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "参数已变更，预览将自动刷新"
        schedulePreviewRegeneration()
    }

    private func startExport(request: ExportRequest, fromRetry: Bool) {
        guard workflow.beginExport(isRetry: fromRetry) else { return }

        failedAssetNames = []
        recoveryAdvice = nil

        let urls = request.imageURLs
        let destination = request.outputURL
        let settings = request.settings
        let logURL = destination.deletingPathExtension().appendingPathExtension("render.log")
        lastLogURL = logURL

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let engine = makeEngine(settings)
                try await engine.export(imageURLs: urls, outputURL: destination) { value in
                    Task { @MainActor in
                        self.workflow.updateExportProgress(value)
                    }
                }

                workflow.finishExportSuccess(
                    message: "导出完成: \(destination.lastPathComponent)\n日志: \(logURL.path)"
                )
                lastSuccessfulOutputURL = destination
                failedAssetNames = []
                recoveryAdvice = nil
                lastFailedRequest = nil
            } catch {
                lastFailedRequest = request
                let failedNames = Self.failedAssetNames(from: error, urls: urls)
                failedAssetNames = failedNames
                let advice = ExportRecoveryAdvisor.advice(for: error, failedAssetNames: failedNames)
                recoveryAdvice = advice
                workflow.finishExportFailure(
                    message: makeErrorStatus(
                        error: error,
                        logURL: logURL,
                        failedAssetNames: failedNames,
                        advice: advice
                    )
                )
            }

            exportTask = nil
        }
    }

    func openLatestLog() {
        guard let url = lastLogURL else {
            workflow.setIdleMessage("暂无日志文件可打开")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openLatestOutputDirectory() {
        let targetURL = lastSuccessfulOutputURL ?? outputURL
        guard let url = targetURL else {
            workflow.setIdleMessage("暂无可打开的输出目录")
            return
        }
        NSWorkspace.shared.open(url.deletingLastPathComponent())
    }

    func performRecoveryAction() {
        guard let advice = recoveryAdvice else { return }

        switch advice.action {
        case .retryExport:
            retryLastExport()
        case .reselectAssets:
            chooseImages()
        case .reauthorizeAccess:
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(settingsURL)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        case .freeDiskSpace:
            openLatestOutputDirectory()
        case .adjustSettings:
            workflow.setIdleMessage("请调整导出参数后再重试。")
        case .inspectLog:
            openLatestLog()
        }
    }

    private func applyUITestScenarioIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-scenario"), arguments.indices.contains(flagIndex + 1) else {
            return
        }

        let scenario = arguments[flagIndex + 1]
        switch scenario {
        case "failure":
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-failure.render.log")
            failedAssetNames = ["broken-sample.jpg"]
            recoveryAdvice = RecoveryAdvice(action: .retryExport, message: "测试场景：可直接重试导出。")
            workflow.finishExportFailure(
                message: "[E_EXPORT_PIPELINE] 测试失败\n建议动作: 重试上次导出\n建议: 测试场景\n日志: /tmp/phototime-ui-failure.render.log"
            )
        case "success":
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-success.render.log")
            lastSuccessfulOutputURL = URL(fileURLWithPath: "/tmp/PhotoTime-UI-Success.mp4")
            workflow.finishExportSuccess(
                message: "导出完成: PhotoTime-UI-Success.mp4\n日志: /tmp/phototime-ui-success.render.log"
            )
        case "invalid":
            config.outputWidth = 100
            config.outputHeight = 100
            workflow.setIdleMessage("测试场景：参数无效")
        default:
            break
        }
    }

    private var isSettingsValid: Bool {
        invalidSettingsMessage == nil
    }

    private var invalidSettingsMessage: String? {
        config.invalidMessage
    }

    private func apply(template: RenderTemplate) {
        config = RenderEditorConfig(template: template)
        previewSecond = min(previewSecond, previewMaxSecond)

        if !imageURLs.isEmpty, isSettingsValid {
            generatePreview()
        }
    }

    var previewMaxSecond: Double {
        guard !imageURLs.isEmpty else { return 0 }
        let settings = config.renderSettings
        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.effectiveTransitionDuration
        )
        return max(timeline.totalDuration - 0.001, 0)
    }

    private static func failedAssetNames(from error: Error, urls: [URL]) -> [String] {
        guard let renderError = error as? RenderEngineError else { return [] }
        guard case let .assetLoadFailed(index, _) = renderError else { return [] }
        guard urls.indices.contains(index) else { return ["index=\(index)"] }
        return [urls[index].lastPathComponent]
    }

    private func makeErrorStatus(
        error: Error,
        logURL: URL,
        failedAssetNames: [String],
        advice: RecoveryAdvice
    ) -> String {
        let head: String
        if let renderError = error as? RenderEngineError {
            head = "[\(renderError.code)] \(renderError.localizedDescription)"
        } else {
            head = error.localizedDescription
        }

        if failedAssetNames.isEmpty {
            return "\(head)\n建议动作: \(advice.action.title)\n建议: \(advice.message)\n日志: \(logURL.path)"
        }

        let list = failedAssetNames.joined(separator: ", ")
        return "\(head)\n失败素材: \(list)\n建议动作: \(advice.action.title)\n建议: \(advice.message)\n日志: \(logURL.path)"
    }
}

private struct ExportRequest {
    let imageURLs: [URL]
    let outputURL: URL
    let settings: RenderSettings
}

struct ContentView: View {
    @StateObject private var viewModel = ExportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PhotoTime MVP")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 12) {
                GroupBox("主操作") {
                    HStack(spacing: 10) {
                        Button("选择图片") { viewModel.chooseImages() }
                            .accessibilityIdentifier("primary_select_images")
                            .disabled(!viewModel.actionAvailability.canSelectImages)
                        Button("选择导出路径") { viewModel.chooseOutput() }
                            .accessibilityIdentifier("primary_select_output")
                            .disabled(!viewModel.actionAvailability.canSelectOutput)
                        Button("导出 MP4") { viewModel.export() }
                            .accessibilityIdentifier("primary_export")
                            .disabled(!viewModel.actionAvailability.canStartExport)
                        Button("取消导出") { viewModel.cancelExport() }
                            .accessibilityIdentifier("primary_cancel")
                            .disabled(!viewModel.actionAvailability.canCancelExport)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("group_primary_actions")

                GroupBox("辅助操作") {
                    HStack(spacing: 10) {
                        Button("生成预览") { viewModel.generatePreview() }
                            .accessibilityIdentifier("secondary_preview")
                            .disabled(!viewModel.actionAvailability.canGeneratePreview)
                        Button("导入模板") { viewModel.importTemplate() }
                            .accessibilityIdentifier("secondary_import_template")
                            .disabled(!viewModel.actionAvailability.canImportTemplate)
                        Button("保存模板") { viewModel.exportTemplate() }
                            .accessibilityIdentifier("secondary_export_template")
                            .disabled(!viewModel.actionAvailability.canSaveTemplate)
                        Button("重试上次导出") { viewModel.retryLastExport() }
                            .accessibilityIdentifier("secondary_retry_export")
                            .disabled(!viewModel.actionAvailability.canRetryExport)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("group_secondary_actions")
            }

            if let report = viewModel.preflightReport, !report.issues.isEmpty {
                GroupBox("导出前检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "已扫描 \(report.scannedCount) 张，必须修复 \(report.blockingIssues.count) 项，建议关注 \(report.reviewIssues.count) 项"
                        )
                        .font(.callout)

                        ForEach(Array(report.issues.prefix(6)), id: \.index) { issue in
                            let tag = issue.severity == .mustFix ? "必须修复" : "建议关注"
                            Text("[\(tag)] \(issue.fileName): \(issue.message)")
                                .font(.caption)
                        }

                        if viewModel.hasBlockingPreflightIssues {
                            Button("跳过问题素材并导出") {
                                viewModel.exportSkippingPreflightIssues()
                            }
                            .disabled(viewModel.isBusy)
                        }

                        if !viewModel.skippedAssetNamesFromPreflight.isEmpty {
                            Text("已跳过: \(viewModel.skippedAssetNamesFromPreflight.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }

            GroupBox("预览") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("时间: \(viewModel.previewSecond, specifier: "%.2f")s")
                        Slider(
                            value: $viewModel.previewSecond,
                            in: 0...max(viewModel.previewMaxSecond, 0.001)
                        )
                        .onChange(of: viewModel.previewSecond) { _, _ in
                            viewModel.schedulePreviewRegeneration()
                        }
                        .disabled(viewModel.isBusy || viewModel.imageURLs.isEmpty)
                    }

                    if let preview = viewModel.previewImage {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .padding(.vertical, 4)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                            .overlay(
                                Text("暂无预览画面")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            )
                    }

                    HStack(spacing: 8) {
                        if viewModel.isPreviewGenerating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.previewStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let previewError = viewModel.previewErrorMessage {
                        Text("预览错误: \(previewError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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

            if viewModel.hasFailureCard, let advice = viewModel.recoveryAdvice {
                GroupBox("导出失败（可恢复）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("推荐动作: \(advice.action.title)")
                            .font(.subheadline.weight(.semibold))
                        Text(advice.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button(advice.action.title) { viewModel.performRecoveryAction() }
                                .accessibilityIdentifier("failure_primary_action")
                                .disabled(viewModel.isBusy)
                            Button("查看日志") { viewModel.openLatestLog() }
                                .accessibilityIdentifier("failure_open_log")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("failure_card")
            }

            if viewModel.hasSuccessCard {
                GroupBox("导出完成（下一步）") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let filename = viewModel.latestOutputFilename {
                            Text("文件: \(filename)")
                                .font(.callout)
                        }
                        if let logPath = viewModel.latestLogPath {
                            Text("日志: \(logPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 10) {
                            Button("再次导出") { viewModel.export() }
                                .accessibilityIdentifier("success_export_again")
                                .disabled(viewModel.isBusy)
                            Button("打开输出目录") { viewModel.openLatestOutputDirectory() }
                                .accessibilityIdentifier("success_open_output")
                            Button("查看日志") { viewModel.openLatestLog() }
                                .accessibilityIdentifier("success_open_log")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("success_card")
            }

            if !viewModel.failedAssetNames.isEmpty {
                GroupBox("失败素材") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.failedAssetNames, id: \.self) { name in
                            Text(name)
                                .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }

            GroupBox("性能设置") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("预取半径: \(viewModel.config.prefetchRadius)", value: $viewModel.config.prefetchRadius, in: RenderEditorConfig.prefetchRadiusRange)
                        .disabled(viewModel.isBusy)
                    Stepper("预取并发: \(viewModel.config.prefetchMaxConcurrent)", value: $viewModel.config.prefetchMaxConcurrent, in: RenderEditorConfig.prefetchMaxConcurrentRange)
                        .disabled(viewModel.isBusy)
                }
                .padding(.vertical, 4)
            }

            GroupBox("导出设置") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Stepper("宽: \(viewModel.config.outputWidth)", value: $viewModel.config.outputWidth, in: RenderEditorConfig.outputWidthRange, step: 2)
                            .disabled(viewModel.isBusy)
                        Stepper("高: \(viewModel.config.outputHeight)", value: $viewModel.config.outputHeight, in: RenderEditorConfig.outputHeightRange, step: 2)
                            .disabled(viewModel.isBusy)
                    }
                    Stepper("FPS: \(viewModel.config.fps)", value: $viewModel.config.fps, in: RenderEditorConfig.fpsRange)
                        .disabled(viewModel.isBusy)
                    HStack(spacing: 12) {
                        Text("单图时长: \(viewModel.config.imageDuration, specifier: "%.2f")s")
                        Slider(value: $viewModel.config.imageDuration, in: RenderEditorConfig.imageDurationRange, step: 0.1)
                            .disabled(viewModel.isBusy)
                    }
                    HStack(spacing: 12) {
                        Toggle("启用淡入淡出转场", isOn: $viewModel.config.enableCrossfade)
                            .disabled(viewModel.isBusy)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        Text("转场时长: \(viewModel.config.transitionDuration, specifier: "%.2f")s")
                        Slider(value: $viewModel.config.transitionDuration, in: RenderEditorConfig.transitionDurationRange, step: 0.05)
                            .disabled(viewModel.isBusy || !viewModel.config.enableCrossfade)
                    }
                    Toggle("启用 Ken Burns", isOn: $viewModel.config.enableKenBurns)
                        .disabled(viewModel.isBusy)

                    if let validationMessage = viewModel.validationMessage {
                        Text("参数校验: \(validationMessage)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settings_validation_message")
                    }
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
        .onChange(of: viewModel.configSignature) { _, _ in
            viewModel.handleConfigChanged()
        }
    }
}

#Preview {
    ContentView()
}
