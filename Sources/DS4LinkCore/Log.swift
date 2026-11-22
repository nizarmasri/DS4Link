import Foundation

/// Append-only log at ~/Library/Logs/DS4Link/ds4link.log. Every Bluetooth event goes here, so a
/// pairing that fails on some other Mac can be diagnosed from the file afterwards.
public enum Log {
    public static var echoToStderr = false

    public static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DS4Link", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ds4link.log")
    }()

    private static let queue = DispatchQueue(label: "com.nizar.ds4link.log")
    private static let maxBytes: UInt64 = 512 * 1024

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static func info(_ message: String) { write("INFO", message) }
    public static func warn(_ message: String) { write("WARN", message) }
    public static func error(_ message: String) { write("ERROR", message) }

    /// Blocks until everything logged so far is on disk. Used before the CLI exits.
    public static func flush() { queue.sync {} }

    private static func write(_ level: String, _ message: String) {
        let now = Date()
        queue.async {
            let line = "\(stamp.string(from: now)) [\(level)] \(message)\n"
            if echoToStderr { FileHandle.standardError.write(Data(line.utf8)) }
            rotateIfNeeded()
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private static func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes?[.size] as? UInt64, size > maxBytes else { return }
        let old = fileURL.deletingLastPathComponent().appendingPathComponent("ds4link.old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
