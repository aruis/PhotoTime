import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

private enum AssetThumbnailPipeline {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    @MainActor
    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated static func renderThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
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

        return NSImage(cgImage: cgImage, size: .zero)
    }

    @MainActor
    static func cacheImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
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
                AssetThumbnailPipeline.renderThumbnail(for: url, maxPixelSize: target)
            }.value
            guard !Task.isCancelled else { return }
            if let loaded {
                AssetThumbnailPipeline.cacheImage(loaded, for: url)
            }
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
                    Divider()
                    Button("导出排障包") { viewModel.exportDiagnosticsBundle() }
                        .accessibilityIdentifier("secondary_export_diagnostics")
                        .disabled(viewModel.isBusy)
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
