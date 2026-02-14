import Foundation

enum ExportStatusMessageBuilder {
    static func success(outputFilename: String, logPath: String, audioAttached: Bool) -> String {
        if audioAttached {
            return "导出完成: \(outputFilename)\n音频: 已附加单轨背景音频\n日志: \(logPath)"
        }
        return "导出完成: \(outputFilename)\n日志: \(logPath)"
    }

    static func failure(
        head: String,
        logPath: String,
        adviceActionTitle: String,
        adviceMessage: String,
        failedAssetNames: [String]
    ) -> String {
        if failedAssetNames.isEmpty {
            return "\(head)\n建议动作: \(adviceActionTitle)\n建议: \(adviceMessage)\n日志: \(logPath)"
        }

        let list = failedAssetNames.joined(separator: "、")
        return """
        \(head)
        问题素材: \(list)
        处理建议: 在素材列表中定位该文件，替换或移除后重试导出
        建议动作: \(adviceActionTitle)
        详细建议: \(adviceMessage)
        日志: \(logPath)
        """
    }
}
