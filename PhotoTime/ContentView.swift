import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

private extension PhotoOrientationStrategy {
    var displayName: String {
        switch self {
        case .followAsset:
            return "按素材方向"
        case .forceLandscape:
            return "强制横图"
        case .forcePortrait:
            return "强制竖图"
        }
    }
}

private extension PreflightIssue {
    var ignoreKey: String {
        "\(index)|\(severity.rawValue)|\(fileName)|\(message)"
    }
}

@MainActor
final class ExportViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum FileListFilter: String, CaseIterable, Identifiable {
        case all
        case problematic
        case mustFix
        case normal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部"
            case .problematic:
                return "仅问题"
            case .mustFix:
                return "仅必须修复"
            case .normal:
                return "仅正常"
            }
        }
    }

    enum PreflightIssueFilter: String, CaseIterable, Identifiable {
        case all
        case mustFix
        case review

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部问题"
            case .mustFix:
                return "仅必须修复"
            case .review:
                return "仅建议关注"
            }
        }
    }

    struct FlowStep: Identifiable {
        let id: String
        let title: String
        let done: Bool
    }

    @Published var imageURLs: [URL] = []
    @Published var outputURL: URL?
    @Published var previewImage: NSImage?
    @Published var previewSecond: Double = 0
    @Published var previewStatusMessage: String = "未生成预览"
    @Published var previewErrorMessage: String?
    @Published var failedAssetNames: [String] = []
    @Published var preflightReport: PreflightReport?
    @Published var ignoredPreflightIssueKeys: Set<String> = []
    @Published var skippedAssetNamesFromPreflight: [String] = []
    @Published var fileListFilter: FileListFilter = .all
    @Published var preflightIssueFilter: PreflightIssueFilter = .all
    @Published var config = RenderEditorConfig()
    @Published var audioStatusMessage: String?
    @Published var isAudioPreviewPlaying = false
    @Published var recoveryAdvice: RecoveryAdvice?
    @Published private var workflow = ExportWorkflowModel()

    private let makeEngine: (RenderSettings) -> any RenderingEngineClient
    private var exportTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var lastFailedRequest: ExportRequest?
    private var pendingRequestFromPreflight: ExportRequest?
    private var pendingPreviewRequest: (urls: [URL], second: Double, useProxySettings: Bool)?
    private var lastLogURL: URL?
    private var lastSuccessfulOutputURL: URL?
    private var autoPreviewRefreshEnabled = true
    private var timelinePreviewEnabled = true
    private var previewAudioPlayer: AVAudioPlayer?

    init(makeEngine: @escaping (RenderSettings) -> any RenderingEngineClient = { settings in
        RenderEngine(settings: settings)
    }) {
        self.makeEngine = makeEngine
        super.init()
        outputURL = Self.defaultOutputURL()
        if let outputURL {
            workflow.setIdleMessage("默认导出路径已设置：\(outputURL.lastPathComponent)（可修改）")
        }
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

    var latestOutputURL: URL? {
        lastSuccessfulOutputURL
    }

    var canRetryLastExport: Bool {
        !isBusy && lastFailedRequest != nil
    }

    var hasBlockingPreflightIssues: Bool {
        preflightReport?.hasBlockingIssues == true
    }

    var filteredPreflightIssues: [PreflightIssue] {
        guard let report = preflightReport else { return [] }
        let visibleIssues = report.issues.filter { !ignoredPreflightIssueKeys.contains($0.ignoreKey) }
        switch preflightIssueFilter {
        case .all:
            return visibleIssues
        case .mustFix:
            return visibleIssues.filter { $0.severity == .mustFix }
        case .review:
            return visibleIssues.filter { $0.severity == .shouldReview }
        }
    }

    var ignoredIssueCount: Int {
        ignoredPreflightIssueKeys.count
    }

    var ignoredPreflightIssues: [PreflightIssue] {
        guard let report = preflightReport else { return [] }
        return report.issues.filter { ignoredPreflightIssueKeys.contains($0.ignoreKey) }
    }

    var actionAvailability: ExportActionAvailability {
        ExportActionAvailability(
            workflowState: workflow.state,
            hasRetryTask: lastFailedRequest != nil
        )
    }

    var hasSelectedImages: Bool {
        !imageURLs.isEmpty
    }

    var hasOutputPath: Bool {
        outputURL != nil
    }

    var hasPreviewFrame: Bool {
        previewImage != nil
    }

    var canRunPreview: Bool {
        actionAvailability.canGeneratePreview && hasSelectedImages && validationMessage == nil
    }

    var canRunExport: Bool {
        actionAvailability.canStartExport && hasSelectedImages && hasOutputPath && validationMessage == nil
    }

    var flowSteps: [FlowStep] {
        [
            FlowStep(id: "select-images", title: "选择图片", done: hasSelectedImages),
            FlowStep(id: "preview", title: "（可选）生成预览", done: hasPreviewFrame || hasSelectedImages),
            FlowStep(id: "select-output", title: "确认导出路径（可修改）", done: hasOutputPath),
            FlowStep(id: "export", title: "导出 MP4", done: hasSuccessCard)
        ]
    }

    var selectedAudioFilename: String? {
        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var selectedAudioDuration: TimeInterval? {
        guard config.audioEnabled else { return nil }
        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let duration = AVURLAsset(url: url).duration.seconds
        guard duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    var canPreviewAudio: Bool {
        config.audioEnabled && selectedAudioFilename != nil && !isBusy
    }

    var nextActionHint: String {
        if !hasSelectedImages {
            return "下一步：点击顶部“选择图片”或直接拖入素材。"
        }
        if validationMessage != nil {
            return "下一步：先修正参数校验错误，再继续。"
        }
        if !hasPreviewFrame {
            return "可选：点击“生成预览”确认画面；也可直接导出 MP4。"
        }
        if !hasOutputPath {
            return "下一步：点击顶部“选择导出路径”设置输出文件。"
        }
        if isExporting {
            return "正在导出，请等待完成。"
        }
        return "已就绪：点击顶部“导出 MP4”即可完成首次导出。"
    }

    var orderedImageURLsForDisplay: [URL] {
        let problematic = problematicAssetNameSet
        return imageURLs.sorted { lhs, rhs in
            let lhsProblematic = problematic.contains(lhs.lastPathComponent)
            let rhsProblematic = problematic.contains(rhs.lastPathComponent)
            if lhsProblematic != rhsProblematic {
                return lhsProblematic && !rhsProblematic
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    var filteredImageURLsForDisplay: [URL] {
        let problematic = problematicAssetNameSet
        let mustFix = mustFixAssetNameSet
        switch fileListFilter {
        case .all:
            return orderedImageURLsForDisplay
        case .problematic:
            return orderedImageURLsForDisplay.filter { problematic.contains($0.lastPathComponent) }
        case .mustFix:
            return orderedImageURLsForDisplay.filter { mustFix.contains($0.lastPathComponent) }
        case .normal:
            return orderedImageURLsForDisplay.filter { !problematic.contains($0.lastPathComponent) }
        }
    }

    var problematicAssetNameSet: Set<String> {
        var names = Set(failedAssetNames)
        if let report = preflightReport {
            for issue in report.issues where !ignoredPreflightIssueKeys.contains(issue.ignoreKey) {
                names.insert(issue.fileName)
            }
        }
        for skipped in skippedAssetNamesFromPreflight {
            names.insert(skipped)
        }
        return names
    }

    var mustFixAssetNameSet: Set<String> {
        guard let report = preflightReport else { return [] }
        return Set(
            report.issues
                .filter { $0.severity == .mustFix && !ignoredPreflightIssueKeys.contains($0.ignoreKey) }
                .map(\.fileName)
        )
    }

    func preflightIssueTags(for fileName: String) -> [String] {
        guard let report = preflightReport else { return [] }
        let issues = report.issues.filter {
            $0.fileName == fileName && !ignoredPreflightIssueKeys.contains($0.ignoreKey)
        }
        guard !issues.isEmpty else { return [] }

        var tags: [String] = []
        if issues.contains(where: { $0.severity == .mustFix }) {
            tags.append("必须修复")
        }
        if issues.contains(where: { $0.severity == .shouldReview }) {
            tags.append("建议关注")
        }
        return tags
    }

    var configSignature: String {
        [
            "\(config.outputWidth)",
            "\(config.outputHeight)",
            "\(config.fps)",
            String(format: "%.3f", config.imageDuration),
            String(format: "%.3f", config.transitionDuration),
            config.orientationStrategy.rawValue,
            config.frameStylePreset.rawValue,
            String(format: "%.3f", config.canvasBackgroundGray),
            String(format: "%.3f", config.canvasPaperWhite),
            String(format: "%.3f", config.canvasStrokeGray),
            String(format: "%.3f", config.canvasTextGray),
            String(format: "%.2f", config.horizontalMargin),
            String(format: "%.2f", config.topMargin),
            String(format: "%.2f", config.bottomMargin),
            String(format: "%.2f", config.innerPadding),
            config.plateEnabled ? "1" : "0",
            config.platePlacement.rawValue,
            config.enableCrossfade ? "1" : "0",
            config.enableKenBurns ? "1" : "0",
            "\(config.prefetchRadius)",
            "\(config.prefetchMaxConcurrent)",
            config.audioEnabled ? "1" : "0",
            config.audioFilePath,
            String(format: "%.3f", config.audioVolume),
            config.audioLoopEnabled ? "1" : "0"
        ].joined(separator: "|")
    }

    func chooseAudioTrack() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyAudioTrack(url: url, sourceDescription: "已选择音频")
    }

    @discardableResult
    func importDroppedAudioTrack(_ urls: [URL]) -> Bool {
        guard !isBusy else { return false }

        for url in urls {
            if AudioTrackValidation.validate(url: url) == nil {
                applyAudioTrack(url: url, sourceDescription: "已拖入音频")
                return true
            }
        }

        let message = urls.first.flatMap { AudioTrackValidation.validate(url: $0) } ?? "未检测到可用音频文件"
        audioStatusMessage = message
        config.audioEnabled = false
        config.audioFilePath = ""
        workflow.setIdleMessage("音频导入失败: \(message)")
        return false
    }

    func clearAudioTrack() {
        guard !isBusy else { return }
        stopAudioPreview()
        let previous = selectedAudioFilename
        config.audioEnabled = false
        config.audioFilePath = ""
        config.audioVolume = 1
        audioStatusMessage = nil
        if let previous {
            workflow.setIdleMessage("已清除音频: \(previous)")
        } else {
            workflow.setIdleMessage("已清除音频")
        }
    }

    private func applyAudioTrack(url: URL, sourceDescription: String) {
        stopAudioPreview()
        if let message = AudioTrackValidation.validate(url: url) {
            audioStatusMessage = message
            config.audioEnabled = false
            config.audioFilePath = ""
            workflow.setIdleMessage("音频导入失败: \(message)")
            return
        }

        config.audioEnabled = true
        config.audioFilePath = url.path
        if config.audioVolume <= 0 {
            config.audioVolume = 1
        }
        audioStatusMessage = "音频已就绪：\(url.lastPathComponent)。导出时将附加单轨背景音频。"
        workflow.setIdleMessage("\(sourceDescription): \(url.lastPathComponent)")
    }

    @discardableResult
    func startAudioPreview() -> Bool {
        guard config.audioEnabled else {
            audioStatusMessage = "请先启用背景音频。"
            return false
        }

        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            audioStatusMessage = "请先选择音频文件。"
            return false
        }

        let url = URL(fileURLWithPath: path)
        if let message = AudioTrackValidation.validate(url: url) {
            audioStatusMessage = message
            return false
        }

        do {
            stopAudioPreview()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(config.audioVolume)
            player.numberOfLoops = config.audioLoopEnabled ? -1 : 0
            player.prepareToPlay()
            let maxStart = max(0, player.duration - 0.01)
            player.currentTime = min(max(0, previewSecond), maxStart)
            guard player.play() else {
                audioStatusMessage = "音频预览播放失败。"
                return false
            }
            previewAudioPlayer = player
            isAudioPreviewPlaying = true
            workflow.setIdleMessage("音频预览播放中")
            return true
        } catch {
            audioStatusMessage = "音频预览失败：\(error.localizedDescription)"
            return false
        }
    }

    func toggleAudioPreview() {
        if isAudioPreviewPlaying {
            pauseAudioPreview()
        } else {
            _ = startAudioPreview()
        }
    }

    func pauseAudioPreview() {
        guard let player = previewAudioPlayer else { return }
        player.pause()
        previewSecond = player.currentTime
        isAudioPreviewPlaying = false
        workflow.setIdleMessage("音频预览已暂停")
    }

    func stopAudioPreview() {
        guard let player = previewAudioPlayer else {
            isAudioPreviewPlaying = false
            return
        }
        player.stop()
        previewAudioPlayer = nil
        isAudioPreviewPlaying = false
    }

    func syncAudioPreviewPosition() {
        guard let player = previewAudioPlayer, isAudioPreviewPlaying else { return }
        let maxStart = max(0, player.duration - 0.01)
        player.currentTime = min(max(0, previewSecond), maxStart)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === previewAudioPlayer else { return }
        previewAudioPlayer = nil
        isAudioPreviewPlaying = false
    }

    func chooseImages() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageURLs = normalizedImageURLs(from: panel.urls)
        previewImage = nil
        previewSecond = 0
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        workflow.setIdleMessage("已选择 \(imageURLs.count) 张图片")

        // Generate first preview frame automatically to avoid blank preview area after import.
        if !imageURLs.isEmpty, isSettingsValid {
            generatePreview()
        }
    }

    func addImages() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK else { return }
        appendImages(panel.urls, source: "已新增")
    }

    func importDroppedItems(_ urls: [URL]) {
        guard !isBusy else { return }
        appendImages(urls, source: "已拖入")
    }

    func removeImage(_ url: URL) {
        guard !isBusy else { return }
        guard let index = imageURLs.firstIndex(of: url) else { return }

        imageURLs.remove(at: index)
        failedAssetNames.removeAll(where: { $0 == url.lastPathComponent })
        skippedAssetNamesFromPreflight.removeAll(where: { $0 == url.lastPathComponent })
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        pendingRequestFromPreflight = nil

        if imageURLs.isEmpty {
            previewImage = nil
            previewSecond = 0
            previewStatusMessage = "未生成预览"
            previewErrorMessage = nil
            workflow.setIdleMessage("素材已清空")
            return
        }

        previewImage = nil
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("已删除: \(url.lastPathComponent)")

        if isSettingsValid {
            generatePreview()
        }
    }

    func reorderImage(from source: URL, to target: URL) {
        guard !isBusy else { return }
        guard source != target else { return }
        guard let sourceIndex = imageURLs.firstIndex(of: source),
              let targetIndex = imageURLs.firstIndex(of: target) else { return }

        var reordered = imageURLs
        let moving = reordered.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        reordered.insert(moving, at: insertIndex)
        imageURLs = reordered

        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        previewImage = nil
        previewStatusMessage = "素材顺序已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("已调整素材顺序")
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

    private static func defaultOutputURL() -> URL? {
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

    private func defaultProblematicAssetURL(from issues: [PreflightIssue]) -> URL? {
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

    private func generatePreview(for urls: [URL], at second: Double, useProxySettings: Bool) {
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

    private func interactivePreviewSettings(from settings: RenderSettings) -> RenderSettings {
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

    private func startExport(request: ExportRequest, fromRetry: Bool) {
        guard workflow.beginExport(isRetry: fromRetry) else { return }

        failedAssetNames = []
        recoveryAdvice = nil

        let urls = request.imageURLs
        let destination = request.outputURL
        let settings = request.settings
        let logURL = RenderLogger.resolvedLogURL(for: destination)
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
                    message: ExportStatusMessageBuilder.success(
                        outputFilename: destination.lastPathComponent,
                        logPath: logURL.path,
                        audioAttached: settings.audioTrack != nil
                    )
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
        case "first_run_ready":
            imageURLs = [
                URL(fileURLWithPath: "/tmp/first-run-a.jpg"),
                URL(fileURLWithPath: "/tmp/first-run-b.jpg")
            ]
            outputURL = URL(fileURLWithPath: "/tmp/PhotoTime-FirstRun.mp4")
            previewImage = NSImage(size: CGSize(width: 320, height: 180))
            previewStatusMessage = "测试场景：预览已就绪"
            workflow.setIdleMessage("测试场景：可直接导出")
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

    private func appendImages(_ urls: [URL], source: String) {
        let incoming = normalizedImageURLs(from: urls)
        guard !incoming.isEmpty else {
            workflow.setIdleMessage("未检测到可用图片")
            return
        }

        var existing = Set(imageURLs.map(\.standardizedFileURL))
        var appended: [URL] = []

        for url in incoming {
            let normalized = url.standardizedFileURL
            if existing.insert(normalized).inserted {
                appended.append(normalized)
            }
        }

        guard !appended.isEmpty else {
            workflow.setIdleMessage("未新增素材（已存在）")
            return
        }

        imageURLs.append(contentsOf: appended)
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        previewImage = nil
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("\(source) \(appended.count) 张，共 \(imageURLs.count) 张")

        if isSettingsValid {
            generatePreview()
        }
    }

    private func normalizedImageURLs(from urls: [URL]) -> [URL] {
        var collected: [URL] = []
        var seen = Set<URL>()

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            collectImageURLs(from: url, into: &collected, seen: &seen)
        }

        return collected
    }

    private func collectImageURLs(from url: URL, into result: inout [URL], seen: inout Set<URL>) {
        guard seen.insert(url).inserted else { return }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey])
        if values?.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for case let fileURL as URL in enumerator {
                let standardized = fileURL.standardizedFileURL
                let fileValues = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey])
                guard fileValues?.isRegularFile == true else { continue }
                guard isSupportedImageURL(standardized, contentType: fileValues?.contentType) else { continue }
                result.append(standardized)
            }
            return
        }

        guard values?.isRegularFile == true else { return }
        guard isSupportedImageURL(url, contentType: values?.contentType) else { return }
        result.append(url)
    }

    private func isSupportedImageURL(_ url: URL, contentType: UTType?) -> Bool {
        if let contentType, contentType.conforms(to: .image) {
            return true
        }
        if let inferred = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return inferred.conforms(to: .image)
        }
        return false
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

        return ExportStatusMessageBuilder.failure(
            head: head,
            logPath: logURL.path,
            adviceActionTitle: advice.action.title,
            adviceMessage: advice.message,
            failedAssetNames: failedAssetNames
        )
    }
}

