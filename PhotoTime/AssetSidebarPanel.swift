import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AssetSidebarPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var selectedAssetURL: URL?
    @Binding var isAssetDropTarget: Bool
    @Binding var draggingAssetURL: URL?
    private let thumbnailHeight: CGFloat = 72
    private let cardHeight: CGFloat = 104

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
        HStack(spacing: 8) {
            if !viewModel.imageURLs.isEmpty {
                filterToggleButtons
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
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(height: cardHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
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
        sidebarBaseAssets
    }

    private var sidebarBaseAssets: [URL] {
        if viewModel.fileListFilter == .all {
            return viewModel.imageURLs
        }
        return viewModel.filteredImageURLsForDisplay
    }

    private var canReorderAssets: Bool {
        viewModel.fileListFilter == .all
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

    private var filterToggleButtons: some View {
        HStack(spacing: 4) {
            filterButton(
                icon: "line.3.horizontal.decrease.circle",
                help: "显示全部素材",
                filter: .all
            )
            filterButton(
                icon: "exclamationmark.triangle",
                help: "仅显示问题素材",
                filter: .problematic
            )
            filterButton(
                icon: "xmark.octagon",
                help: "仅显示必须修复",
                filter: .mustFix
            )
            filterButton(
                icon: "checkmark.circle",
                help: "仅显示正常素材",
                filter: .normal
            )
        }
    }

    private func filterButton(
        icon: String,
        help: String,
        filter: ExportViewModel.FileListFilter
    ) -> some View {
        let isActive = viewModel.fileListFilter == filter
        return Button {
            viewModel.fileListFilter = filter
        } label: {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isActive ? .accentColor : .gray.opacity(0.35))
        .help(help)
    }
}
