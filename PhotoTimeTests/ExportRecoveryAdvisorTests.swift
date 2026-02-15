import Foundation
import Testing
@testable import PhotoTime

struct ExportRecoveryAdvisorTests {
    @Test
    func contextFromRenderErrorKeepsCodeAndLogPath() {
        let logURL = URL(fileURLWithPath: "/tmp/render.log")
        let context = ExportFailureContext.from(
            error: RenderEngineError.assetLoadFailed(index: 1, message: "bad data"),
            failedAssetNames: ["a.jpg"],
            logURL: logURL,
            stage: .export
        )

        #expect(context.code == "E_IMAGE_LOAD")
        #expect(context.stage == .export)
        #expect(context.logPath == "/tmp/render.log")
        #expect(context.failedAssetNames == ["a.jpg"])
        #expect(context.displayHead.contains("[E_IMAGE_LOAD]"))
    }

    @Test
    func advisorUsesStructuredErrorCodeFirst() {
        let context = ExportFailureContext(
            code: "E_EXPORT_CANCELLED",
            stage: .export,
            message: "custom message",
            failedAssetNames: [],
            logPath: "/tmp/render.log",
            rawDescription: "irrelevant"
        )

        let advice = ExportRecoveryAdvisor.advice(for: context)
        #expect(advice.action == .retryExport)
    }

    @Test
    func advisorFallsBackToKeywordMatchingForGenericErrors() {
        let context = ExportFailureContext(
            code: nil,
            stage: .export,
            message: "permission denied",
            failedAssetNames: [],
            logPath: "/tmp/render.log",
            rawDescription: "Operation not permitted"
        )

        let advice = ExportRecoveryAdvisor.advice(for: context)
        #expect(advice.action == .reauthorizeAccess)
    }
}
