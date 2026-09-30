import Darwin
import Foundation

/// Durable on-device log sink. Writes are serialized and `synchronize`d so that
/// a subsequent crash is less likely to lose the last lines (unlike OSLog only).
final class FileLogStore: @unchecked Sendable {
    static let shared = FileLogStore()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case notice = "NOTICE"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"
    }

    private let queue = DispatchQueue(label: "com.plexios.filelog", qos: .utility)
    private var fileHandle: FileHandle?
    private let maxFileBytes: UInt64 = 2_500_000
    private let maxRotatedFiles = 4
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Logs", isDirectory: true)
    }

    var currentLogURL: URL {
        directoryURL.appendingPathComponent("plexios.log", isDirectory: false)
    }

    private init() {
        queue.sync {
            openHandleIfNeeded()
            writeLineUnlocked(
                "\(iso.string(from: Date())) [INFO] [app] ——— session start pid=\(ProcessInfo.processInfo.processIdentifier) ———\n"
            )
        }
        Self.installCrashHooks()
    }

    // MARK: - Public API

    func append(level: Level, category: String, message: String) {
        let redacted = LogRedaction.redact(message)
        let line = "\(iso.string(from: Date())) [\(level.rawValue)] [\(category)] \(redacted)\n"
        queue.async { [weak self] in
            self?.writeLineUnlocked(line)
        }
    }

    /// Blocking write + fsync — use from exception hooks / critical paths.
    func appendAndFlush(level: Level, category: String, message: String) {
        let redacted = LogRedaction.redact(message)
        let line = "\(iso.string(from: Date())) [\(level.rawValue)] [\(category)] \(redacted)\n"
        queue.sync { [weak self] in
            self?.writeLineUnlocked(line)
            self?.fileHandle?.synchronizeFile()
        }
    }

    func flush() {
        queue.sync { [weak self] in
            self?.fileHandle?.synchronizeFile()
        }
    }

    /// Newest content first for UI (tail of current + rotated if needed).
    func readRecentText(maxBytes: Int = 400_000) -> String {
        queue.sync {
            closeHandleUnlocked()
            defer { openHandleIfNeeded() }
            let urls = logFileURLsNewestFirst()
            var chunks: [Data] = []
            var remaining = maxBytes
            for url in urls {
                guard remaining > 0 else { break }
                guard let data = try? Data(contentsOf: url) else { continue }
                if data.count <= remaining {
                    chunks.append(data)
                    remaining -= data.count
                } else {
                    chunks.append(data.suffix(remaining))
                    remaining = 0
                }
            }
            let combined = chunks.reversed().reduce(Data()) { $0 + $1 }
            return String(data: combined, encoding: .utf8) ?? ""
        }
    }

    /// Single file suitable for share sheet (merges rotations, oldest → newest).
    func exportMergedLogURL() throws -> URL {
        try queue.sync {
            closeHandleUnlocked()
            defer { openHandleIfNeeded() }
            let out = directoryURL.appendingPathComponent(
                "plexios-export-\(Int(Date().timeIntervalSince1970)).log"
            )
            if FileManager.default.fileExists(atPath: out.path) {
                try FileManager.default.removeItem(at: out)
            }
            FileManager.default.createFile(atPath: out.path, contents: nil)
            let handle = try FileHandle(forWritingTo: out)
            defer { try? handle.close() }
            for url in logFileURLsOldestFirst() {
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                try handle.write(contentsOf: data)
            }
            try handle.synchronize()
            return out
        }
    }

    func clearAll() {
        queue.sync {
            closeHandleUnlocked()
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
                for url in files where url.lastPathComponent.hasPrefix("plexios") {
                    try? fm.removeItem(at: url)
                }
            }
            openHandleIfNeeded()
            writeLineUnlocked(
                "\(iso.string(from: Date())) [INFO] [app] ——— logs cleared ———\n"
            )
        }
    }

    func approximateSizeBytes() -> UInt64 {
        queue.sync {
            closeHandleUnlocked()
            defer { openHandleIfNeeded() }
            var total: UInt64 = 0
            for url in logFileURLsOldestFirst() {
                if let n = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber {
                    total += n.uint64Value
                }
            }
            return total
        }
    }

    // MARK: - Internals

    private func logFileURLsOldestFirst() -> [URL] {
        var urls: [URL] = []
        for i in (1...maxRotatedFiles).reversed() {
            let u = directoryURL.appendingPathComponent("plexios.\(i).log")
            if FileManager.default.fileExists(atPath: u.path) { urls.append(u) }
        }
        if FileManager.default.fileExists(atPath: currentLogURL.path) {
            urls.append(currentLogURL)
        }
        return urls
    }

    private func logFileURLsNewestFirst() -> [URL] {
        logFileURLsOldestFirst().reversed()
    }

    private func openHandleIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: currentLogURL.path) {
            fm.createFile(atPath: currentLogURL.path, contents: nil)
        }
        if fileHandle == nil {
            fileHandle = try? FileHandle(forWritingTo: currentLogURL)
            fileHandle?.seekToEndOfFile()
        }
    }

    private func closeHandleUnlocked() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func writeLineUnlocked(_ line: String) {
        openHandleIfNeeded()
        guard let data = line.data(using: .utf8) else { return }
        do {
            try fileHandle?.write(contentsOf: data)
            // Persist promptly so a hard crash keeps the trailing lines.
            fileHandle?.synchronizeFile()
        } catch {
            closeHandleUnlocked()
            openHandleIfNeeded()
            try? fileHandle?.write(contentsOf: data)
            fileHandle?.synchronizeFile()
        }
        rotateIfNeededUnlocked()
    }

    private func rotateIfNeededUnlocked() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: currentLogURL.path)[.size] as? NSNumber
        else { return }
        guard size.uint64Value >= maxFileBytes else { return }
        closeHandleUnlocked()
        let fm = FileManager.default
        let last = directoryURL.appendingPathComponent("plexios.\(maxRotatedFiles).log")
        try? fm.removeItem(at: last)
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let src = directoryURL.appendingPathComponent("plexios.\(i).log")
            let dst = directoryURL.appendingPathComponent("plexios.\(i + 1).log")
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        }
        let rotated = directoryURL.appendingPathComponent("plexios.1.log")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: currentLogURL, to: rotated)
        openHandleIfNeeded()
    }

    // MARK: - Crash hooks

    private static var hooksInstalled = false

    private static func installCrashHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true

        NSSetUncaughtExceptionHandler { exception in
            let msg = "Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "") — \(exception.callStackSymbols.prefix(12).joined(separator: " | "))"
            FileLogStore.shared.appendAndFlush(level: .fault, category: "crash", message: msg)
        }

        // Signal: only write(2) to stderr (async-signal-safe). Per-line fsync on
        // normal logs is the primary durability mechanism for hard crashes.
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        for sig in signals {
            signal(sig) { s in
                let msg = "\n[FAULT][crash] signal \(s)\n"
                _ = msg.withCString { ptr in
                    write(STDERR_FILENO, ptr, strlen(ptr))
                }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}
