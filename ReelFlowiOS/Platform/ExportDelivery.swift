import Foundation
import Photos

protocol ExportDelivery {
    func saveVideoToPhotoLibrary(at url: URL) async throws
}

enum ExportDeliveryError: LocalizedError {
    case permissionDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有照片写入权限，请允许保存到相册。"
        case .saveFailed(let message):
            return "保存到相册失败：\(message)"
        }
    }
}

struct PhotoLibraryExportDelivery: ExportDelivery {
    func saveVideoToPhotoLibrary(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportDeliveryError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: ExportDeliveryError.saveFailed(error.localizedDescription))
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportDeliveryError.saveFailed("unknown"))
                }
            }
        }
    }
}
