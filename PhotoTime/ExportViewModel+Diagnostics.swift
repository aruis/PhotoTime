import AppKit
import Foundation

@MainActor
extension ExportViewModel {
    func exportDiagnosticsBundle() {
        do {
            let input = DiagnosticsBundleInput(
                destinationRoot: diagnosticsBundleRootURL(),
                statsFileURL: exportFailureStatsURL(),
                logsDirectoryURL: logsDirectoryURL(),
                latestLogURL: lastLogURL,
                configSnapshotLines: diagnosticsSnapshotLines()
            )
            let bundleURL = try DiagnosticsBundleBuilder.createBundle(input: input)
            workflow.setIdleMessage("排障包已生成: \(bundleURL.path)")
            NSWorkspace.shared.open(bundleURL)
        } catch {
            workflow.setIdleMessage("排障包生成失败: \(error.localizedDescription)")
        }
    }

    private func diagnosticsBundleRootURL() -> URL {
        let base = (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        )
        return base
            .appendingPathComponent("PhotoTime/Diagnostics/Bundles", isDirectory: true)
    }

    private func exportFailureStatsURL() -> URL {
        let base = (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        )
        return base
            .appendingPathComponent("PhotoTime/Diagnostics/export-failure-stats.json")
    }

    private func logsDirectoryURL() -> URL {
        let base = (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        )
        return base
            .appendingPathComponent("PhotoTime/Logs", isDirectory: true)
    }

    private func diagnosticsSnapshotLines() -> [String] {
        let settings = config.renderSettings
        var lines: [String] = [
            "workflow_state=\(workflow.state.rawValue)",
            "workflow_progress=\(String(format: "%.3f", workflow.progress))",
            "image_count=\(imageURLs.count)",
            "output_path=\(outputURL?.path ?? "(none)")",
            String(
                format: "render output=%dx%d fps=%d imageDuration=%.2f transition=%.2f(%@) kenBurns=%@",
                Int(settings.outputSize.width),
                Int(settings.outputSize.height),
                Int(settings.fps),
                settings.imageDuration,
                settings.transitionDuration,
                settings.transitionEnabled ? settings.transitionStyle.rawValue : "off",
                settings.enableKenBurns ? "on" : "off"
            ),
            String(
                format: "layout h=%.1f top=%.1f bottom=%.1f inner=%.1f",
                settings.layout.horizontalMargin,
                settings.layout.topMargin,
                settings.layout.bottomMargin,
                settings.layout.innerPadding
            ),
            String(
                format: "plate enabled=%@ height=%.1f baseline=%.1f font=%.1f",
                settings.plate.enabled ? "on" : "off",
                settings.plate.height,
                settings.plate.baselineOffset,
                settings.plate.fontSize
            )
        ]
        if let audioTrack = settings.audioTrack {
            lines.append(
                String(
                    format: "audio enabled path=%@ volume=%.2f loop=%@",
                    audioTrack.sourceURL.path,
                    audioTrack.volume,
                    audioTrack.loopEnabled ? "on" : "off"
                )
            )
        } else {
            lines.append("audio disabled")
        }
        return lines
    }
}
