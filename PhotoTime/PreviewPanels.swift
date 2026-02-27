import SwiftUI

struct SingleFramePreviewPanel: View {
    @ObservedObject var viewModel: ExportViewModel

    var body: some View {
        GroupBox("单帧预览") {
            VStack(alignment: .leading, spacing: 12) {
                previewSurface(
                    image: viewModel.previewImage,
                    placeholderSystemImage: "photo",
                    placeholderText: "尚未生成单帧预览",
                    accessibilityIdentifier: "single_frame_preview_surface"
                )

                PreviewStatusRow(
                    statusMessage: viewModel.previewStatusMessage,
                    errorMessage: viewModel.previewErrorMessage,
                    isBusy: viewModel.isPreviewGenerating,
                    accessibilityIdentifier: "single_frame_preview_status"
                )
            }
        }
    }
}

struct VideoTimelinePreviewPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    let audioSegments: [(start: Double, end: Double)]

    var body: some View {
        GroupBox("时间轴预览") {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.config.audioEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        let videoDuration = max(viewModel.previewMaxSecond, 0)
                        let audioDuration = viewModel.selectedAudioDuration
                        let audioName = viewModel.selectedAudioFilename ?? "未选择音频"

                        Text("音轨: \(audioName)")
                            .font(.caption)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.12))
                            GeometryReader { proxy in
                                let width = proxy.size.width
                                ForEach(Array(audioSegments.enumerated()), id: \.offset) { _, segment in
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

                previewSurface(
                    image: viewModel.previewImage,
                    placeholderSystemImage: "film",
                    placeholderText: "尚未生成时间轴预览",
                    accessibilityIdentifier: "timeline_preview_surface"
                )

                PreviewStatusRow(
                    statusMessage: viewModel.previewStatusMessage,
                    errorMessage: viewModel.previewErrorMessage,
                    isBusy: viewModel.isPreviewGenerating,
                    accessibilityIdentifier: "timeline_preview_status"
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("时间: \(viewModel.previewSecond, specifier: "%.2f")s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("总时长: \(viewModel.previewMaxSecond, specifier: "%.2f")s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityIdentifier("timeline_preview_duration")
                    }

                    Slider(
                        value: $viewModel.previewSecond,
                        in: 0...max(viewModel.previewMaxSecond, 0.001)
                    )
                    .onChange(of: viewModel.previewSecond) { _, _ in
                        viewModel.schedulePreviewRegeneration()
                        viewModel.syncAudioPreviewPosition()
                    }
                    .disabled(viewModel.isBusy || viewModel.imageURLs.isEmpty)
                    .accessibilityIdentifier("timeline_preview_slider")

                    if !viewModel.canRunPreview && !viewModel.imageURLs.isEmpty {
                        Text("当前参数下无法刷新预览，请先修正校验问题或等待当前任务结束。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private extension View {
    func previewSurface(
        image: NSImage?,
        placeholderSystemImage: String,
        placeholderText: String,
        accessibilityIdentifier: String
    ) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                    .padding(.vertical, 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: placeholderSystemImage)
                            Text(placeholderText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PreviewStatusRow: View {
    let statusMessage: String
    let errorMessage: String?
    let isBusy: Bool
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(isBusy ? .primary : .secondary)
                    .lineLimit(2)
            }

            if let errorMessage {
                Text("预览错误: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
