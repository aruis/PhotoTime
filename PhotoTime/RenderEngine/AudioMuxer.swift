import AVFoundation
import Foundation

enum AudioMuxerError: LocalizedError {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateExportSession
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "无法读取视频轨道"
        case .missingAudioTrack:
            return "无法读取音频轨道"
        case .cannotCreateExportSession:
            return "无法创建音视频混流会话"
        case .exportFailed(let message):
            return "音频混流失败: \(message)"
        case .cancelled:
            return "音频混流已取消"
        }
    }
}

enum AudioMuxer {
    static func muxSingleTrack(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        volume: Float,
        loopEnabled: Bool
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first
        guard let videoTrack else {
            throw AudioMuxerError.missingVideoTrack
        }

        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        guard let audioTrack else {
            throw AudioMuxerError.missingAudioTrack
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard audioDuration > .zero else {
            throw AudioMuxerError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AudioMuxerError.cannotCreateExportSession
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

        guard
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AudioMuxerError.cannotCreateExportSession
        }

        if loopEnabled {
            var cursor = CMTime.zero
            while cursor < videoDuration {
                let remaining = videoDuration - cursor
                let segmentDuration = CMTimeMinimum(audioDuration, remaining)
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: audioTrack,
                    at: cursor
                )
                cursor = cursor + segmentDuration
            }
        } else {
            let insertDuration = CMTimeMinimum(videoDuration, audioDuration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: audioTrack,
                at: .zero
            )
        }

        let mixParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        mixParameters.setVolume(max(0, min(volume, 1)), at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [mixParameters]

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard
            let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            )
        else {
            throw AudioMuxerError.cannotCreateExportSession
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = false
        exporter.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        exporter.audioMix = audioMix

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(
                            throwing: AudioMuxerError.exportFailed(exporter.error?.localizedDescription ?? "unknown")
                        )
                    case .cancelled:
                        continuation.resume(throwing: AudioMuxerError.cancelled)
                    default:
                        continuation.resume(
                            throwing: AudioMuxerError.exportFailed("unexpected status: \(exporter.status.rawValue)")
                        )
                    }
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }

    }
}
