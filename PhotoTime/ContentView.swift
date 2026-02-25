import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    @StateObject private var viewModel = ExportViewModel()
    @State private var centerPreviewTab: CenterPreviewTab = .singleFrame
    @State private var settingsTab: SettingsTab = .simple
    @State private var selectedAssetURL: URL?
    @State private var singlePreviewDebounceTask: Task<Void, Never>?
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

    var body: some View {
        NavigationSplitView(columnVisibility: $splitColumnVisibility) {
            sidebarAssetColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            workspaceDetailSplit
                .navigationSplitViewColumnWidth(min: 860, ideal: 1040)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("PhotoTime")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.hasSelectedImages {
                    Button("导出 MP4") { viewModel.export() }
                        .accessibilityIdentifier("primary_export")
                        .disabled(!viewModel.canRunExport)
                }
                if viewModel.isExporting {
                    Button("取消导出") { viewModel.cancelExport() }
                        .accessibilityIdentifier("primary_cancel")
                        .disabled(!viewModel.actionAvailability.canCancelExport)
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu("更多") {
                    Button("选择导出路径") { viewModel.chooseOutput() }
                        .accessibilityIdentifier("primary_select_output")
                        .disabled(!viewModel.actionAvailability.canSelectOutput)
                    if viewModel.hasSelectedImages {
                        Button("生成预览") {
                            if centerPreviewTab == .singleFrame, let selected = selectedAssetForPreview {
                                viewModel.generatePreviewForSelectedAsset(selected)
                            } else {
                                viewModel.generatePreview()
                            }
                        }
                            .accessibilityIdentifier("secondary_preview")
                            .disabled(!viewModel.canRunPreview)
                        Button("运行预检") { viewModel.rerunPreflight() }
                            .accessibilityIdentifier("secondary_rerun_preflight")
                            .disabled(viewModel.isBusy || viewModel.imageURLs.isEmpty)
                        Divider()
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
                        #if DEBUG
                        Divider()
                        Button("模拟导出失败") { viewModel.simulateExportFailure() }
                            .disabled(viewModel.isBusy)
                        #endif
                    }
                }
                .accessibilityIdentifier("toolbar_more_menu")
            }
        }
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
        AssetSidebarPanel(
            viewModel: viewModel,
            selectedAssetURL: $selectedAssetURL,
            isAssetDropTarget: $isAssetDropTarget,
            draggingAssetURL: $draggingAssetURL
        )
    }

    private var workspaceDetailSplit: some View {
        HSplitView {
            centerPreviewColumn
                .frame(minWidth: 520, idealWidth: 680, maxWidth: .infinity)
            rightSettingsColumn
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
        }
    }

    private var centerPreviewColumn: some View {
        Group {
            if shouldUseFullHeightEmptyState {
                VStack(alignment: .leading, spacing: 14) {
                    if let validationMessage = viewModel.validationMessage {
                        Text("参数校验: \(validationMessage)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settings_validation_message")
                    }

                    emptyPreviewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let validationMessage = viewModel.validationMessage {
                            Text("参数校验: \(validationMessage)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("settings_validation_message")
                        }

                        if viewModel.hasSelectedImages {
                            Picker("预览模式", selection: $centerPreviewTab) {
                                ForEach(CenterPreviewTab.allCases) { tab in
                                    Text(tab.title).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)

                            if centerPreviewTab == .singleFrame {
                                previewPanel
                            } else {
                                videoPreviewPanel
                            }
                        } else {
                            emptyPreviewPanel
                        }

                        workflowPanel
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.hasSelectedImages || viewModel.hasFailureCard || viewModel.hasSuccessCard {
                exportStatusPanel
            }

            if viewModel.hasSelectedImages, viewModel.outputURL == nil {
                outputPathHintPanel
            }

            if let report = viewModel.preflightReport, !report.issues.isEmpty {
                PreflightPanel(
                    viewModel: viewModel,
                    displayIssues: preflightDisplayIssues(report: report),
                    filteredIgnoredIssues: filteredIgnoredIssues,
                    onSelectAsset: { selectedAssetURL = $0 },
                    expansionBindingForKey: { key in preflightIssueExpandedBinding(for: key) },
                    preflightSecondaryActionsExpanded: $preflightSecondaryActionsExpanded,
                    preflightOnlyPending: $preflightOnlyPending,
                    preflightPrioritizeMustFix: $preflightPrioritizeMustFix,
                    expandedPreflightIssueKeys: $expandedPreflightIssueKeys,
                    ignoredIssuesExpanded: $ignoredIssuesExpanded,
                    ignoredIssueSearchText: $ignoredIssueSearchText
                )
            }
        }
        .textSelection(.enabled)
    }

    private var outputPathHintPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("导出前请先选择导出路径。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("选择导出路径") { viewModel.chooseOutput() }
                .controlSize(.small)
                .disabled(!viewModel.actionAvailability.canSelectOutput)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyPreviewPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("从左侧开始，先导入图片")
                        .font(.headline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08), in: Capsule())

                Text("导入后，这里会显示预览与导出状态。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(24)
        }
        .frame(minHeight: 320)
    }

    private var exportStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkflowOverviewPanel(
                statusMessage: viewModel.statusMessage,
                nextActionHint: viewModel.nextActionHint,
                firstRunPrimaryActionTitle: firstRunPrimaryAction?.title,
                isBusy: viewModel.isBusy,
                onFirstRunPrimaryAction: { firstRunPrimaryAction?.handler() }
            )

            if viewModel.isExporting {
                ProgressView(value: viewModel.progress)
                    .frame(maxWidth: .infinity)
            }

            if viewModel.hasFailureCard, let copy = viewModel.failureCardCopy {
                FailureStatusCard(
                    copy: copy,
                    isBusy: viewModel.isBusy,
                    onPrimaryAction: { viewModel.performRecoveryAction() },
                    onOpenLog: { viewModel.openLatestLog() }
                )
            }

            if viewModel.hasSuccessCard {
                SuccessStatusCard(
                    filename: viewModel.latestOutputFilename,
                    logPath: viewModel.latestLogPath,
                    isBusy: viewModel.isBusy,
                    onExportAgain: { viewModel.export() },
                    onOpenOutputFile: { viewModel.openLatestOutputFile() },
                    onOpenOutputDirectory: { viewModel.openLatestOutputDirectory() },
                    onOpenLog: { viewModel.openLatestLog() }
                )
            }

            if !viewModel.failedAssetNames.isEmpty {
                FailedAssetsPanel(
                    names: failedAssetNamesPreview,
                    hiddenCount: failedAssetHiddenCount
                )
            }
        }
    }

    private var firstRunPrimaryAction: (title: String, handler: () -> Void)? {
        if !viewModel.hasSelectedImages {
            return ("导入图片", { viewModel.chooseImages() })
        }
        if viewModel.validationMessage != nil {
            return nil
        }
        if !viewModel.hasSuccessCard {
            return ("导出 MP4", { viewModel.export() })
        }
        if !viewModel.hasPreviewFrame {
            return ("可选：生成预览", {
                if centerPreviewTab == .singleFrame, let selected = selectedAssetForPreview {
                    viewModel.generatePreviewForSelectedAsset(selected)
                } else {
                    viewModel.generatePreview()
                }
            })
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

    private var shouldUseFullHeightEmptyState: Bool {
        !viewModel.hasSelectedImages
            && !viewModel.hasFailureCard
            && !viewModel.hasSuccessCard
            && (viewModel.preflightReport?.issues.isEmpty ?? true)
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
        SingleFramePreviewPanel(viewModel: viewModel)
    }

    private var videoPreviewPanel: some View {
        let videoDuration = max(viewModel.previewMaxSecond, 0)
        let audioSegments = audioTimelineSegments(
            videoDuration: videoDuration,
            audioDuration: viewModel.selectedAudioDuration,
            loopEnabled: viewModel.config.audioLoopEnabled
        )
        return VideoTimelinePreviewPanel(
            viewModel: viewModel,
            audioSegments: audioSegments
        )
    }

    private var settingsPanel: some View {
        Group {
            if settingsTab == .simple {
                SimpleSettingsPanel(
                    viewModel: viewModel,
                    isAudioDropTarget: $isAudioDropTarget,
                    onAudioDrop: handleAudioDrop(providers:)
                )
            } else {
                AdvancedSettingsPanel(
                    viewModel: viewModel,
                    isAudioDropTarget: $isAudioDropTarget,
                    onAudioDrop: handleAudioDrop(providers:)
                )
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
}

#Preview {
    ContentView()
}
