@preconcurrency import AVFoundation
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
    static func muxTracks(
        videoURL: URL,
        outputURL: URL,
        backgroundTrack: AudioTrackSettings?,
        shutterTrack: ShutterSoundTrackSettings?,
        shutterTimes: [TimeInterval]
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)

        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first
        guard let videoTrack else {
            throw AudioMuxerError.missingVideoTrack
        }

        let videoDuration = try await videoAsset.load(.duration)

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
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        var mixParameters: [AVMutableAudioMixInputParameters] = []

        if let backgroundTrack {
            guard
                let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                throw AudioMuxerError.cannotCreateExportSession
            }

            let audioAsset = AVURLAsset(url: backgroundTrack.sourceURL)
            let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
            guard let audioTrack else {
                throw AudioMuxerError.missingAudioTrack
            }

            let audioDuration = try await audioAsset.load(.duration)
            guard audioDuration > .zero else {
                throw AudioMuxerError.missingAudioTrack
            }

            if backgroundTrack.loopEnabled {
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

            let backgroundMix = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            backgroundMix.setVolume(Float(backgroundTrack.volume), at: .zero)
            mixParameters.append(backgroundMix)
        }

        if let shutterTrack, !shutterTimes.isEmpty {
            let shutterAsset = AVURLAsset(url: shutterTrack.sourceURL)
            let shutterSourceTrack = try await shutterAsset.loadTracks(withMediaType: .audio).first
            guard let shutterSourceTrack else {
                throw AudioMuxerError.missingAudioTrack
            }

            let shutterDuration = try await shutterAsset.load(.duration)
            guard shutterDuration > .zero else {
                throw AudioMuxerError.missingAudioTrack
            }

            guard
                let shutterCompositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                throw AudioMuxerError.cannotCreateExportSession
            }

            for shutterTime in shutterTimes {
                let atTime = CMTime(seconds: shutterTime, preferredTimescale: 600)
                guard atTime < videoDuration else { continue }
                let remaining = videoDuration - atTime
                let segmentDuration = CMTimeMinimum(shutterDuration, remaining)
                try shutterCompositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: shutterSourceTrack,
                    at: atTime
                )
            }

            let shutterMix = AVMutableAudioMixInputParameters(track: shutterCompositionTrack)
            shutterMix.setVolume(Float(shutterTrack.volume), at: .zero)
            mixParameters.append(shutterMix)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

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
        let exporterBox = UncheckedSendableBox(value: exporter)
        nonisolated(unsafe) let unsafeExporter = exporter

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exporterBox.value.exportAsynchronously {
                    switch exporterBox.value.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(
                            throwing: AudioMuxerError.exportFailed(exporterBox.value.error?.localizedDescription ?? "unknown")
                        )
                    case .cancelled:
                        continuation.resume(throwing: AudioMuxerError.cancelled)
                    default:
                        continuation.resume(
                            throwing: AudioMuxerError.exportFailed("unexpected status: \(exporterBox.value.status.rawValue)")
                        )
                    }
                }
            }
        } onCancel: {
            unsafeExporter.cancelExport()
        }

    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}
