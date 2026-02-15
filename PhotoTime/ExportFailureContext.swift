import Foundation

enum ExportFailureStage: String, Sendable {
    case preview
    case export
    case unknown
}

struct ExportFailureContext: Sendable {
    let code: String?
    let stage: ExportFailureStage
    let message: String
    let failedAssetNames: [String]
    let logPath: String
    let rawDescription: String

    var displayHead: String {
        guard let code else { return message }
        return "[\(code)] \(message)"
    }

    static func from(
        error: Error,
        failedAssetNames: [String],
        logURL: URL? = nil,
        stage: ExportFailureStage = .unknown
    ) -> ExportFailureContext {
        if let renderError = error as? RenderEngineError {
            return ExportFailureContext(
                code: renderError.code,
                stage: stage,
                message: renderError.localizedDescription,
                failedAssetNames: failedAssetNames,
                logPath: logURL?.path ?? "",
                rawDescription: renderError.localizedDescription
            )
        }

        return ExportFailureContext(
            code: nil,
            stage: stage,
            message: error.localizedDescription,
            failedAssetNames: failedAssetNames,
            logPath: logURL?.path ?? "",
            rawDescription: error.localizedDescription
        )
    }
}
