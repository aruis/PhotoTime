import AppKit
import Foundation

@MainActor
extension ExportViewModel {
    func applyUITestScenarioIfNeeded() {
        #if DEBUG
        guard let scenario = currentUITestScenario() else { return }
        switch scenario {
        case "failure":
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-failure.render.log")
            failedAssetNames = ["broken-sample.jpg"]
            recoveryAdvice = RecoveryAdvice(action: .retryExport, message: "测试场景：可直接重试导出。")
            failureCardCopy = ExportStatusMessageBuilder.failureCardCopy(
                stage: .export,
                adviceActionTitle: RecoveryAction.retryExport.title,
                adviceMessage: "测试场景：可直接重试导出。",
                failedAssetNames: failedAssetNames
            )
            workflow.finishExportFailure(
                message: "导出失败，请查看下方详情。"
            )
        case "failure_then_success":
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-failure.render.log")
            failedAssetNames = ["broken-sample.jpg"]
            recoveryAdvice = RecoveryAdvice(action: .retryExport, message: "测试场景：修复后可重试。")
            failureCardCopy = ExportStatusMessageBuilder.failureCardCopy(
                stage: .export,
                adviceActionTitle: RecoveryAction.retryExport.title,
                adviceMessage: "测试场景：修复后可重试。",
                failedAssetNames: failedAssetNames
            )
            workflow.finishExportFailure(
                message: "导出失败，请查看下方详情。"
            )
        case "success":
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-success.render.log")
            lastSuccessfulOutputURL = URL(fileURLWithPath: "/tmp/PhotoTime-UI-Success.mp4")
            recoveryAdvice = nil
            failureCardCopy = nil
            workflow.finishExportSuccess(
                message: "导出完成: PhotoTime-UI-Success.mp4\n日志: /tmp/phototime-ui-success.render.log"
            )
        case "invalid":
            config.outputWidth = 100
            config.outputHeight = 100
            workflow.setIdleMessage("测试场景：参数无效")
        case "first_run_ready":
            imageURLs = [
                URL(fileURLWithPath: "/tmp/first-run-a.jpg"),
                URL(fileURLWithPath: "/tmp/first-run-b.jpg")
            ]
            outputURL = URL(fileURLWithPath: "/tmp/PhotoTime-FirstRun.mp4")
            previewImage = NSImage(size: CGSize(width: 320, height: 180))
            previewStatusMessage = "测试场景：预览已就绪"
            workflow.setIdleMessage("测试场景：可直接导出")
        default:
            break
        }
        #endif
    }

    func handleUITestRecoveryShortcutIfNeeded() -> Bool {
        #if DEBUG
        guard isUITestScenario(named: "failure_then_success") else { return false }
        lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-recovered.render.log")
        lastSuccessfulOutputURL = URL(fileURLWithPath: "/tmp/PhotoTime-UI-Recovered.mp4")
        recoveryAdvice = nil
        failureCardCopy = nil
        workflow.finishExportSuccess(
            message: "导出完成: PhotoTime-UI-Recovered.mp4\n日志: /tmp/phototime-ui-recovered.render.log"
        )
        return true
        #else
        return false
        #endif
    }

    func simulateExportFailure() {
        #if DEBUG
        let debugDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTime-Debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        let logURL = debugDir.appendingPathComponent("phototime-debug-failure.render.log")
        lastLogURL = logURL
        let debugLog = """
        [debug] simulated export failure
        reason: manual trigger for acceptance
        next_action: retry export
        """
        try? debugLog.write(to: logURL, atomically: true, encoding: .utf8)
        failedAssetNames = ["simulated-broken.jpg"]
        recoveryAdvice = RecoveryAdvice(action: .retryExport, message: "这是手动模拟的失败，用于验收测试。可点击重试。")
        failureCardCopy = ExportStatusMessageBuilder.failureCardCopy(
            stage: .export,
            adviceActionTitle: RecoveryAction.retryExport.title,
            adviceMessage: "这是手动模拟的失败，用于验收测试。可点击重试。",
            failedAssetNames: failedAssetNames
        )
        workflow.finishExportFailure(
            message: "导出失败，请查看下方详情。"
        )
        #endif
    }

    private func isUITestScenario(named expected: String) -> Bool {
        #if DEBUG
        return currentUITestScenario() == expected
        #else
        return false
        #endif
    }

    private func currentUITestScenario() -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-scenario"), arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
        #else
        return nil
        #endif
    }
}
