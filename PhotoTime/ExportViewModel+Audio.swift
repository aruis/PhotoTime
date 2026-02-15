import AppKit
import AVFoundation
import Foundation

@MainActor
extension ExportViewModel {
    func chooseAudioTrack() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyAudioTrack(url: url, sourceDescription: "已选择音频")
    }

    @discardableResult
    func importDroppedAudioTrack(_ urls: [URL]) -> Bool {
        guard !isBusy else { return false }

        for url in urls {
            if AudioTrackValidation.validate(url: url) == nil {
                applyAudioTrack(url: url, sourceDescription: "已拖入音频")
                return true
            }
        }

        let message = urls.first.flatMap { AudioTrackValidation.validate(url: $0) } ?? "未检测到可用音频文件"
        audioStatusMessage = message
        config.audioEnabled = false
        config.audioFilePath = ""
        refreshSelectedAudioDuration(force: true)
        workflow.setIdleMessage("音频导入失败: \(message)")
        return false
    }

    func clearAudioTrack() {
        guard !isBusy else { return }
        stopAudioPreview()
        let previous = selectedAudioFilename
        config.audioEnabled = false
        config.audioFilePath = ""
        config.audioVolume = 1
        audioStatusMessage = nil
        refreshSelectedAudioDuration(force: true)
        if let previous {
            workflow.setIdleMessage("已清除音频: \(previous)")
        } else {
            workflow.setIdleMessage("已清除音频")
        }
    }

    func applyAudioTrack(url: URL, sourceDescription: String) {
        stopAudioPreview()
        if let message = AudioTrackValidation.validate(url: url) {
            audioStatusMessage = message
            config.audioEnabled = false
            config.audioFilePath = ""
            workflow.setIdleMessage("音频导入失败: \(message)")
            return
        }

        config.audioEnabled = true
        config.audioFilePath = url.path
        if config.audioVolume <= 0 {
            config.audioVolume = 1
        }
        audioStatusMessage = "音频已就绪：\(url.lastPathComponent)。导出时将附加单轨背景音频。"
        refreshSelectedAudioDuration(force: true)
        workflow.setIdleMessage("\(sourceDescription): \(url.lastPathComponent)")
    }

    @discardableResult
    func startAudioPreview() -> Bool {
        guard config.audioEnabled else {
            audioStatusMessage = "请先启用背景音频。"
            return false
        }

        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            audioStatusMessage = "请先选择音频文件。"
            return false
        }

        let url = URL(fileURLWithPath: path)
        if let message = AudioTrackValidation.validate(url: url) {
            audioStatusMessage = message
            return false
        }

        do {
            stopAudioPreview()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(config.audioVolume)
            player.numberOfLoops = config.audioLoopEnabled ? -1 : 0
            player.prepareToPlay()
            let maxStart = max(0, player.duration - 0.01)
            player.currentTime = min(max(0, previewSecond), maxStart)
            guard player.play() else {
                audioStatusMessage = "音频预览播放失败。"
                return false
            }
            previewAudioPlayer = player
            isAudioPreviewPlaying = true
            workflow.setIdleMessage("音频预览播放中")
            return true
        } catch {
            audioStatusMessage = "音频预览失败：\(error.localizedDescription)"
            return false
        }
    }

    func toggleAudioPreview() {
        if isAudioPreviewPlaying {
            pauseAudioPreview()
        } else {
            _ = startAudioPreview()
        }
    }

    func pauseAudioPreview() {
        guard let player = previewAudioPlayer else { return }
        player.pause()
        previewSecond = player.currentTime
        isAudioPreviewPlaying = false
        workflow.setIdleMessage("音频预览已暂停")
    }

    func stopAudioPreview() {
        guard let player = previewAudioPlayer else {
            isAudioPreviewPlaying = false
            return
        }
        player.stop()
        previewAudioPlayer = nil
        isAudioPreviewPlaying = false
    }

    func syncAudioPreviewPosition() {
        guard let player = previewAudioPlayer, isAudioPreviewPlaying else { return }
        let maxStart = max(0, player.duration - 0.01)
        player.currentTime = min(max(0, previewSecond), maxStart)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === previewAudioPlayer else { return }
        previewAudioPlayer = nil
        isAudioPreviewPlaying = false
    }

    var audioDurationLookupKey: String {
        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(config.audioEnabled ? 1 : 0)|\(path)"
    }

    func refreshSelectedAudioDuration(force: Bool = false) {
        let lookupKey = audioDurationLookupKey
        if !force, lookupKey == lastAudioDurationLookupKey {
            return
        }
        lastAudioDurationLookupKey = lookupKey

        audioDurationTask?.cancel()
        selectedAudioDuration = nil

        guard config.audioEnabled else { return }
        let path = config.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)

        audioDurationTask = Task { [weak self] in
            let duration = await Self.loadAudioDuration(from: url)
            guard let self, !Task.isCancelled else { return }
            guard self.audioDurationLookupKey == lookupKey else { return }
            self.selectedAudioDuration = duration
        }
    }

    static func loadAudioDuration(from url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }
}
