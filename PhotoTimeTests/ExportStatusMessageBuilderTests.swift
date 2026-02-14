import Foundation
import Testing
@testable import PhotoTime

struct ExportStatusMessageBuilderTests {
    @Test
    func successMessageIncludesAudioLineWhenAttached() {
        let text = ExportStatusMessageBuilder.success(
            outputFilename: "PhotoTime-Output.mp4",
            logPath: "/tmp/render.log",
            audioAttached: true
        )

        #expect(text.contains("导出完成: PhotoTime-Output.mp4"))
        #expect(text.contains("音频: 已附加单轨背景音频"))
        #expect(text.contains("日志: /tmp/render.log"))
    }

    @Test
    func successMessageOmitsAudioLineWhenNotAttached() {
        let text = ExportStatusMessageBuilder.success(
            outputFilename: "PhotoTime-Output.mp4",
            logPath: "/tmp/render.log",
            audioAttached: false
        )

        #expect(text == "导出完成: PhotoTime-Output.mp4\n日志: /tmp/render.log")
    }

    @Test
    func failureMessageWithAssetsIncludesRemediation() {
        let text = ExportStatusMessageBuilder.failure(
            head: "[E_EXPORT_PIPELINE] 导出失败",
            logPath: "/tmp/render.log",
            adviceActionTitle: "重试上次导出",
            adviceMessage: "请先处理素材后重试。",
            failedAssetNames: ["a.jpg", "b.jpg"]
        )

        #expect(text.contains("问题素材: a.jpg、b.jpg"))
        #expect(text.contains("处理建议: 在素材列表中定位该文件，替换或移除后重试导出"))
        #expect(text.contains("建议动作: 重试上次导出"))
        #expect(text.contains("详细建议: 请先处理素材后重试。"))
        #expect(text.contains("日志: /tmp/render.log"))
    }

    @Test
    func failureMessageWithoutAssetsUsesCompactForm() {
        let text = ExportStatusMessageBuilder.failure(
            head: "[E_EXPORT_PIPELINE] 导出失败",
            logPath: "/tmp/render.log",
            adviceActionTitle: "重试上次导出",
            adviceMessage: "可先重试导出。",
            failedAssetNames: []
        )

        #expect(text == "[E_EXPORT_PIPELINE] 导出失败\n建议动作: 重试上次导出\n建议: 可先重试导出。\n日志: /tmp/render.log")
    }
}
