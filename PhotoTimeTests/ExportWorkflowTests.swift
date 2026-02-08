import Testing
@testable import PhotoTime

struct ExportWorkflowTests {
    @Test
    func workflowRejectsConcurrentStart() {
        var workflow = ExportWorkflowModel()

        let startedPreview = workflow.beginPreview()
        let startedExportWhilePreviewing = workflow.beginExport(isRetry: false)
        #expect(startedPreview)
        #expect(!startedExportWhilePreviewing)
        #expect(workflow.state == .previewing)

        workflow.finishPreviewSuccess()
        #expect(workflow.state == .idle)
    }

    @Test
    func workflowExportCancellationPath() {
        var workflow = ExportWorkflowModel()

        let started = workflow.beginExport(isRetry: false)
        #expect(started)
        #expect(workflow.state == .exporting)

        workflow.updateExportProgress(0.4)
        #expect(workflow.progress == 0.4)

        workflow.requestCancel()
        #expect(workflow.state == .cancelling)
        #expect(workflow.isExporting)

        workflow.finishExportFailure(message: "[E_EXPORT_CANCELLED] 导出已取消")
        #expect(workflow.state == .failed)
        #expect(!workflow.isBusy)
    }

    @Test
    func workflowSuccessSetsProgressToDone() {
        var workflow = ExportWorkflowModel()

        let started = workflow.beginExport(isRetry: true)
        #expect(started)
        workflow.updateExportProgress(0.65)
        workflow.finishExportSuccess(message: "ok")

        #expect(workflow.state == .succeeded)
        #expect(workflow.progress == 1)
        #expect(!workflow.isExporting)
    }

    @Test
    func workflowPreviewFailureReturnsToIdle() {
        var workflow = ExportWorkflowModel()
        let started = workflow.beginPreview()
        #expect(started)
        #expect(workflow.state == .previewing)

        workflow.finishPreviewFailure(message: "preview error")
        #expect(workflow.state == .idle)
        #expect(!workflow.isBusy)
    }
}
