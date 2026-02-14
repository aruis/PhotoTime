import Foundation
import UniformTypeIdentifiers

enum AudioTrackValidation {
    static func validate(url: URL) -> String? {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return "音频文件不存在或已被移动"
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return "音频文件不可读，请检查权限"
        }
        if
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize,
            fileSize <= 0
        {
            return "音频文件大小为 0，无法使用"
        }

        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]), let type = values.contentType {
            guard type.conforms(to: .audio) else {
                return "文件格式不是受支持的音频类型"
            }
            return nil
        }

        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            guard type.conforms(to: .audio) else {
                return "文件格式不是受支持的音频类型"
            }
            return nil
        }

        return "无法识别音频格式，请选择常见音频文件"
    }
}
