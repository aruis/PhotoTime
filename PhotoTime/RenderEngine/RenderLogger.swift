import Foundation

actor RenderLogger {
    private let fileURL: URL
    private let formatter: ISO8601DateFormatter

    init(fileURL: URL) {
        self.fileURL = fileURL
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let header = "PhotoTime Export Log\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

}
