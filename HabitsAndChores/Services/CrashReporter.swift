import Foundation
import Darwin
import OSLog

/// A lightweight, dependency-free **local** crash logger: it captures uncaught
/// exceptions and fatal signals to a file, and logs them on the next launch via
/// `os.Logger`. This is not a crash-reporting *service* (no symbolication or
/// upload) — it just makes crashes visible in device logs for diagnosis.
enum CrashReporter {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("last_crash.log")
    }

    /// Destination path as a C string, computed once so the signal handler (which
    /// must avoid allocation) can use it safely.
    private static var pathCString: [CChar] = []

    /// Installs the handlers. Call once, early at launch.
    static func install() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        pathCString = Array(fileURL.path.utf8CString)

        NSSetUncaughtExceptionHandler { exception in
            let text = "EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n")
            try? text.data(using: .utf8)?.write(to: CrashReporter.fileURL)
        }
        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE, SIGTRAP] {
            signal(sig, CrashReporter.signalHandler)
        }
    }

    /// If the previous run left a crash record, log it and clear it. Call at launch.
    static func reportPreviousCrashIfNeeded() {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        Logger.app.error("Previous run terminated abnormally:\n\(text, privacy: .public)")
        try? FileManager.default.removeItem(at: url)
    }

    // Async-signal-safe: only `open`/`backtrace`/`backtrace_symbols_fd`/`close` plus a
    // stack-allocated buffer — no heap allocation or Swift runtime calls.
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        pathCString.withUnsafeBufferPointer { buffer in
            guard let path = buffer.baseAddress else { return }
            let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            guard fd >= 0 else { return }
            withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: 64) { frames in
                let count = backtrace(frames.baseAddress, 64)
                backtrace_symbols_fd(frames.baseAddress, count, fd)
            }
            close(fd)
        }
        signal(sig, SIG_DFL)
        raise(sig)
    }
}
