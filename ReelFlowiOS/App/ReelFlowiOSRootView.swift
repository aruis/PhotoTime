import PhotosUI
import SwiftUI
import UIKit

struct ReelFlowiOSRootView: View {
    @StateObject private var viewModel = IOSExportViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    private let previewBridge: any PreviewImageBridging = SwiftUIPreviewImageBridge()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mediaSection
                    settingsSection
                    previewSection
                    exportSection
                }
                .padding(16)
            }
            .navigationTitle("ReelFlow iOS")
            .task {
                await viewModel.applyDebugScenarioIfNeeded()
            }
            .onChange(of: selectedItems) { _, items in
                Task {
                    await viewModel.importPhotos(from: items)
                    selectedItems = []
                }
            }
        }
    }

    private var mediaSection: some View {
        sectionCard(title: "素材") {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 50,
                matching: .images
            ) {
                Label("选择照片", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("ios_pick_photos")

            Text(viewModel.selectedCountText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ios_selected_count")

            if let importStatusMessage = viewModel.importStatusMessage {
                Text(importStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.imageURLs, id: \.self) { url in
                            if let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        sectionCard(title: "简单设置") {
            Picker("分辨率", selection: $viewModel.config.resolution) {
                ForEach(MobileResolutionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Picker("FPS", selection: $viewModel.config.fps) {
                ForEach([24, 30, 60], id: \.self) { fps in
                    Text("\(fps)").tag(fps)
                }
            }
            .pickerStyle(.segmented)

            Picker("展示节奏", selection: $viewModel.config.duration) {
                ForEach(MobileDurationPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Picker("转场", selection: $viewModel.config.transition) {
                ForEach(MobileTransitionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Picker("Ken Burns", selection: $viewModel.config.kenBurns) {
                ForEach(MobileKenBurnsPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Toggle("启用快门声", isOn: $viewModel.config.shutterSoundEnabled)
                .accessibilityIdentifier("ios_shutter_toggle")

            if viewModel.config.shutterSoundEnabled {
                Picker("快门型号", selection: $viewModel.config.shutterSoundPreset) {
                    ForEach(ShutterSoundPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("快门声音量 \(Int((viewModel.config.shutterSoundVolume * 100).rounded()))%")
                    Slider(value: $viewModel.config.shutterSoundVolume, in: 0...1, step: 0.01)
                }
            }
        }
    }

    private var previewSection: some View {
        sectionCard(title: "单帧预览") {
            Group {
                if let previewImage = viewModel.previewImage {
                    previewBridge.makeImage(from: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                Text("尚未生成预览")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("ios_preview_surface")

            Button("刷新预览") {
                Task { await viewModel.generatePreview() }
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canGeneratePreview)
            .accessibilityIdentifier("ios_generate_preview")

            Text(viewModel.previewStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ios_preview_status")

            if let previewErrorMessage = viewModel.previewErrorMessage {
                Text(previewErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !viewModel.reviewIssues.isEmpty {
                Text("预检提示：\(viewModel.reviewIssues.count) 个建议关注问题")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportSection: some View {
        sectionCard(title: "导出") {
            Button {
                Task { await viewModel.exportVideo() }
            } label: {
                if viewModel.workflow.isExporting {
                    ProgressView(value: viewModel.workflow.progress) {
                        Text("导出中…")
                    }
                } else {
                    Text("导出 MP4")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExport)
            .accessibilityIdentifier("ios_export_button")

            Text(viewModel.workflow.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ios_export_status")

            if let latestOutputURL = viewModel.latestOutputURL {
                ShareLink(item: latestOutputURL) {
                    Label("分享视频", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ios_share_video")

                Button("保存到相册") {
                    Task { await viewModel.saveLatestVideoToPhotos() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ios_save_video")

                Text(latestOutputURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveStatusMessage = viewModel.saveStatusMessage {
                Text(saveStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
