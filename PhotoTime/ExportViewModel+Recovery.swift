import AppKit
import Foundation

@MainActor
extension ExportViewModel {
    func performRecoveryAction() {
        guard let advice = recoveryAdvice else { return }
        if advice.action == .retryExport, handleUITestRecoveryShortcutIfNeeded() {
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
}
