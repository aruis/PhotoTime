import AppKit
import Foundation

@MainActor
extension ExportViewModel {
    func performRecoveryAction() {
        guard let advice = recoveryAdvice else { return }
        if advice.action == .retryExport, isUITestScenario(named: "failure_then_success") {
            lastLogURL = URL(fileURLWithPath: "/tmp/phototime-ui-recovered.render.log")
            lastSuccessfulOutputURL = URL(fileURLWithPath: "/tmp/PhotoTime-UI-Recovered.mp4")
            recoveryAdvice = nil
            failureCardCopy = nil
            workflow.finishExportSuccess(
                message: "导出完成: PhotoTime-UI-Recovered.mp4\n日志: /tmp/phototime-ui-recovered.render.log"
            )
            return
        }

        switch advice.action {
        case .retryExport:
            retryLastExport()
        case .reselectAssets:
            chooseImages()
        case .reauthorizeAccess:
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(settingsURL)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        case .freeDiskSpace:
            openLatestOutputDirectory()
        case .adjustSettings:
            workflow.setIdleMessage("请调整导出参数后再重试。")
        case .inspectLog:
            openLatestLog()
        }
    }

    func applyUITestScenarioIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-scenario"), arguments.indices.contains(flagIndex + 1) else {
            return
        }

        let scenario = arguments[flagIndex + 1]
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
                message: "[E_EXPORT_PIPELINE] 测试失败\n建议动作: 重试上次导出\n建议: 测试场景\n日志: /tmp/phototime-ui-failure.render.log"
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
                message: "[E_EXPORT_PIPELINE] 测试失败\n建议动作: 重试上次导出\n建议: 测试场景\n日志: /tmp/phototime-ui-failure.render.log"
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
    }

    private func isUITestScenario(named expected: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-scenario"), arguments.indices.contains(flagIndex + 1) else {
            return false
        }
        return arguments[flagIndex + 1] == expected
    }
}
