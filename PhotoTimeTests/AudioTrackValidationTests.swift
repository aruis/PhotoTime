import Foundation
import Testing
@testable import PhotoTime

struct AudioTrackValidationTests {
    @Test
    func validatorRejectsMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/not-exists-\(UUID().uuidString).m4a")
        let message = AudioTrackValidation.validate(url: url)
        #expect(message?.contains("不存在") == true)
    }

    @Test
    func validatorRejectsNonAudioType() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeAudioValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let textURL = tempDir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: textURL, options: .atomic)

        let message = AudioTrackValidation.validate(url: textURL)
        #expect(message?.contains("音频") == true)
    }

    @Test
    func validatorAcceptsKnownAudioExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTimeAudioValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("bgm.m4a")
        try Data([1, 2, 3]).write(to: audioURL, options: .atomic)

        let message = AudioTrackValidation.validate(url: audioURL)
        #expect(message == nil)
    }
}
