import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ExportViewModel {
    func chooseOutput() {
        guard !isBusy else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "PhotoTime-Output.mp4"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        hasUserSelectedOutputURL = true
        workflow.setIdleMessage("导出路径: \(url.path)")
    }

    static func defaultOutputURL() -> URL? {
        let fileName = "PhotoTime-Output.mp4"
        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            return movies.appendingPathComponent(fileName)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent(fileName)
        }
        return nil
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
        guard let outputURL = resolveOutputURLForExport(original: outputURL) else { return }

        config.clampToSafeRange()
        guard isSettingsValid else {
            workflow.setIdleMessage(invalidSettingsMessage ?? "参数无效")
            return
        }
        if config.audioEnabled {
            let audioURL = URL(fileURLWithPath: config.audioFilePath)
            if let message = AudioTrackValidation.validate(url: audioURL) {
                audioStatusMessage = message
                workflow.setIdleMessage("音频校验失败: \(message)")
                return
            }
        }

        let request = ExportRequest(
            imageURLs: imageURLs,
            outputURL: outputURL,
            settings: config.renderSettings
        )
        let report = ExportPreflightScanner.scan(imageURLs: request.imageURLs)
        preflightReport = report
        ignoredPreflightIssueKeys = []
        skippedAssetNamesFromPreflight = []
        preflightIssueFilter = report.hasBlockingIssues ? .mustFix : .all
        pendingRequestFromPreflight = request

        if report.hasBlockingIssues {
            fileListFilter = .problematic
            workflow.setIdleMessage("导出前检查发现 \(report.blockingIssues.count) 个必须修复问题，请先处理或跳过问题素材。")
            return
        }

        if !report.reviewIssues.isEmpty {
            workflow.setIdleMessage("导出前检查完成：\(report.reviewIssues.count) 个建议关注问题，将继续导出。")
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
        fileListFilter = .all
        preflightIssueFilter = .all
        let filteredRequest = ExportRequest(
            imageURLs: filtered,
            outputURL: request.outputURL,
            settings: request.settings
        )
        workflow.setIdleMessage("已跳过 \(skippedAssetNamesFromPreflight.count) 张问题素材，开始导出。")
        startExport(request: filteredRequest, fromRetry: false)
    }

    func rerunPreflight() {
        guard !isBusy else { return }
        guard !imageURLs.isEmpty else {
            workflow.setIdleMessage("请先选择图片")
            return
        }

        let sourceURLs = pendingRequestFromPreflight?.imageURLs ?? imageURLs
        let report = ExportPreflightScanner.scan(imageURLs: sourceURLs)
        preflightReport = report
        ignoredPreflightIssueKeys = []
        skippedAssetNamesFromPreflight = []
        preflightIssueFilter = report.hasBlockingIssues ? .mustFix : .all

        if report.issues.isEmpty {
            fileListFilter = .all
            workflow.setIdleMessage("复检通过：当前未发现导出风险。")
            return
        }

        if report.hasBlockingIssues {
            fileListFilter = .problematic
            workflow.setIdleMessage("复检结果：仍有 \(report.blockingIssues.count) 个必须修复问题。")
        } else {
            workflow.setIdleMessage("复检完成：存在 \(report.reviewIssues.count) 个建议关注问题。")
        }
    }

    func focusOnProblematicAssets() -> URL? {
        let issues = filteredPreflightIssues
        guard !issues.isEmpty else {
            workflow.setIdleMessage("当前没有问题素材。")
            return nil
        }
        fileListFilter = .problematic
        guard let url = defaultProblematicAssetURL(from: issues) else {
            workflow.setIdleMessage("已切到“仅问题”，请先处理必须修复项。")
            return nil
        }
        workflow.setIdleMessage("已切到“仅问题”，优先处理：\(url.lastPathComponent)")
        return url
    }

    func focusAssetForIssue(_ issue: PreflightIssue) -> URL? {
        fileListFilter = .problematic
        guard imageURLs.indices.contains(issue.index) else {
            workflow.setIdleMessage("无法定位问题素材：索引越界。")
            return nil
        }
        let url = imageURLs[issue.index]
        workflow.setIdleMessage("已定位问题素材：\(url.lastPathComponent)")
        return url
    }

    func defaultProblematicAssetURL(from issues: [PreflightIssue]) -> URL? {
        let preferredIssue = issues.first(where: { $0.severity == .mustFix }) ?? issues.first
        guard let issue = preferredIssue, imageURLs.indices.contains(issue.index) else {
            return nil
        }
        return imageURLs[issue.index]
    }

    func isIssueIgnored(_ issue: PreflightIssue) -> Bool {
        ignoredPreflightIssueKeys.contains(issue.ignoreKey)
    }

    func toggleIgnoreIssue(_ issue: PreflightIssue) {
        let key = issue.ignoreKey
        if ignoredPreflightIssueKeys.contains(key) {
            ignoredPreflightIssueKeys.remove(key)
            workflow.setIdleMessage("已恢复问题项：\(issue.fileName)")
        } else {
            ignoredPreflightIssueKeys.insert(key)
            workflow.setIdleMessage("已忽略本次：\(issue.fileName)")
        }
    }

    func restoreAllIgnoredIssues() {
        guard !ignoredPreflightIssueKeys.isEmpty else { return }
        let count = ignoredPreflightIssueKeys.count
        ignoredPreflightIssueKeys.removeAll()
        workflow.setIdleMessage("已恢复 \(count) 项忽略问题。")
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
        guard timelinePreviewEnabled else { return }
        generatePreview(for: imageURLs, at: previewSecond, useProxySettings: true)
    }

    func generatePreviewForSelectedAsset(_ url: URL) {
        generatePreview(for: [url], at: 0, useProxySettings: false)
    }

    func generatePreview(for urls: [URL], at second: Double, useProxySettings: Bool) {
        guard !urls.isEmpty else { return }
        if previewTask != nil {
            pendingPreviewRequest = (urls: urls, second: second, useProxySettings: useProxySettings)
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

        pendingPreviewRequest = nil
        let baseSettings = config.renderSettings
        let settings = useProxySettings
            ? interactivePreviewSettings(from: baseSettings)
            : baseSettings

        previewTask = Task { [weak self] in
            guard let self else { return }
            defer {
                previewTask = nil
                if let next = pendingPreviewRequest {
                    pendingPreviewRequest = nil
                    generatePreview(
                        for: next.urls,
                        at: next.second,
                        useProxySettings: next.useProxySettings
                    )
                }
            }

            do {
                let engine = makeEngine(settings)
                let cgImage = try await engine.previewFrame(imageURLs: urls, at: second)
                previewImage = NSImage(cgImage: cgImage, size: settings.outputSize)
                previewStatusMessage = "预览已更新 (\(String(format: "%.2f", second))s)"
                previewErrorMessage = nil
                workflow.finishPreviewSuccess()
            } catch {
                let logURL = outputURL.map { RenderLogger.resolvedLogURL(for: $0) }
                let previewFailedAssetNames = Self.failedAssetNames(from: error, urls: urls)
                let failureContext = ExportFailureContext.from(
                    error: error,
                    failedAssetNames: previewFailedAssetNames,
                    logURL: logURL,
                    stage: .preview
                )
                let advice = ExportRecoveryAdvisor.advice(for: failureContext)
                previewStatusMessage = "预览生成失败"
                previewErrorMessage = failureContext.displayHead
                if !previewFailedAssetNames.isEmpty {
                    failedAssetNames = Array(Set(failedAssetNames + previewFailedAssetNames)).sorted()
                    fileListFilter = .problematic
                }
                failureCardCopy = nil
                workflow.finishPreviewFailure(
                    message: makeErrorStatus(
                        context: failureContext,
                        advice: advice
                    )
                )
                await ExportFailureTelemetry.shared.record(failureContext)
            }
        }
    }

    func schedulePreviewRegeneration() {
        guard timelinePreviewEnabled else { return }
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
        previewAudioPlayer?.volume = Float(config.audioVolume)
        previewAudioPlayer?.numberOfLoops = config.audioLoopEnabled ? -1 : 0
        if !config.audioEnabled {
            audioStatusMessage = nil
            stopAudioPreview()
        }

        refreshSelectedAudioDuration()

        guard autoPreviewRefreshEnabled else { return }
        previewStatusMessage = "参数已变更，预览将自动刷新"
        schedulePreviewRegeneration()
    }

    func setAutoPreviewRefreshEnabled(_ enabled: Bool) {
        autoPreviewRefreshEnabled = enabled
    }

    func setTimelinePreviewEnabled(_ enabled: Bool) {
        timelinePreviewEnabled = enabled
        if !enabled {
            stopAudioPreview()
        }
    }

    func interactivePreviewSettings(from settings: RenderSettings) -> RenderSettings {
        let maxDimension: CGFloat = 1280
        let width = settings.outputSize.width
        let height = settings.outputSize.height
        let currentMax = max(width, height)
        guard currentMax > maxDimension else { return settings }

        let scale = maxDimension / currentMax
        let proxyWidth = max(2, Int((width * scale).rounded()) / 2 * 2)
        let proxyHeight = max(2, Int((height * scale).rounded()) / 2 * 2)
        let scaleFactor = Double(scale)
        let scaledLayout = LayoutSettings(
            horizontalMargin: max(1, settings.layout.horizontalMargin * scaleFactor),
            topMargin: max(1, settings.layout.topMargin * scaleFactor),
            bottomMargin: max(1, settings.layout.bottomMargin * scaleFactor),
            innerPadding: max(1, settings.layout.innerPadding * scaleFactor)
        )
        let scaledPlate = PlateSettings(
            enabled: settings.plate.enabled,
            height: max(1, settings.plate.height * scaleFactor),
            baselineOffset: max(1, settings.plate.baselineOffset * scaleFactor),
            fontSize: max(8, settings.plate.fontSize * scaleFactor),
            placement: settings.plate.placement
        )

        return RenderSettings(
            outputSize: CGSize(width: proxyWidth, height: proxyHeight),
            fps: settings.fps,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.transitionDuration,
            transitionEnabled: settings.transitionEnabled,
            transitionStyle: settings.transitionStyle,
            orientationStrategy: settings.orientationStrategy,
            enableKenBurns: settings.enableKenBurns,
            prefetchRadius: settings.prefetchRadius,
            prefetchMaxConcurrent: settings.prefetchMaxConcurrent,
            layout: scaledLayout,
            plate: scaledPlate,
            canvas: settings.canvas
        )
    }

    func startExport(request: ExportRequest, fromRetry: Bool) {
        guard workflow.beginExport(isRetry: fromRetry) else { return }

        failedAssetNames = []
        recoveryAdvice = nil
        failureCardCopy = nil

        let urls = request.imageURLs
        let destination = request.outputURL
        let settings = request.settings
        let logURL = RenderLogger.resolvedLogURL(for: destination)
        lastLogURL = logURL

        exportTask = Task { [weak self] in
            guard let self else { return }
            let scopedAccessEnabled = destination.startAccessingSecurityScopedResource()
            defer {
                if scopedAccessEnabled {
                    destination.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let engine = makeEngine(settings)
                try await engine.export(imageURLs: urls, outputURL: destination) { value in
                    Task { @MainActor in
                        self.workflow.updateExportProgress(value)
                    }
                }

                workflow.finishExportSuccess(
                    message: ExportStatusMessageBuilder.success(
                        outputFilename: destination.lastPathComponent,
                        logPath: logURL.path,
                        audioAttached: settings.audioTrack != nil
                    )
                )
                lastSuccessfulOutputURL = destination
                failedAssetNames = []
                recoveryAdvice = nil
                failureCardCopy = nil
                lastFailedRequest = nil
            } catch {
                lastFailedRequest = request
                let failedNames = Self.failedAssetNames(from: error, urls: urls)
                failedAssetNames = failedNames
                let failureContext = ExportFailureContext.from(
                    error: error,
                    failedAssetNames: failedNames,
                    logURL: logURL,
                    stage: .export
                )
                let advice = ExportRecoveryAdvisor.advice(for: failureContext)
                recoveryAdvice = advice
                failureCardCopy = makeFailureCardCopy(
                    context: failureContext,
                    advice: advice
                )
                await ExportFailureTelemetry.shared.record(failureContext)
                workflow.finishExportFailure(
                    message: makeErrorStatus(
                        context: failureContext,
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
        if !FileManager.default.fileExists(atPath: url.path) {
            workflow.setIdleMessage("日志文件不存在: \(url.path)")
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

    var isSettingsValid: Bool {
        invalidSettingsMessage == nil
    }

    var invalidSettingsMessage: String? {
        config.invalidMessage
    }

    func apply(template: RenderTemplate) {
        config = RenderEditorConfig(template: template)
        previewSecond = min(previewSecond, previewMaxSecond)

        if !imageURLs.isEmpty, isSettingsValid {
            generatePreview()
        }
    }

    static func failedAssetNames(from error: Error, urls: [URL]) -> [String] {
        guard let renderError = error as? RenderEngineError else { return [] }
        switch renderError {
        case let .assetLoadFailed(index, _):
            guard urls.indices.contains(index) else { return ["index=\(index)"] }
            return [urls[index].lastPathComponent]
        case let .imageLoadFailed(message):
            return urls
                .map(\.lastPathComponent)
                .filter { message.localizedCaseInsensitiveContains($0) }
        default:
            return []
        }
    }

    func makeErrorStatus(
        context: ExportFailureContext,
        advice: RecoveryAdvice
    ) -> String {
        return ExportStatusMessageBuilder.failure(
            head: context.displayHead,
            stage: context.stage,
            logPath: context.logPath,
            adviceActionTitle: advice.action.title,
            adviceMessage: advice.message,
            failedAssetNames: context.failedAssetNames
        )
    }

    func makeFailureCardCopy(
        context: ExportFailureContext,
        advice: RecoveryAdvice
    ) -> FailureCardCopy {
        ExportStatusMessageBuilder.failureCardCopy(
            stage: context.stage,
            adviceActionTitle: advice.action.title,
            adviceMessage: advice.message,
            failedAssetNames: context.failedAssetNames
        )
    }

    private func resolveOutputURLForExport(original: URL) -> URL? {
        if let outputValidationMessage = Self.validateOutputURL(original) {
            guard outputValidationMessage.contains("导出路径不可写"),
                  !hasUserSelectedOutputURL,
                  !Self.isRunningUnitTests() else {
                workflow.setIdleMessage(outputValidationMessage)
                return nil
            }

            workflow.setIdleMessage("默认导出路径当前不可写，请在弹窗中重新选择导出位置。")
            chooseOutput()
            guard let selectedOutputURL = outputURL else {
                workflow.setIdleMessage("已取消选择导出路径。")
                return nil
            }
            if let selectedValidationMessage = Self.validateOutputURL(selectedOutputURL) {
                workflow.setIdleMessage(selectedValidationMessage)
                return nil
            }
            return selectedOutputURL
        }
        return original
    }

    private static func validateOutputURL(_ url: URL) -> String? {
        let fm = FileManager.default
        let scopedAccessEnabled = url.startAccessingSecurityScopedResource()
        defer {
            if scopedAccessEnabled {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "导出路径不能是文件夹，请选择具体的 .mp4 文件。"
        }

        guard url.pathExtension.lowercased() == "mp4" else {
            return "导出文件需使用 .mp4 扩展名。"
        }

        let directoryURL = url.deletingLastPathComponent()

        var directoryIsDir: ObjCBool = false
        if fm.fileExists(atPath: directoryURL.path, isDirectory: &directoryIsDir) {
            if !directoryIsDir.boolValue {
                return "导出路径不可写，请重新选择可写目录。"
            }
        } else {
            do {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                return "导出路径不可写，请重新选择可写目录。"
            }
        }

        let outputExisted = fm.fileExists(atPath: url.path)
        if outputExisted {
            do {
                let handle = try FileHandle(forWritingTo: url)
                try handle.close()
            } catch {
                return "导出路径不可写，请重新选择可写目录。"
            }
            return nil
        }

        guard fm.createFile(atPath: url.path, contents: Data()) else {
            return "导出路径不可写，请重新选择可写目录。"
        }
        do {
            try fm.removeItem(at: url)
        } catch {
            return "导出路径不可写，请重新选择可写目录。"
        }
        return nil
    }

    private static func isRunningUnitTests() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

}
