import SwiftUI
import UniformTypeIdentifiers

struct AudioSettingsSection: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool

    var body: some View {
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
                .onDrop(of: [UTType.fileURL], isTargeted: $isAudioDropTarget, perform: onAudioDrop)
            }
        }
    }
}
