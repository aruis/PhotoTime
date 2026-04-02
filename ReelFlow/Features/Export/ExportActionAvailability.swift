import Foundation

struct ExportActionAvailability: Sendable {
    let canSelectImages: Bool
    let canSelectOutput: Bool
    let canStartExport: Bool
    let canCancelExport: Bool
    let canGeneratePreview: Bool
    let canImportTemplate: Bool
    let canSaveTemplate: Bool
    let canRetryExport: Bool

    init(workflowState: ExportWorkflowState, hasRetryTask: Bool) {
        let isBusy: Bool
        let isExporting: Bool
        switch workflowState {
        case .previewing, .exporting, .cancelling:
            isBusy = true
        case .idle, .succeeded, .failed:
            isBusy = false
        }

        switch workflowState {
        case .exporting, .cancelling:
            isExporting = true
        case .idle, .previewing, .succeeded, .failed:
            isExporting = false
        }

        canSelectImages = !isBusy
        canSelectOutput = !isBusy
        canStartExport = !isBusy
        canCancelExport = isExporting
        canGeneratePreview = !isBusy
        canImportTemplate = !isBusy
        canSaveTemplate = !isBusy
        canRetryExport = !isBusy && hasRetryTask
    }
}
