import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AssetSidebarPanel: View {
    private struct SidebarGridLayout {
        let columns: [GridItem]
        let cardHeight: CGFloat
        let thumbnailHeight: CGFloat
        let fileNameLineLimit: Int
    }

    @ObservedObject var viewModel: ExportViewModel
    @Binding var selectedAssetURL: URL?
    @Binding var selectedAssetURLs: Set<URL>
    @Binding var isAssetDropTarget: Bool
    @Binding var draggingAssetURL: URL?
    @State private var localKeyMonitor: Any?
    @State private var focusedAssetURL: URL?
    private let sidebarGridSpacing: CGFloat = 10
    private let sidebarGridPadding: CGFloat = 12
    private let singleColumnMinimumWidth: CGFloat = 210
    private let twoColumnMinimumWidth: CGFloat = 150

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                if viewModel.imageURLs.isEmpty {
                    emptyAssetDropView
                } else {
                    GeometryReader { geometry in
                        let layout = sidebarGridLayout(for: geometry.size.width)

                        ScrollView {
                            LazyVGrid(
                                columns: layout.columns,
                                spacing: sidebarGridSpacing
                            ) {
                                ForEach(sidebarFilteredAssets, id: \.self) { url in
                                    assetThumbnailItem(
                                        url: url,
                                        cardHeight: layout.cardHeight,
                                        thumbnailHeight: layout.thumbnailHeight,
                                        fileNameLineLimit: layout.fileNameLineLimit
                                    )
                                        .id(url)
                                }
                            }
                            .padding(sidebarGridPadding)
                        }
                    }
                }
            }
            .onChange(of: selectedAssetURL) { _, newValue in
                guard let newValue, sidebarFilteredAssets.contains(newValue) else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
                focusAsset(newValue)
            }
        }
        .background(isAssetDropTarget ? Color.accentColor.opacity(0.12) : Color.clear)
        .animation(.easeInOut(duration: 0.12), value: isAssetDropTarget)
        .onDrop(of: [UTType.fileURL], isTargeted: $isAssetDropTarget, perform: handleAssetDrop(providers:))
        .onDeleteCommand(perform: deleteSelectedAsset)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .safeAreaInset(edge: .bottom) {
            assetBottomBar
        }
    }

    private var emptyAssetDropView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Button("导入图片") {
                viewModel.addImages()
            }
            .buttonStyle(.borderedProminent)
            VStack(spacing: 4) {
                Text("支持拖入图片或文件夹")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
    }

    private var assetBottomBar: some View {
        ViewThatFits(in: .horizontal) {
            assetBottomBarRegular
            assetBottomBarCompact
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var assetBottomBarRegular: some View {
        HStack(spacing: 8) {
            if !viewModel.imageURLs.isEmpty {
                filterToggleButtons(compact: false)
            }

            Spacer(minLength: 0)

            assetSummaryLabels(showProblemCount: true)

            addImagesButton
        }
    }

    private var assetBottomBarCompact: some View {
        HStack(spacing: 6) {
            if !viewModel.imageURLs.isEmpty {
                filterToggleButtons(compact: true)
            }

            Spacer(minLength: 0)

            assetSummaryLabels(showProblemCount: false)

            addImagesButton
        }
    }

    private var addImagesButton: some View {
        Group {
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
    }

    private func assetSummaryLabels(showProblemCount: Bool) -> some View {
        HStack(spacing: 4) {
            Text(assetSelectionSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if showProblemCount, viewModel.problematicAssetNameSet.count > 0 {
                Text("\(viewModel.problematicAssetNameSet.count) 问题")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .lineLimit(1)
    }

    private var assetSelectionSummaryText: String {
        let totalCount = viewModel.imageURLs.count
        let selectedCount = selectedAssetURLs.count
        guard selectedCount > 0 else {
            return "\(totalCount)"
        }
        return "\(selectedCount)/\(totalCount)"
    }

    private func assetThumbnailItem(
        url: URL,
        cardHeight: CGFloat,
        thumbnailHeight: CGFloat,
        fileNameLineLimit: Int
    ) -> some View {
        let fileName = url.lastPathComponent
        let tags = viewModel.preflightIssueTags(for: fileName)
        let isSelected = selectedAssetURLs.contains(url)
        let isFocused = focusedAssetURL == url

        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AssetThumbnailView(url: url, height: thumbnailHeight)

                if !tags.isEmpty || viewModel.failedAssetNames.contains(fileName) {
                    Circle()
                        .fill(tags.contains("必须修复") || viewModel.failedAssetNames.contains(fileName) ? .red : .orange)
                        .frame(width: 8, height: 8)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: thumbnailHeight, maxHeight: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .clipped()

            Text(fileName)
                .font(.caption2)
                .lineLimit(fileNameLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isFocused
                    ? Color.accentColor.opacity(0.22)
                    : (isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? Color.accentColor : (isSelected ? Color.accentColor : Color.secondary.opacity(0.18)),
                    lineWidth: isFocused ? 2.2 : (isSelected ? 1.5 : 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .frame(height: cardHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
        .accessibilityIdentifier("asset_card_\(accessibilityToken(for: fileName))")
        .accessibilityValue(isFocused ? "focused" : (isSelected ? "selected" : "idle"))
        .onTapGesture {
            handleAssetTap(url)
        }
        .contextMenu {
            Button("删除") {
                selectedAssetURLs = [url]
                deleteSelectedAsset()
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
                selectedAssetURLs = [source]
            }
        )
        .help(assetTagLine(fileName: fileName, issueTags: tags))
    }

    private func deleteSelectedAsset() {
        let targets = selectedAssetURLs.isEmpty ? Set(selectedAssetURL.map { [$0] } ?? []) : selectedAssetURLs
        guard !targets.isEmpty else { return }
        viewModel.removeImages(Array(targets))
        selectedAssetURLs = []
        selectedAssetURL = sidebarFilteredAssets.first
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
        sidebarBaseAssets
    }

    private var sidebarBaseAssets: [URL] {
        if viewModel.fileListFilter == .all {
            return viewModel.imageURLs
        }
        return viewModel.filteredImageURLsForDisplay
    }

    private var canReorderAssets: Bool {
        viewModel.fileListFilter == .all && selectedAssetURLs.count <= 1
    }

    private func sidebarGridLayout(for availableWidth: CGFloat) -> SidebarGridLayout {
        let contentWidth = max(availableWidth - sidebarGridPadding * 2, 0)
        let twoColumnThreshold = twoColumnMinimumWidth * 2 + sidebarGridSpacing
        let usesTwoColumns = contentWidth >= twoColumnThreshold
        let columnCount = usesTwoColumns ? 2 : 1
        let totalSpacing = sidebarGridSpacing * CGFloat(max(0, columnCount - 1))
        let itemWidth = max(
            usesTwoColumns ? twoColumnMinimumWidth : singleColumnMinimumWidth,
            (contentWidth - totalSpacing) / CGFloat(columnCount)
        )

        return SidebarGridLayout(
            columns: Array(
                repeating: GridItem(.fixed(itemWidth), spacing: sidebarGridSpacing),
                count: columnCount
            ),
            cardHeight: usesTwoColumns ? 104 : 132,
            thumbnailHeight: usesTwoColumns ? 72 : 94,
            fileNameLineLimit: usesTwoColumns ? 1 : 2
        )
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

    private func filterToggleButtons(compact: Bool) -> some View {
        HStack(spacing: 4) {
            filterButton(
                title: "全部",
                icon: "line.3.horizontal.decrease.circle",
                help: "显示全部素材",
                filter: .all,
                compact: compact
            )
            filterButton(
                title: "问题",
                icon: "exclamationmark.triangle",
                help: "仅显示问题素材",
                filter: .problematic,
                compact: compact
            )
            filterButton(
                title: "必修",
                icon: "xmark.octagon",
                help: "仅显示必须修复",
                filter: .mustFix,
                compact: compact
            )
            filterButton(
                title: "正常",
                icon: "checkmark.circle",
                help: "仅显示正常素材",
                filter: .normal,
                compact: compact
            )
        }
    }

    private func filterButton(
        title: String,
        icon: String,
        help: String,
        filter: ExportViewModel.FileListFilter,
        compact: Bool
    ) -> some View {
        let isActive = viewModel.fileListFilter == filter
        return Button {
            viewModel.fileListFilter = filter
        } label: {
            Group {
                if compact {
                    Image(systemName: icon)
                        .font(.caption)
                        .frame(width: 18, height: 18)
                } else {
                    Label(title, systemImage: icon)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 20)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isActive ? .accentColor : .gray.opacity(0.35))
        .help(help)
    }

    private func handleAssetTap(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedAssetURLs.contains(url) {
                selectedAssetURLs.remove(url)
                if selectedAssetURL == url {
                    selectedAssetURL = selectedAssetURLs.first
                }
            } else {
                selectedAssetURLs.insert(url)
                selectedAssetURL = url
            }
            return
        }
        selectedAssetURLs = [url]
        selectedAssetURL = url
        focusAsset(url)
    }

    private func focusAsset(_ url: URL) {
        focusedAssetURL = url
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                if focusedAssetURL == url {
                    focusedAssetURL = nil
                }
            }
        }
    }

    private func selectAllVisibleAssets() {
        guard !sidebarFilteredAssets.isEmpty else { return }
        selectedAssetURLs = Set(sidebarFilteredAssets)
        selectedAssetURL = sidebarFilteredAssets.first
    }

    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard shouldHandleGlobalShortcut else { return event }

        let characters = event.charactersIgnoringModifiers ?? ""
        let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117 || characters == "\u{8}"

        if commandPressed, characters.lowercased() == "a" {
            selectAllVisibleAssets()
            return nil
        }

        if !commandPressed, isDeleteKey {
            deleteSelectedAsset()
            return nil
        }

        return event
    }

    private var shouldHandleGlobalShortcut: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return true }
        return !(responder is NSTextView)
    }

    private func accessibilityToken(for value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
    }
}
