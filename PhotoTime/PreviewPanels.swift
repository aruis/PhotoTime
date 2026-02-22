import SwiftUI

struct SingleFramePreviewPanel: View {
    @ObservedObject var viewModel: ExportViewModel

    var body: some View {
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
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                Text("尚未生成预览")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在生成预览...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(viewModel.isPreviewGenerating ? 1 : 0)

                if let previewError = viewModel.previewErrorMessage {
                    Text("预览错误: \(previewError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

struct VideoTimelinePreviewPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    let audioSegments: [(start: Double, end: Double)]

    var body: some View {
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
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "film")
                                Text("尚未生成预览")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在生成预览...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(viewModel.isPreviewGenerating ? 1 : 0)

                if let previewError = viewModel.previewErrorMessage {
                    Text("预览错误: \(previewError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
