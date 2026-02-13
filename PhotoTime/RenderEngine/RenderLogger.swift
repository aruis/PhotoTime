import Foundation

actor RenderLogger {
    private let fileURL: URL
    private let formatter: ISO8601DateFormatter
    private let runID: String?

    init(fileURL: URL, runID: String? = nil) {
        self.fileURL = fileURL
        self.runID = runID
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let header = "PhotoTime Export Log\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    nonisolated static func resolvedLogURL(for outputURL: URL) -> URL {
        let preferred = outputURL
            .deletingPathExtension()
            .appendingPathExtension("render.log")
        if canWrite(to: preferred) {
            return preferred
        }
        return fallbackLogURL(for: outputURL)
    }

    nonisolated static func fallbackLogURL(for outputURL: URL) -> URL {
        let base = (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        )
        let dir = base.appendingPathComponent("PhotoTime/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = outputURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(name).render.log")
    }

    nonisolated private static func canWrite(to fileURL: URL) -> Bool {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return false
        }

        if fm.fileExists(atPath: fileURL.path) {
            return fm.isWritableFile(atPath: fileURL.path)
        }

        guard fm.createFile(atPath: fileURL.path, contents: Data(), attributes: nil) else {
            return false
        }
        try? fm.removeItem(at: fileURL)
        return true
    }

    func log(_ message: String) {
        let runPrefix = runID.map { "[run:\($0)] " } ?? ""
        let line = "[\(formatter.string(from: Date()))] \(runPrefix)\(message)\n"

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

}
