import Foundation

/// Lightweight reachability / speed probe for IPTV sources.
/// Does **not** download full streams — only a small byte range with short timeout.
/// Results gate selection via `disabledUntil` so bad sources are skipped until the next allowed test.
actor SourceProbeService {
    static let shared = SourceProbeService()

    /// Cap concurrent probes app-wide.
    private var inFlight: Set<UUID> = []

    /// Bytes to pull for a crude Mbps sample (keep small).
    private let sampleBytes = 64 * 1024
    private let connectTimeout: TimeInterval = 5
    private let resourceTimeout: TimeInterval = 8

    struct ProbeResult: Sendable {
        var ok: Bool
        var latencyMs: Int
        var mbps: Double?
        var errorDescription: String?
    }

    /// Whether this source is due for a probe given prefs (avoids frequent tests).
    nonisolated func needsProbe(_ source: IPTVSource, prefs: IPTVPreferences, now: Date = Date()) -> Bool {
        guard prefs.autoProbeSources else { return false }
        guard source.streamURL != nil else { return false }
        // Still in failure cooldown — don't probe until cooldown ends
        if let until = source.disabledUntil, until > now {
            return false
        }
        // Never probed
        guard let last = source.lastProbeAt else { return true }
        let interval = max(1, prefs.probeIntervalHours) * 3600
        return now.timeIntervalSince(last) >= interval
    }

    /// Probe a single URL; updates are returned for the caller to persist.
    func probe(source: IPTVSource, prefs: IPTVPreferences) async -> (IPTVSource, ProbeResult) {
        var updated = source
        guard let url = source.streamURL else {
            let r = ProbeResult(ok: false, latencyMs: 0, mbps: nil, errorDescription: "invalid URL")
            updated = applyFailure(updated, prefs: prefs, result: r)
            return (updated, r)
        }
        guard !inFlight.contains(source.id) else {
            return (source, ProbeResult(ok: true, latencyMs: source.lastProbeLatencyMs ?? 0, mbps: source.lastProbeMbps, errorDescription: "in-flight"))
        }
        inFlight.insert(source.id)
        defer { inFlight.remove(source.id) }

        let result = await runProbe(url: url, headers: source.headers)
        if result.ok, result.latencyMs <= prefs.probeMaxLatencyMs {
            updated.lastProbeAt = Date()
            updated.lastProbeLatencyMs = result.latencyMs
            updated.lastProbeMbps = result.mbps
            updated.disabledUntil = nil
            updated.successCount += 1
            updated.lastSuccess = Date()
        } else {
            updated = applyFailure(updated, prefs: prefs, result: result)
        }
        return (updated, result)
    }

    /// Probe candidates that need testing (at most `limit`).
    /// Runs up to `maxConcurrent` probes in parallel to keep the source sheet responsive.
    /// - Parameter force: when true, re-probe even if interval has not elapsed (still respects in-flight).
    func probeIfNeeded(
        sources: [IPTVSource],
        prefs: IPTVPreferences,
        limit: Int = 3,
        force: Bool = false,
        maxConcurrent: Int = 4
    ) async -> [IPTVSource] {
        guard prefs.autoProbeSources || force else { return sources }

        var candidates: [(offset: Int, source: IPTVSource)] = []
        for (i, src) in sources.enumerated() {
            guard candidates.count < limit else { break }
            if force {
                guard src.streamURL != nil else { continue }
            } else {
                guard needsProbe(src, prefs: prefs) else { continue }
            }
            candidates.append((i, src))
        }
        guard !candidates.isEmpty else { return sources }

        var list = sources
        let concurrency = max(1, maxConcurrent)
        var nextIndex = 0
        var inFlight = 0

        await withTaskGroup(of: (Int, IPTVSource).self) { group in
            func enqueue() {
                while nextIndex < candidates.count, inFlight < concurrency {
                    let item = candidates[nextIndex]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        let (updated, _) = await self.probe(source: item.source, prefs: prefs)
                        return (item.offset, updated)
                    }
                }
            }
            enqueue()
            for await (offset, updated) in group {
                inFlight -= 1
                if list.indices.contains(offset) {
                    list[offset] = updated
                }
                enqueue()
            }
        }
        return list
    }

    private func applyFailure(_ source: IPTVSource, prefs: IPTVPreferences, result: ProbeResult) -> IPTVSource {
        var u = source
        u.lastProbeAt = Date()
        u.lastProbeLatencyMs = result.latencyMs
        u.lastProbeMbps = result.mbps
        u.failureCount += 1
        u.lastFailure = Date()
        let cooldown = max(15, prefs.probeFailureCooldownMinutes) * 60
        u.disabledUntil = Date().addingTimeInterval(cooldown)
        return u
    }

    private func runProbe(url: URL, headers: [String: String]) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = connectTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Prefer a small range when server supports it
        request.setValue("bytes=0-\(sampleBytes - 1)", forHTTPHeaderField: "Range")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("PlexiOS/1.0 (IPTV-Probe)", forHTTPHeaderField: "User-Agent")
        }

        let start = Date()
        do {
            let (bytes, response) = try await IPTVNetwork.session.bytes(for: request)
            if let http = response as? HTTPURLResponse {
                // 2xx or 206 Partial Content is success
                if !(200...299).contains(http.statusCode) {
                    return ProbeResult(ok: false, latencyMs: ms(since: start), mbps: nil, errorDescription: "HTTP \(http.statusCode)")
                }
            }
            var received = 0
            let deadline = Date().addingTimeInterval(resourceTimeout)
            for try await b in bytes {
                received += 1
                if received >= sampleBytes { break }
                if Date() > deadline { break }
            }
            let elapsed = Date().timeIntervalSince(start)
            let latency = ms(since: start)
            guard received > 0 else {
                return ProbeResult(ok: false, latencyMs: latency, mbps: nil, errorDescription: "empty body")
            }
            // Mbps from sample
            let mbps = elapsed > 0 ? (Double(received) * 8.0) / (elapsed * 1_000_000.0) : nil
            return ProbeResult(ok: true, latencyMs: latency, mbps: mbps, errorDescription: nil)
        } catch {
            return ProbeResult(
                ok: false,
                latencyMs: ms(since: start),
                mbps: nil,
                errorDescription: IPTVNetwork.describe(error)
            )
        }
    }

    private func ms(since: Date) -> Int {
        Int(Date().timeIntervalSince(since) * 1000)
    }
}
