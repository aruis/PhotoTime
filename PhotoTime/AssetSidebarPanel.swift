import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AssetSidebarPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var selectedAssetURL: URL?
    @Binding var assetSearchText: String
    @Binding var isAssetDropTarget: Bool
    @Binding var draggingAssetURL: URL?

    var body: some View {
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

            Text("\(viewModel.imageURLs.count) 张")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if viewModel.problematicAssetNameSet.count > 0 {
                Text("· \(viewModel.problematicAssetNameSet.count) 个问题")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

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
}
