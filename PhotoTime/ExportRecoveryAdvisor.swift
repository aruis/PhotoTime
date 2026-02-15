import Foundation

enum RecoveryAction: String, Sendable {
    case retryExport
    case reselectAssets
    case reauthorizeAccess
    case freeDiskSpace
    case adjustSettings
    case inspectLog

    var title: String {
        switch self {
        case .retryExport:
            return "重试上次导出"
        case .reselectAssets:
            return "重新选择素材"
        case .reauthorizeAccess:
            return "重新授权访问"
        case .freeDiskSpace:
            return "释放磁盘空间"
        case .adjustSettings:
            return "调整参数后重试"
        case .inspectLog:
            return "检查日志"
        }
    }
}

struct RecoveryAdvice: Sendable {
    let action: RecoveryAction
    let message: String
}

enum ExportRecoveryAdvisor {
    static func advice(for context: ExportFailureContext) -> RecoveryAdvice {
        switch context.code {
        case "E_INPUT_EMPTY":
            return RecoveryAdvice(action: .reselectAssets, message: "请先选择图片，再开始导出。")
        case "E_EXPORT_CANCELLED":
            return RecoveryAdvice(action: .retryExport, message: "导出已取消，可再次点击导出继续。")
        case "E_IMAGE_LOAD":
            if !context.failedAssetNames.isEmpty {
                return RecoveryAdvice(action: .reselectAssets, message: "请移除或替换失败素材后重试。")
            }
            return RecoveryAdvice(action: .reselectAssets, message: "请检查素材是否可读、格式是否正常，再重试。")
        case "E_EXPORT_PIPELINE":
            return RecoveryAdvice(action: .retryExport, message: "可先重试导出；若仍失败，请检查日志排查。")
        case "E_PREVIEW_PIPELINE":
            return RecoveryAdvice(action: .adjustSettings, message: "可先调整参数或重新选择素材后再试。")
        default:
            break
        }

        let lowercasedDescription = context.rawDescription.lowercased()

        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { lowercasedDescription.contains($0) }
        }

        if containsAny(["operation not permitted", "permission denied", "sandbox", "not authorized", "don't have permission"]) {
            return RecoveryAdvice(
                action: .reauthorizeAccess,
                message: "请确认已授予 PhotoTime 访问素材和导出目录权限，然后重试导出。"
            )
        }

        if containsAny(["no such file", "not found", "doesn’t exist", "does not exist"]) {
            return RecoveryAdvice(
                action: .reselectAssets,
                message: "有素材可能已被移动或删除，请重新选择缺失素材后重试。"
            )
        }

        if containsAny(["no space left", "disk full", "volume is full"]) {
            return RecoveryAdvice(
                action: .freeDiskSpace,
                message: "磁盘空间不足，请释放空间后重试。"
            )
        }

        return RecoveryAdvice(
            action: .retryExport,
            message: "可先重试导出；若仍失败，请检查日志排查。"
        )
    }

    static func advice(for error: Error, failedAssetNames: [String]) -> RecoveryAdvice {
        let context = ExportFailureContext.from(
            error: error,
            failedAssetNames: failedAssetNames,
            stage: .unknown
        )
        return advice(for: context)
    }
}
