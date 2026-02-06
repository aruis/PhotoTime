import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var imageURLs: [URL] = []
    @Published var outputURL: URL?
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var statusMessage = "请选择图片并设置导出路径"

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageURLs = panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        statusMessage = "已选择 \(imageURLs.count) 张图片"
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "PhotoTime-Output.mp4"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        statusMessage = "导出路径: \(url.path)"
    }

    func export() {
        guard !isExporting else { return }
        guard !imageURLs.isEmpty else {
            statusMessage = "请先选择图片"
            return
        }
        guard let outputURL else {
            statusMessage = "请先选择导出路径"
            return
        }

        isExporting = true
        progress = 0
        statusMessage = "开始导出..."

        let urls = imageURLs
        let destination = outputURL

        Task.detached {
            do {
                let engine = RenderEngine()
                try await engine.export(imageURLs: urls, outputURL: destination) { value in
                    Task { @MainActor [weak self] in
                        self?.progress = value
                    }
                }

                await MainActor.run {
                    self.statusMessage = "导出完成: \(destination.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isExporting = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ExportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PhotoTime MVP")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button("选择图片") { viewModel.chooseImages() }
                Button("选择导出路径") { viewModel.chooseOutput() }
                Button("导出 MP4") { viewModel.export() }
                    .disabled(viewModel.isExporting)
            }

            if !viewModel.imageURLs.isEmpty {
                Text("已选文件")
                    .font(.headline)
                List(viewModel.imageURLs, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
                .frame(height: 220)
            }

            if viewModel.isExporting {
                ProgressView(value: viewModel.progress)
                    .frame(maxWidth: .infinity)
            }

            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

#Preview {
    ContentView()
}
