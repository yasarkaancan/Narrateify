import Foundation

/// Shared helpers for the local TTS servers (Kokoro / Chatterbox): on-disk size
/// accounting and orphan-process cleanup.
enum LocalServerSupport {

    /// Total allocated size on disk of everything under `url`, in bytes.
    static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [],
                                             errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Human-readable byte size, e.g. "2.4 GB".
    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: max(0, bytes))
    }

    /// Best-effort kill of any process still listening on a TCP port — orphans
    /// left by a previous run that didn't shut down cleanly. Synchronous but
    /// quick; call off the main thread if you care about the few-ms cost.
    static func killProcesses(onPort port: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "lsof -ti tcp:\(port) | xargs kill -9 2>/dev/null || true"]
        try? p.run()
        p.waitUntilExit()
    }
}
