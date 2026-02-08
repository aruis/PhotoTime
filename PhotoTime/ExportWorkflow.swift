import Foundation

enum ExportWorkflowState: String, Sendable {
    case idle
    case previewing
    case exporting
    case cancelling
    case succeeded
    case failed
}

struct ExportWorkflowModel: Sendable {
    private(set) var state: ExportWorkflowState = .idle
    private(set) var progress: Double = 0
    private(set) var statusMessage: String = "请选择图片并设置导出路径"

    var isBusy: Bool {
        switch state {
        case .previewing, .exporting, .cancelling:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }

    var isExporting: Bool {
        switch state {
        case .exporting, .cancelling:
            return true
        case .idle, .previewing, .succeeded, .failed:
            return false
        }
    }

    mutating func beginPreview() -> Bool {
        guard !isBusy else { return false }
        state = .previewing
        statusMessage = "生成预览中..."
        return true
    }

    mutating func finishPreviewSuccess() {
        state = .idle
        statusMessage = "预览已更新"
    }

    mutating func finishPreviewFailure(message: String) {
        state = .idle
        statusMessage = message
    }

    mutating func beginExport(isRetry: Bool) -> Bool {
        guard !isBusy else { return false }
        state = .exporting
        progress = 0
        statusMessage = isRetry ? "开始重试导出..." : "开始导出..."
        return true
    }

    mutating func updateExportProgress(_ value: Double) {
        guard state == .exporting || state == .cancelling else { return }
        progress = max(0, min(value, 1))
    }

    mutating func requestCancel() {
        guard state == .exporting else { return }
        state = .cancelling
        statusMessage = "正在取消导出..."
    }

    mutating func finishExportSuccess(message: String) {
        state = .succeeded
        progress = 1
        statusMessage = message
    }

    mutating func finishExportFailure(message: String) {
        state = .failed
        statusMessage = message
    }

    mutating func setIdleMessage(_ message: String) {
        guard !isBusy else { return }
        state = .idle
        statusMessage = message
    }
}
