import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ExportViewModel {
    func chooseImages() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageURLs = normalizedImageURLs(from: panel.urls)
        previewImage = nil
        previewSecond = 0
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        workflow.setIdleMessage("已选择 \(imageURLs.count) 张图片")

        // Generate first preview frame automatically to avoid blank preview area after import.
        if !imageURLs.isEmpty, isSettingsValid {
            generatePreview()
        }
    }

    func addImages() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK else { return }
        appendImages(panel.urls, source: "已新增")
    }

    func importDroppedItems(_ urls: [URL]) {
        guard !isBusy else { return }
        appendImages(urls, source: "已拖入")
    }

    func removeImage(_ url: URL) {
        guard !isBusy else { return }
        guard let index = imageURLs.firstIndex(of: url) else { return }

        imageURLs.remove(at: index)
        failedAssetNames.removeAll(where: { $0 == url.lastPathComponent })
        skippedAssetNamesFromPreflight.removeAll(where: { $0 == url.lastPathComponent })
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        pendingRequestFromPreflight = nil

        if imageURLs.isEmpty {
            previewImage = nil
            previewSecond = 0
            previewStatusMessage = "未生成预览"
            previewErrorMessage = nil
            workflow.setIdleMessage("素材已清空")
            return
        }

        previewImage = nil
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("已删除: \(url.lastPathComponent)")

        if isSettingsValid {
            generatePreview()
        }
    }

    func removeImages(_ urls: [URL]) {
        guard !isBusy else { return }
        let targets = Set(urls)
        guard !targets.isEmpty else { return }

        let remaining = imageURLs.filter { !targets.contains($0) }
        guard remaining.count != imageURLs.count else { return }

        imageURLs = remaining
        let removedNames = Set(urls.map(\.lastPathComponent))
        failedAssetNames.removeAll(where: { removedNames.contains($0) })
        skippedAssetNamesFromPreflight.removeAll(where: { removedNames.contains($0) })
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        pendingRequestFromPreflight = nil

        if imageURLs.isEmpty {
            previewImage = nil
            previewSecond = 0
            previewStatusMessage = "未生成预览"
            previewErrorMessage = nil
            workflow.setIdleMessage("素材已清空")
            return
        }

        previewImage = nil
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("已删除 \(removedNames.count) 张素材")

        if isSettingsValid {
            generatePreview()
        }
    }

    func reorderImage(from source: URL, to target: URL) {
        guard !isBusy else { return }
        guard source != target else { return }
        guard let sourceIndex = imageURLs.firstIndex(of: source),
              let targetIndex = imageURLs.firstIndex(of: target) else { return }

        var reordered = imageURLs
        let moving = reordered.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        reordered.insert(moving, at: insertIndex)
        imageURLs = reordered

        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        previewImage = nil
        previewStatusMessage = "素材顺序已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("已调整素材顺序")
    }


    func appendImages(_ urls: [URL], source: String) {
        let incoming = normalizedImageURLs(from: urls)
        guard !incoming.isEmpty else {
            workflow.setIdleMessage("未检测到可用图片")
            return
        }

        var existing = Set(imageURLs.map(\.standardizedFileURL))
        var appended: [URL] = []

        for url in incoming {
            let normalized = url.standardizedFileURL
            if existing.insert(normalized).inserted {
                appended.append(normalized)
            }
        }

        guard !appended.isEmpty else {
            workflow.setIdleMessage("未新增素材（已存在）")
            return
        }

        imageURLs.append(contentsOf: appended)
        preflightReport = nil
        ignoredPreflightIssueKeys = []
        preflightIssueFilter = .all
        skippedAssetNamesFromPreflight = []
        pendingRequestFromPreflight = nil
        previewImage = nil
        previewSecond = min(previewSecond, previewMaxSecond)
        previewStatusMessage = "素材已更新，请生成预览"
        previewErrorMessage = nil
        workflow.setIdleMessage("\(source) \(appended.count) 张，共 \(imageURLs.count) 张")

        if isSettingsValid {
            generatePreview()
        }
    }

    func normalizedImageURLs(from urls: [URL]) -> [URL] {
        var collected: [URL] = []
        var seen = Set<URL>()

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            collectImageURLs(from: url, into: &collected, seen: &seen)
        }

        return collected
    }

    func collectImageURLs(from url: URL, into result: inout [URL], seen: inout Set<URL>) {
        guard seen.insert(url).inserted else { return }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey])
        if values?.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for case let fileURL as URL in enumerator {
                let standardized = fileURL.standardizedFileURL
                let fileValues = try? standardized.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey])
                guard fileValues?.isRegularFile == true else { continue }
                guard isSupportedImageURL(standardized, contentType: fileValues?.contentType) else { continue }
                result.append(standardized)
            }
            return
        }

        guard values?.isRegularFile == true else { return }
        guard isSupportedImageURL(url, contentType: values?.contentType) else { return }
        result.append(url)
    }

    func isSupportedImageURL(_ url: URL, contentType: UTType?) -> Bool {
        if let contentType, contentType.conforms(to: .image) {
            return true
        }
        if let inferred = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return inferred.conforms(to: .image)
        }
        return false
    }

    var previewMaxSecond: Double {
        guard !imageURLs.isEmpty else { return 0 }
        let settings = config.renderSettings
        let timeline = TimelineEngine(
            itemCount: imageURLs.count,
            imageDuration: settings.imageDuration,
            transitionDuration: settings.effectiveTransitionDuration
        )
        return max(timeline.totalDuration - 0.001, 0)
    }
}