private struct ExportRequest {
    let imageURLs: [URL]
    let outputURL: URL
    let settings: RenderSettings
}

private enum AssetThumbnailPipeline {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    static func loadThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct AssetThumbnailView: View {
    let url: URL
    let height: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            if let cached = AssetThumbnailPipeline.cachedImage(for: url) {
                image = cached
                return
            }
            let target = Int(height * 2.5)
            let loaded = await Task.detached(priority: .utility) {
                AssetThumbnailPipeline.loadThumbnail(for: url, maxPixelSize: target)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct ContentView: View {
    private enum CenterPreviewTab: String, CaseIterable, Identifiable {
        case singleFrame
        case videoTimeline

        var id: String { rawValue }

        var title: String {
            switch self {
            case .singleFrame: return "单帧预览"
            case .videoTimeline: return "视频预览"
            }
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case simple
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .simple: return "简单"
            case .advanced: return "高级"
            }
        }
    }

    private enum ResolutionPreset: String, CaseIterable, Identifiable {
        case hd720
        case fullHD1080
        case qhd1440
        case uhd4K
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hd720: return "720p"
            case .fullHD1080: return "1080p"
            case .qhd1440: return "1440p"
            case .uhd4K: return "4K"
            case .custom: return "自定义"
            }
        }

