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
