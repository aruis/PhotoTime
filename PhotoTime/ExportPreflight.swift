import Foundation
import ImageIO

enum PreflightSeverity: String, Codable, Sendable {
    case mustFix
    case shouldReview
}

struct PreflightIssue: Codable, Sendable {
    let index: Int
    let fileName: String
    let message: String
    let severity: PreflightSeverity

    var isBlocking: Bool {
        severity == .mustFix
    }
}

struct PreflightReport: Codable, Sendable {
    let scannedCount: Int
    let issues: [PreflightIssue]

    var blockingIssues: [PreflightIssue] {
        issues.filter(\.isBlocking)
    }

    var reviewIssues: [PreflightIssue] {
        issues.filter { $0.severity == .shouldReview }
    }

    var hasBlockingIssues: Bool {
        !blockingIssues.isEmpty
    }

    var blockingIndexes: Set<Int> {
        Set(blockingIssues.map(\.index))
    }
}

enum ExportPreflightScanner {
    private static let reviewFilenameLengthThreshold = 96
    private static let reviewExtremeAspectRatioThreshold = 3.0
    private static let suspiciousColorModels: Set<String> = ["CMYK", "Lab", "Indexed", "Monochrome", "Unknown"]

    nonisolated static func scan(imageURLs: [URL]) -> PreflightReport {
        var issues: [PreflightIssue] = []
        issues.reserveCapacity(imageURLs.count * 2)

        for (index, url) in imageURLs.enumerated() {
            let fileName = url.lastPathComponent
            if fileName.count > reviewFilenameLengthThreshold {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "文件名较长，部分系统导出时可能遇到路径/兼容问题",
                        severity: .shouldReview
                    )
                )
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "文件不存在或已被移动",
                        severity: .mustFix
                    )
                )
                continue
            }

            guard FileManager.default.isReadableFile(atPath: url.path) else {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "文件不可读，请检查权限",
                        severity: .mustFix
                    )
                )
                continue
            }

            if
                let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize,
                fileSize <= 0
            {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "文件大小为 0，无法导出",
                        severity: .mustFix
                    )
                )
                continue
            }

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "图片源无法读取，可能已损坏",
                        severity: .mustFix
                    )
                )
                continue
            }

            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "无法读取图片属性",
                        severity: .mustFix
                    )
                )
                continue
            }

            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            if width <= 0 || height <= 0 {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "像素尺寸异常（宽高为 0）",
                        severity: .mustFix
                    )
                )
                continue
            }

            if min(width, height) < 320 {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "分辨率较低，导出画质可能受影响",
                        severity: .shouldReview
                    )
                )
            }

            let aspectRatio = Double(max(width, height)) / Double(min(width, height))
            if aspectRatio >= reviewExtremeAspectRatioThreshold {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: String(format: "长宽比极端(%.2f:1)，导出构图可能异常", aspectRatio),
                        severity: .shouldReview
                    )
                )
            }

            if
                let colorModel = properties[kCGImagePropertyColorModel] as? String,
                suspiciousColorModels.contains(colorModel)
            {
                issues.append(
                    PreflightIssue(
                        index: index,
                        fileName: fileName,
                        message: "色彩模型为 \(colorModel)，建议先转换为 RGB 以降低导出风险",
                        severity: .shouldReview
                    )
                )
            }
        }

        return PreflightReport(scannedCount: imageURLs.count, issues: issues)
    }
}
