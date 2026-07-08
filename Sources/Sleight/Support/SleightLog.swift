import Foundation

/// Appends diagnostic lines to ~/Library/Logs/Sleight.log so problems in the
/// permission-sensitive paths (event tap, hotkeys) can be pinpointed exactly.
enum SleightLog {
    private static let queue = DispatchQueue(label: "com.kamenlevi.sleight.log", qos: .utility)
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Sleight.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        queue.async {
            let line = "\(stamp.string(from: Date())) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.data(using: .utf8)!.write(to: url)
            }
        }
    }
}
