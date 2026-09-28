import Foundation

/// Minimal MPEG-TS sync / PID presence probe (not a full demuxer).
struct TSProbe: Sendable {
    struct Result: Sendable {
        var isTransportStream: Bool
        var packetSize: Int // 188 or 192 (BDAV)
        var hasPayload: Bool
    }

    func probe(dataSource: HTTPRangeDataSource) async throws -> Result {
        let data = try await dataSource.read(offset: 0, length: 192 * 20)
        // Standard TS 188-byte packets start with 0x47
        if let idx = data.firstIndex(of: 0x47) {
            let i = data.distance(from: data.startIndex, to: idx)
            let size188 = validatePacketSize(data, start: i, size: 188)
            if size188 {
                return Result(isTransportStream: true, packetSize: 188, hasPayload: true)
            }
            let size192 = validatePacketSize(data, start: i, size: 192)
            if size192 {
                return Result(isTransportStream: true, packetSize: 192, hasPayload: true)
            }
        }
        return Result(isTransportStream: false, packetSize: 0, hasPayload: false)
    }

    private func validatePacketSize(_ data: Data, start: Int, size: Int) -> Bool {
        var hits = 0
        var o = start
        while o < data.count {
            if data[o] == 0x47 { hits += 1 }
            o += size
        }
        return hits >= 3
    }
}
