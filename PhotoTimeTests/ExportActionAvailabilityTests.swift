import Testing
@testable import PhotoTime

struct ExportActionAvailabilityTests {
    @Test
    func idleStateEnablesPrimaryActions() {
        let availability = ExportActionAvailability(workflowState: .idle, hasRetryTask: false)

        #expect(availability.canSelectImages)
        #expect(availability.canSelectOutput)
        #expect(availability.canStartExport)
        #expect(availability.canGeneratePreview)
        #expect(!availability.canCancelExport)
        #expect(!availability.canRetryExport)
    }

    @Test
    func exportingStateOnlyAllowsCancel() {
        let availability = ExportActionAvailability(workflowState: .exporting, hasRetryTask: true)

        #expect(!availability.canSelectImages)
        #expect(!availability.canSelectOutput)
        #expect(!availability.canStartExport)
        #expect(!availability.canGeneratePreview)
        #expect(!availability.canImportTemplate)
        #expect(!availability.canSaveTemplate)
        #expect(availability.canCancelExport)
        #expect(!availability.canRetryExport)
    }

    @Test
    func failedStateAllowsRetryWhenTaskExists() {
        let noRetry = ExportActionAvailability(workflowState: .failed, hasRetryTask: false)
        let withRetry = ExportActionAvailability(workflowState: .failed, hasRetryTask: true)

        #expect(!noRetry.canRetryExport)
        #expect(withRetry.canRetryExport)
        #expect(withRetry.canStartExport)
        #expect(!withRetry.canCancelExport)
    }
}