        var size: (width: Int, height: Int)? {
            switch self {
            case .hd720: return (1280, 720)
            case .fullHD1080: return (1920, 1080)
            case .qhd1440: return (2560, 1440)
            case .uhd4K: return (3840, 2160)
            case .custom: return nil
            }
        }

        static let simplePresets: [ResolutionPreset] = [.hd720, .fullHD1080, .qhd1440, .uhd4K]
    }

    private enum ImageDurationPreset: String, CaseIterable, Identifiable {
        case quick
        case standard
        case relaxed
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quick: return "快节奏"
            case .standard: return "标准"
            case .relaxed: return "舒缓"
            case .custom: return "自定义"
            }
        }

        var seconds: Double? {
            switch self {
            case .quick: return 1.5
            case .standard: return 2.5
            case .relaxed: return 4.0
            case .custom: return nil
            }
        }

        static let simplePresets: [ImageDurationPreset] = [.quick, .standard, .relaxed]
    }

    private enum TransitionPreset: String, CaseIterable, Identifiable {
        case off
        case soft
        case standard
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "关闭"
            case .soft: return "柔和"
            case .standard: return "标准"
            case .custom: return "自定义"
            }
        }

        var transitionDuration: Double? {
            switch self {
            case .off: return 0
            case .soft: return 0.4
            case .standard: return 0.8
            case .custom: return nil
            }
        }

        static let simplePresets: [TransitionPreset] = [.off, .soft, .standard]
    }

    @StateObject private var viewModel = ExportViewModel()
    @State private var centerPreviewTab: CenterPreviewTab = .singleFrame
    @State private var settingsTab: SettingsTab = .simple
    @State private var selectedAssetURL: URL?
    @State private var singlePreviewDebounceTask: Task<Void, Never>?
    @State private var assetSearchText = ""
    @State private var isAssetDropTarget = false
    @State private var isAudioDropTarget = false
    @State private var draggingAssetURL: URL?
    @State private var expandedPreflightIssueKeys: Set<String> = []
    @State private var ignoredIssuesExpanded = false
    @State private var ignoredIssueSearchText = ""
    @State private var preflightOnlyPending = true
    @State private var preflightPrioritizeMustFix = true
    @State private var preflightSecondaryActionsExpanded = false
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all
    private let commonFPSOptions = [24, 30, 60]

    var body: some View {
        NavigationSplitView(columnVisibility: $splitColumnVisibility) {
            sidebarAssetColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } content: {
            centerPreviewColumn
                .navigationSplitViewColumnWidth(min: 520, ideal: 680, max: 900)
        } detail: {
            rightSettingsColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("PhotoTime")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("选择图片") { viewModel.chooseImages() }
                    .accessibilityIdentifier("primary_select_images")
                    .disabled(!viewModel.actionAvailability.canSelectImages)
                Button("选择导出路径") { viewModel.chooseOutput() }
                    .accessibilityIdentifier("primary_select_output")
                    .disabled(!viewModel.actionAvailability.canSelectOutput)
                Button("导出 MP4") { viewModel.export() }
                    .accessibilityIdentifier("primary_export")
                    .disabled(!viewModel.canRunExport)
                Button("取消导出") { viewModel.cancelExport() }
                    .accessibilityIdentifier("primary_cancel")
                    .disabled(!viewModel.actionAvailability.canCancelExport)
            }

            ToolbarItem(placement: .automatic) {
                Menu("更多") {
                    Button("生成预览") {
                        if centerPreviewTab == .singleFrame, let selected = selectedAssetForPreview {
                            viewModel.generatePreviewForSelectedAsset(selected)
                        } else {
                            viewModel.generatePreview()
                        }
                    }
                        .accessibilityIdentifier("secondary_preview")
                        .disabled(!viewModel.canRunPreview)
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
            }
        }
        .frame(minWidth: 1200, idealWidth: 1360, minHeight: 720, idealHeight: 860)
        .onAppear {
            applyPreviewModePolicy(for: centerPreviewTab)
            if centerPreviewTab == .singleFrame {
                scheduleSingleFramePreview()
            }
        }
        .onChange(of: viewModel.configSignature) { _, _ in
            viewModel.handleConfigChanged()
            if centerPreviewTab == .singleFrame {
                scheduleSingleFramePreview()
            }
        }
        .onChange(of: viewModel.imageURLs) { _, urls in
            guard !urls.isEmpty else {
                selectedAssetURL = nil
                if centerPreviewTab == .singleFrame {
                    scheduleSingleFramePreview()
                }
                return
            }
            if let selectedAssetURL, urls.contains(selectedAssetURL) {
                if centerPreviewTab == .singleFrame {
                    scheduleSingleFramePreview()
                }
                return
            }
            selectedAssetURL = urls.first
        }
        .onChange(of: selectedAssetURL) { _, _ in
            if centerPreviewTab == .singleFrame {
                scheduleSingleFramePreview()
            }
        }
        .onChange(of: centerPreviewTab) { _, tab in
            applyPreviewModePolicy(for: tab)
            if tab == .singleFrame {
                scheduleSingleFramePreview()
            } else {
                viewModel.generatePreview()
            }
        }
        .onDisappear {
            viewModel.stopAudioPreview()
        }
    }

    private var sidebarAssetColumn: some View {
        ZStack {
            if viewModel.imageURLs.isEmpty {
                emptyAssetDropView
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88, maximum: 128), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(sidebarFilteredAssets, id: \.self) { url in
                            assetThumbnailItem(url: url)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(isAssetDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
        .animation(.easeInOut(duration: 0.12), value: isAssetDropTarget)
        .onDrop(of: [UTType.fileURL], isTargeted: $isAssetDropTarget, perform: handleAssetDrop(providers:))
        .onDeleteCommand(perform: deleteSelectedAsset)
        .safeAreaInset(edge: .bottom) {
            assetBottomBar
        }
    }

    private var centerPreviewColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let validationMessage = viewModel.validationMessage {
                    Text("参数校验: \(validationMessage)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings_validation_message")
                }
                Picker("预览模式", selection: $centerPreviewTab) {
                    ForEach(CenterPreviewTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.imageURLs.isEmpty)

                if centerPreviewTab == .singleFrame {
                    previewPanel
                } else {
                    videoPreviewPanel
                }
                workflowPanel
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rightSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("参数设置", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text("调整画布、时长、转场和性能参数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let outputURL = viewModel.outputURL {
                    Text("输出: \(outputURL.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Picker("模式", selection: $settingsTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            settingsPanel
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyAssetDropView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Button("导入图片") {
                viewModel.addImages()
            }
            .buttonStyle(.borderedProminent)
            Text("支持拖入图片或文件夹；导出路径默认在“影片”目录，可按需修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var assetBottomBar: some View {
        HStack(spacing: 8) {
            if !viewModel.imageURLs.isEmpty {
                TextField("搜索图片", text: $assetSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)

                Picker("筛选", selection: $viewModel.fileListFilter) {
                    ForEach(ExportViewModel.FileListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            Text("\(viewModel.problematicAssetNameSet.count) 个问题")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !viewModel.imageURLs.isEmpty {
                Button {
                    viewModel.addImages()
                } label: {
                    Label("添加图片", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("添加图片")
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func assetThumbnailItem(url: URL) -> some View {
        let fileName = url.lastPathComponent
        let tags = viewModel.preflightIssueTags(for: fileName)
        let isSelected = selectedAssetURL == url

        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AssetThumbnailView(url: url, height: 72)

                if !tags.isEmpty || viewModel.failedAssetNames.contains(fileName) {
                    Circle()
                        .fill(tags.contains("必须修复") || viewModel.failedAssetNames.contains(fileName) ? .red : .orange)
                        .frame(width: 8, height: 8)
                        .padding(6)
                }
            }

            Text(fileName)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectedAssetURL = url
        }
        .contextMenu {
            Button("删除") {
                viewModel.removeImage(url)
                if selectedAssetURL == url {
                    selectedAssetURL = sidebarFilteredAssets.first
                }
            }
        }
        .onDrag {
            draggingAssetURL = url
            return NSItemProvider(object: NSString(string: url.absoluteString))
        }
        .onDrop(
            of: [.text],
            delegate: AssetReorderDropDelegate(
                destination: url,
                dragging: $draggingAssetURL,
                canReorder: canReorderAssets
            ) { source, target in
                viewModel.reorderImage(from: source, to: target)
                selectedAssetURL = source
            }
        )
        .help(assetTagLine(fileName: fileName, issueTags: tags))
    }

    private func deleteSelectedAsset() {
        guard let selectedAssetURL else { return }
        viewModel.removeImage(selectedAssetURL)
        self.selectedAssetURL = sidebarFilteredAssets.first
    }

    private func handleAssetDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let lock = NSLock()
        let group = DispatchGroup()
        var dropped: [URL] = []

        for provider in fileProviders {
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                defer { group.leave() }
                guard let item = item as? URL else { return }
                lock.lock()
                dropped.append(item)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            viewModel.importDroppedItems(dropped)
        }

        return true
    }

    private var sidebarFilteredAssets: [URL] {
        let baseAssets = sidebarBaseAssets
        guard !assetSearchText.isEmpty else {
            return baseAssets
        }
        return baseAssets.filter { url in
            url.lastPathComponent.localizedCaseInsensitiveContains(assetSearchText)
        }
    }

    private var sidebarBaseAssets: [URL] {
        if viewModel.fileListFilter == .all {
            return viewModel.imageURLs
        }
        return viewModel.filteredImageURLsForDisplay
    }

    private var canReorderAssets: Bool {
        viewModel.fileListFilter == .all && assetSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func assetTagLine(fileName: String, issueTags: [String]) -> String {
        var tags = issueTags
        if viewModel.failedAssetNames.contains(fileName) {
            tags.append("导出失败")
        }
        if viewModel.skippedAssetNamesFromPreflight.contains(fileName) {
            tags.append("已跳过")
        }
        return tags.joined(separator: " · ")
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            exportStatusPanel

            if let report = viewModel.preflightReport, !report.issues.isEmpty {
                GroupBox("导出前检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button("仅看问题素材") {
                                if let url = viewModel.focusOnProblematicAssets() {
                                    selectedAssetURL = url
                                }
                            }
                            .disabled(viewModel.isBusy)

                            Button("重新检查") {
                                viewModel.rerunPreflight()
                            }
                            .disabled(viewModel.isBusy)

                            if viewModel.hasBlockingPreflightIssues {
                                Button("跳过问题素材并导出") {
                                    viewModel.exportSkippingPreflightIssues()
                                }
                                .disabled(viewModel.isBusy)
                            }
                        }

                        DisclosureGroup("次级选项", isExpanded: $preflightSecondaryActionsExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("问题筛选", selection: $viewModel.preflightIssueFilter) {
                                    ForEach(ExportViewModel.PreflightIssueFilter.allCases) { filter in
                                        Text(filter.title).tag(filter)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 320)
                                .controlSize(.small)

                                HStack(spacing: 12) {
                                    Toggle("仅未处理", isOn: $preflightOnlyPending)
                                    Toggle("严重优先", isOn: $preflightPrioritizeMustFix)
                                }
                                .toggleStyle(.checkbox)
                                .font(.caption)
                                .controlSize(.small)

                                HStack(spacing: 10) {
                                    Button("展开全部") {
                                        expandedPreflightIssueKeys.formUnion(preflightDisplayIssues(report: report).map(\.ignoreKey))
                                    }
                                    .font(.caption)
                                    .disabled(preflightDisplayIssues(report: report).isEmpty)

                                    Button("收起全部") {
                                        expandedPreflightIssueKeys.subtract(preflightDisplayIssues(report: report).map(\.ignoreKey))
                                    }
                                    .font(.caption)
                                    .disabled(preflightDisplayIssues(report: report).isEmpty)
                                }
                                .controlSize(.small)

                                ForEach(preflightDisplayIssues(report: report), id: \.ignoreKey) { issue in
                                    DisclosureGroup(
                                        isExpanded: preflightIssueExpandedBinding(for: issue.ignoreKey)
                                    ) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(issue.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            HStack(spacing: 10) {
                                                Button(viewModel.isIssueIgnored(issue) ? "恢复" : "忽略本次") {
                                                    viewModel.toggleIgnoreIssue(issue)
                                                }
                                                .font(.caption)
                                                .disabled(viewModel.isBusy)
                                                Button("定位") {
                                                    if let url = viewModel.focusAssetForIssue(issue) {
                                                        selectedAssetURL = url
                                                    }
                                                }
                                                .font(.caption)
                                                .disabled(viewModel.isBusy)
                                            }
                                        }
                                        .padding(.top, 2)
                                    } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("[\(issue.severity == .mustFix ? "必须修复" : "建议关注")]")
                                                .font(.caption)
                                                .foregroundStyle(issue.severity == .mustFix ? .red : .orange)
                                            Text(issue.fileName)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Text(issue.message)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                if viewModel.ignoredIssueCount > 0 {
                                    DisclosureGroup(
                                        "已忽略 \(viewModel.ignoredIssueCount) 项（本次）",
                                        isExpanded: $ignoredIssuesExpanded
                                    ) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            TextField("搜索已忽略文件名", text: $ignoredIssueSearchText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.caption)
                                                .frame(maxWidth: 280)

                                            HStack(spacing: 10) {
                                                Button("恢复全部") {
                                                    viewModel.restoreAllIgnoredIssues()
                                                    ignoredIssueSearchText = ""
                                                }
                                                .font(.caption)
                                                .disabled(viewModel.isBusy)
                                                Text("显示 \(filteredIgnoredIssues.count) / \(viewModel.ignoredIssueCount)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            ForEach(filteredIgnoredIssues.prefix(5), id: \.ignoreKey) { issue in
                                                HStack(spacing: 8) {
                                                    Text(issue.fileName)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                    Button("恢复") {
                                                        viewModel.toggleIgnoreIssue(issue)
                                                    }
                                                    .font(.caption)
                                                    .disabled(viewModel.isBusy)
                                                }
                                            }

                                            if filteredIgnoredIssues.isEmpty {
                                                Text("没有匹配的已忽略项。")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }

                            }
                            .padding(.top, 4)
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
        }
        .textSelection(.enabled)
    }

    private var exportStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("流程状态") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.statusMessage)
                        .font(.callout)
                        .accessibilityIdentifier("workflow_status_message")
                    Text(viewModel.nextActionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("flow_next_hint")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("快速开始") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.flowSteps) { step in
                        HStack(spacing: 8) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.done ? .green : .secondary)
                            Text(step.title)
                                .font(.caption)
                                .foregroundStyle(step.done ? .secondary : .primary)
                        }
                    }

                    if let action = firstRunPrimaryAction {
                        Button(action.title) {
                            action.handler()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isBusy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.isExporting {
                ProgressView(value: viewModel.progress)
                    .frame(maxWidth: .infinity)
            }

            if viewModel.hasFailureCard, let advice = viewModel.recoveryAdvice {
                GroupBox("导出失败") {
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
                }
                .accessibilityIdentifier("failure_card")
            }

            if viewModel.hasSuccessCard {
                GroupBox("导出成功") {
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
                }
                .accessibilityIdentifier("success_card")
            }

            if !viewModel.failedAssetNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("失败素材")
                        .font(.subheadline.weight(.semibold))
                    ForEach(failedAssetNamesPreview, id: \.self) { name in
                        Text(name)
                            .font(.callout)
                    }
                    if failedAssetHiddenCount > 0 {
                        Text("另有 \(failedAssetHiddenCount) 项失败素材，可在“素材列表”查看全部。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var firstRunPrimaryAction: (title: String, handler: () -> Void)? {
        if !viewModel.hasSelectedImages {
            return ("现在选择图片", { viewModel.chooseImages() })
        }
        if viewModel.validationMessage != nil {
            return nil
        }
        if !viewModel.hasPreviewFrame {
            return ("现在生成预览", {
                if centerPreviewTab == .singleFrame, let selected = selectedAssetForPreview {
                    viewModel.generatePreviewForSelectedAsset(selected)
                } else {
                    viewModel.generatePreview()
                }
            })
        }
        if !viewModel.hasOutputPath {
            return ("现在选择导出路径", { viewModel.chooseOutput() })
        }
        if !viewModel.hasSuccessCard {
            return ("现在导出 MP4", { viewModel.export() })
        }
        return nil
    }

    private func preflightIssueExpandedBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedPreflightIssueKeys.contains(key) },
            set: { newValue in
                if newValue {
                    expandedPreflightIssueKeys.insert(key)
                } else {
                    expandedPreflightIssueKeys.remove(key)
                }
            }
        )
    }

    private var failedAssetNamesPreview: [String] {
        Array(viewModel.failedAssetNames.prefix(3))
    }

    private var failedAssetHiddenCount: Int {
        max(0, viewModel.failedAssetNames.count - failedAssetNamesPreview.count)
    }

    private func preflightIssuesForDisplay(report: PreflightReport) -> [PreflightIssue] {
        var issues = report.issues
        if preflightOnlyPending {
            issues = issues.filter { !viewModel.isIssueIgnored($0) }
        }
        if viewModel.preflightIssueFilter == .mustFix {
            issues = issues.filter { $0.severity == .mustFix }
        } else if viewModel.preflightIssueFilter == .review {
            issues = issues.filter { $0.severity == .shouldReview }
        }
        if preflightPrioritizeMustFix {
            issues.sort { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity == .mustFix
                }
                return lhs.index < rhs.index
            }
        }
        return issues
    }

    private func preflightDisplayIssues(report: PreflightReport) -> [PreflightIssue] {
        Array(preflightIssuesForDisplay(report: report).prefix(6))
    }

    private var filteredIgnoredIssues: [PreflightIssue] {
        viewModel.ignoredPreflightIssues.filter { issue in
            ignoredIssueSearchText.isEmpty || issue.fileName.localizedCaseInsensitiveContains(ignoredIssueSearchText)
        }
    }

    private var selectedAssetForPreview: URL? {
        if let selectedAssetURL, viewModel.imageURLs.contains(selectedAssetURL) {
            return selectedAssetURL
        }
        return viewModel.imageURLs.first
    }

    private func scheduleSingleFramePreview() {
        guard !viewModel.isBusy else { return }
        guard viewModel.validationMessage == nil else { return }
        guard let selected = selectedAssetForPreview else { return }

        singlePreviewDebounceTask?.cancel()
        singlePreviewDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.generatePreviewForSelectedAsset(selected)
            }
        }
    }

    private func applyPreviewModePolicy(for tab: CenterPreviewTab) {
        switch tab {
        case .singleFrame:
            viewModel.setTimelinePreviewEnabled(false)
            viewModel.setAutoPreviewRefreshEnabled(false)
        case .videoTimeline:
            viewModel.setTimelinePreviewEnabled(true)
            viewModel.setAutoPreviewRefreshEnabled(true)
        }
    }

    private var previewPanel: some View {
        GroupBox("单张预览") {
            VStack(alignment: .leading, spacing: 12) {
                if let preview = viewModel.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                        .padding(.vertical, 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                        .overlay(Image(systemName: "photo"))
                }

                if viewModel.isPreviewGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                if let previewError = viewModel.previewErrorMessage {
                    Text("预览错误: \(previewError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

            }
        }
    }

    private var videoPreviewPanel: some View {
        GroupBox("视频预览") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("时间: \(viewModel.previewSecond, specifier: "%.2f")s")
                    Slider(
                        value: $viewModel.previewSecond,
                        in: 0...max(viewModel.previewMaxSecond, 0.001)
                    )
                    .onChange(of: viewModel.previewSecond) { _, _ in
                        viewModel.schedulePreviewRegeneration()
                        viewModel.syncAudioPreviewPosition()
                    }
                    .disabled(viewModel.isBusy || viewModel.imageURLs.isEmpty)
                }

                if viewModel.config.audioEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        let videoDuration = max(viewModel.previewMaxSecond, 0)
                        let audioDuration = viewModel.selectedAudioDuration
                        let segments = audioTimelineSegments(
                            videoDuration: videoDuration,
                            audioDuration: audioDuration,
                            loopEnabled: viewModel.config.audioLoopEnabled
                        )
                        let audioName = viewModel.selectedAudioFilename ?? "未选择音频"

                        Text("音轨: \(audioName)")
                            .font(.caption)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.12))
                            GeometryReader { proxy in
                                let width = proxy.size.width
                                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                    let start = segment.start
                                    let end = segment.end
                                    let x = videoDuration > 0 ? CGFloat(start / videoDuration) * width : 0
                                    let segmentWidth = videoDuration > 0 ? max(2, CGFloat((end - start) / videoDuration) * width) : 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.75))
                                        .frame(width: segmentWidth, height: 10)
                                        .offset(x: x, y: 4)
                                }
                            }
                        }
                        .frame(height: 18)

                        if let audioDuration {
                            Text(
                                "视频 \(videoDuration, specifier: "%.2f")s · 音频 \(audioDuration, specifier: "%.2f")s · \(viewModel.config.audioLoopEnabled ? "自动循环开启" : "自动循环关闭")"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("未读取到音频时长，导出前会再次校验。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button(viewModel.isAudioPreviewPlaying ? "暂停试听" : "试听当前时间点") {
                                viewModel.toggleAudioPreview()
                            }
                            .disabled(!viewModel.canPreviewAudio)

                            Button("停止") {
                                viewModel.stopAudioPreview()
                            }
                            .disabled(!viewModel.isAudioPreviewPlaying)
                        }
                        .controlSize(.small)
                    }
                }

                if let preview = viewModel.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                        .padding(.vertical, 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                        .overlay(Image(systemName: "film"))
                }

                if viewModel.isPreviewGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                if let previewError = viewModel.previewErrorMessage {
                    Text("预览错误: \(previewError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var settingsPanel: some View {
        Group {
            if settingsTab == .simple {
                simpleSettingsPanel
            } else {
                advancedSettingsPanel
            }
        }
    }

    private var simpleSettingsPanel: some View {
        Form {
            Section("常用参数") {
                Picker("分辨率", selection: resolutionPresetBinding) {
                    ForEach(ResolutionPreset.simplePresets) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .disabled(viewModel.isBusy)

                fpsPicker

                Picker("展示节奏", selection: imageDurationPresetBinding) {
                    ForEach(ImageDurationPreset.simplePresets) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)

                Picker("转场", selection: transitionPresetBinding) {
                    ForEach(TransitionPreset.simplePresets) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)

                Toggle("启用 Ken Burns", isOn: $viewModel.config.enableKenBurns)
                    .disabled(viewModel.isBusy)

                Toggle("显示底部铭牌文字", isOn: $viewModel.config.plateEnabled)
                    .disabled(viewModel.isBusy)

                Picker("信息位置", selection: $viewModel.config.platePlacement) {
                    Text("相框").tag(PlatePlacement.frame)
                    Text("黑底下方").tag(PlatePlacement.canvasBottom)
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)
            }

            Section("风格") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("横竖图策略")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        orientationQuickChoiceButton(
                            title: PhotoOrientationStrategy.followAsset.displayName,
                            strategy: .followAsset
                        )
                        orientationQuickChoiceButton(
                            title: PhotoOrientationStrategy.forceLandscape.displayName,
                            strategy: .forceLandscape
                        )
                        orientationQuickChoiceButton(
                            title: PhotoOrientationStrategy.forcePortrait.displayName,
                            strategy: .forcePortrait
                        )
                    }
                }
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("相框风格")
                        .font(.subheadline.weight(.medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(FrameStylePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            frameStyleQuickChoiceButton(
                                title: preset.displayName,
                                preset: preset
                            )
                        }
                    }
                }
                .disabled(viewModel.isBusy)
            }

            audioSettingsSection
        }
        .formStyle(.grouped)
    }

    private var advancedSettingsPanel: some View {
        Form {
            Section("导出设置") {
                Stepper("宽: \(viewModel.config.outputWidth)", value: $viewModel.config.outputWidth, in: RenderEditorConfig.outputWidthRange, step: 2)
                    .disabled(viewModel.isBusy)
                Stepper("高: \(viewModel.config.outputHeight)", value: $viewModel.config.outputHeight, in: RenderEditorConfig.outputHeightRange, step: 2)
                    .disabled(viewModel.isBusy)
                fpsPicker
                VStack(alignment: .leading, spacing: 6) {
                    Text("单图时长: \(viewModel.config.imageDuration, specifier: "%.2f")s")
                    Slider(value: $viewModel.config.imageDuration, in: RenderEditorConfig.imageDurationRange, step: 0.1)
                        .disabled(viewModel.isBusy)
                }
                Picker("横竖图策略", selection: $viewModel.config.orientationStrategy) {
                    Text(PhotoOrientationStrategy.followAsset.displayName).tag(PhotoOrientationStrategy.followAsset)
                    Text(PhotoOrientationStrategy.forceLandscape.displayName).tag(PhotoOrientationStrategy.forceLandscape)
                    Text(PhotoOrientationStrategy.forcePortrait.displayName).tag(PhotoOrientationStrategy.forcePortrait)
                }
                .disabled(viewModel.isBusy)
                Picker("相框风格", selection: $viewModel.config.frameStylePreset) {
                    ForEach(FrameStylePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(viewModel.isBusy)
                if viewModel.config.frameStylePreset == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("背景灰度: \(viewModel.config.canvasBackgroundGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasBackgroundGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("相纸亮度: \(viewModel.config.canvasPaperWhite, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasPaperWhite, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("边框灰度: \(viewModel.config.canvasStrokeGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasStrokeGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("文字灰度: \(viewModel.config.canvasTextGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasTextGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                }
                Toggle("启用淡入淡出转场", isOn: $viewModel.config.enableCrossfade)
                    .disabled(viewModel.isBusy)
                VStack(alignment: .leading, spacing: 6) {
                    Text("转场时长: \(viewModel.config.transitionDuration, specifier: "%.2f")s")
                    Slider(value: $viewModel.config.transitionDuration, in: RenderEditorConfig.transitionDurationRange, step: 0.05)
                        .disabled(viewModel.isBusy || !viewModel.config.enableCrossfade)
                }
                Toggle("启用 Ken Burns", isOn: $viewModel.config.enableKenBurns)
                    .disabled(viewModel.isBusy)
            }

            Section("高级布局") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("左右留白: \(viewModel.config.horizontalMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.horizontalMargin, in: RenderEditorConfig.horizontalMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("上留白: \(viewModel.config.topMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.topMargin, in: RenderEditorConfig.topMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("下留白: \(viewModel.config.bottomMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.bottomMargin, in: RenderEditorConfig.bottomMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("内边距: \(viewModel.config.innerPadding, specifier: "%.0f")")
                    Slider(value: $viewModel.config.innerPadding, in: RenderEditorConfig.innerPaddingRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                Toggle("显示底部铭牌文字", isOn: $viewModel.config.plateEnabled)
                    .disabled(viewModel.isBusy)
                Picker("信息位置", selection: $viewModel.config.platePlacement) {
                    Text("相框").tag(PlatePlacement.frame)
                    Text("黑底下方").tag(PlatePlacement.canvasBottom)
                }
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)
            }

            Section("性能设置") {
                Stepper("预取半径: \(viewModel.config.prefetchRadius)", value: $viewModel.config.prefetchRadius, in: RenderEditorConfig.prefetchRadiusRange)
                    .disabled(viewModel.isBusy)
                Stepper("预取并发: \(viewModel.config.prefetchMaxConcurrent)", value: $viewModel.config.prefetchMaxConcurrent, in: RenderEditorConfig.prefetchMaxConcurrentRange)
                    .disabled(viewModel.isBusy)
            }

            audioSettingsSection
        }
        .formStyle(.grouped)
    }

    private var audioSettingsSection: some View {
        Section("音频 v1（预研）") {
            Toggle("启用背景音频", isOn: $viewModel.config.audioEnabled)
                .disabled(viewModel.isBusy)

            if viewModel.config.audioEnabled {
                HStack(spacing: 10) {
                    Button("选择音频") {
                        viewModel.chooseAudioTrack()
                    }
                    .disabled(viewModel.isBusy)

                    Button("清除音频") {
                        viewModel.clearAudioTrack()
                    }
                    .disabled(viewModel.isBusy || viewModel.selectedAudioFilename == nil)
                }

                if let name = viewModel.selectedAudioFilename {
                    Text("已选: \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未选择音频文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("音量: \(Int((viewModel.config.audioVolume * 100).rounded()))%")
                    Slider(value: $viewModel.config.audioVolume, in: RenderEditorConfig.audioVolumeRange, step: 0.01)
                        .disabled(viewModel.isBusy)
                }

                Toggle("自动循环至视频结束", isOn: $viewModel.config.audioLoopEnabled)
                    .disabled(viewModel.isBusy)

                if let message = viewModel.audioStatusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("将以单轨方式附加背景音频，不支持剪辑/淡入淡出编辑。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    Label("拖拽音频到此处", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("支持单条音频文件；将自动校验格式。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isAudioDropTarget ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isAudioDropTarget ? Color.accentColor : Color.secondary.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
                .onDrop(of: [UTType.fileURL], isTargeted: $isAudioDropTarget, perform: handleAudioDrop(providers:))
            }
        }
    }

    private func handleAudioDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let lock = NSLock()
        let group = DispatchGroup()
        var dropped: [URL] = []

        for provider in fileProviders {
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                defer { group.leave() }
                guard let item = item as? URL else { return }
                lock.lock()
                dropped.append(item)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            _ = viewModel.importDroppedAudioTrack(dropped)
        }

        return true
    }

    private func audioTimelineSegments(
        videoDuration: Double,
        audioDuration: Double?,
        loopEnabled: Bool
    ) -> [(start: Double, end: Double)] {
        guard videoDuration > 0, let audioDuration, audioDuration > 0 else { return [] }
        if !loopEnabled {
            return [(0, min(videoDuration, audioDuration))]
        }

        var segments: [(start: Double, end: Double)] = []
        var cursor: Double = 0
        while cursor < videoDuration {
            let end = min(videoDuration, cursor + audioDuration)
            segments.append((cursor, end))
            if end <= cursor { break }
            cursor = end
        }
        return segments
    }

    private var fpsPicker: some View {
        Picker("FPS", selection: $viewModel.config.fps) {
            ForEach(commonFPSOptions, id: \.self) { fps in
                Text("\(fps)").tag(fps)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.isBusy)
    }

    private var resolutionPresetBinding: Binding<ResolutionPreset> {
        Binding(
            get: {
                switch (viewModel.config.outputWidth, viewModel.config.outputHeight) {
                case (1280, 720): return .hd720
                case (1920, 1080): return .fullHD1080
                case (2560, 1440): return .qhd1440
                case (3840, 2160): return .uhd4K
                default: return .fullHD1080
                }
            },
            set: { preset in
                guard let size = preset.size else { return }
                viewModel.config.outputWidth = size.width
                viewModel.config.outputHeight = size.height
            }
        )
    }

    private var imageDurationPresetBinding: Binding<ImageDurationPreset> {
        Binding(
            get: {
                let value = viewModel.config.imageDuration
                let options: [(ImageDurationPreset, Double)] = [(.quick, 1.5), (.standard, 2.5), (.relaxed, 4.0)]
                return options.min(by: { abs($0.1 - value) < abs($1.1 - value) })?.0 ?? .standard
            },
            set: { preset in
                guard let seconds = preset.seconds else { return }
                viewModel.config.imageDuration = seconds
            }
        )
    }

    private var transitionPresetBinding: Binding<TransitionPreset> {
        Binding(
            get: {
                if !viewModel.config.enableCrossfade || viewModel.config.transitionDuration <= 0.001 {
                    return .off
                }
                let duration = viewModel.config.transitionDuration
                let options: [(TransitionPreset, Double)] = [(.soft, 0.4), (.standard, 0.8)]
                return options.min(by: { abs($0.1 - duration) < abs($1.1 - duration) })?.0 ?? .standard
            },
            set: { preset in
                switch preset {
                case .off:
                    viewModel.config.enableCrossfade = false
                    viewModel.config.transitionDuration = 0
                case .soft, .standard:
                    viewModel.config.enableCrossfade = true
                    if let duration = preset.transitionDuration {
                        viewModel.config.transitionDuration = duration
                    }
                case .custom: break
                }
            }
        )
    }

    private func orientationQuickChoiceButton(
        title: String,
        strategy: PhotoOrientationStrategy
    ) -> some View {
        let isSelected = viewModel.config.orientationStrategy == strategy
        return Button {
            viewModel.config.orientationStrategy = strategy
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                Text(title)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.4 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func frameStyleQuickChoiceButton(
        title: String,
        preset: FrameStylePreset
    ) -> some View {
        let isSelected = viewModel.config.frameStylePreset == preset
        return Button {
            viewModel.config.frameStylePreset = preset
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.4 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AssetReorderDropDelegate: DropDelegate {
    let destination: URL
    @Binding var dragging: URL?
    let canReorder: Bool
    let onMove: (URL, URL) -> Void

    func dropEntered(info: DropInfo) {
        guard canReorder else { return }
        guard let dragging, dragging != destination else { return }
        onMove(dragging, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        canReorder ? DropProposal(operation: .move) : DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

#Preview {
    ContentView()
}
