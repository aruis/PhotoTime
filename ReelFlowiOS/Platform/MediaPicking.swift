import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

protocol MediaPicking {
    func materializeImageFiles(from items: [PhotosPickerItem]) async throws -> [URL]
}

enum MediaPickingError: LocalizedError {
    case emptySelection
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "未选择可用照片。"
        case .loadFailed:
            return "照片导入失败，请重试。"
        }
    }
}

struct PhotosPickerMediaPicker: MediaPicking {
    func materializeImageFiles(from items: [PhotosPickerItem]) async throws -> [URL] {
        guard !items.isEmpty else {
            throw MediaPickingError.emptySelection
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReelFlowiOS-Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var urls: [URL] = []
        urls.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                continue
            }
            let contentType = item.supportedContentTypes.first ?? .jpeg
            let ext = contentType.preferredFilenameExtension ?? "jpg"
            let url = root.appendingPathComponent("asset-\(UUID().uuidString)-\(index).\(ext)")
            try data.write(to: url, options: [.atomic])
            urls.append(url)
        }

        guard !urls.isEmpty else {
            throw MediaPickingError.loadFailed
        }
        return urls
    }
}
