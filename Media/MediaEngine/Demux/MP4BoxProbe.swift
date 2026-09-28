import Foundation

/// Lightweight MP4/MOV/M4V ftyp + moov probe without FFmpeg (Phase 2 interim).
/// Sufficient to confirm ISO-BMFF and extract duration / track codec hints when moov is near start.
struct MP4BoxProbe: Sendable {
    struct Result: Sendable {
        var brand: String?
        var durationMs: Int64?
        var videoCodecs: [String]
        var audioCodecs: [String]
        var hasMoov: Bool
    }

    func probe(dataSource: HTTPRangeDataSource, maxBytes: Int = 2_000_000) async throws -> Result {
        // Read start of file
        var buffer = try await dataSource.read(offset: 0, length: min(maxBytes, 256 * 1024))
        var brand: String?
        var hasMoov = false
        var durationMs: Int64?
        var videoCodecs: [String] = []
        var audioCodecs: [String] = []

        var offset = 0
        while offset + 8 <= buffer.count {
            let size32 = readU32(buffer, offset)
            let type = readFourCC(buffer, offset + 4)
            var boxSize = Int(size32)
            var header = 8
            if size32 == 1 {
                guard offset + 16 <= buffer.count else { break }
                boxSize = Int(readU64(buffer, offset + 8))
                header = 16
            } else if size32 == 0 {
                boxSize = buffer.count - offset
            }
            if boxSize < header { break }

            if type == "ftyp", offset + header + 4 <= buffer.count {
                brand = readFourCC(buffer, offset + header)
            }
            if type == "moov" {
                hasMoov = true
                let payload = buffer.subdata(in: (offset + header)..<min(offset + boxSize, buffer.count))
                parseMoov(payload, durationMs: &durationMs, video: &videoCodecs, audio: &audioCodecs)
            }

            // Need more data for large early boxes
            if offset + boxSize > buffer.count, buffer.count < maxBytes {
                let need = min(maxBytes, offset + boxSize + 64 * 1024) - buffer.count
                if need > 0 {
                    let more = try await dataSource.read(offset: Int64(buffer.count), length: need)
                    buffer.append(more)
                    continue
                }
            }

            offset += max(boxSize, header)
            if type == "mdat", !hasMoov {
                // moov at end — try tail if we know length
                if let total = await dataSource.totalLength(), total > 512 * 1024 {
                    let tailLen = min(512 * 1024, Int(total))
                    let tail = try await dataSource.read(offset: total - Int64(tailLen), length: tailLen)
                    scanTailForMoov(tail, hasMoov: &hasMoov, durationMs: &durationMs, video: &videoCodecs, audio: &audioCodecs)
                }
                break
            }
        }

        return Result(
            brand: brand,
            durationMs: durationMs,
            videoCodecs: videoCodecs,
            audioCodecs: audioCodecs,
            hasMoov: hasMoov
        )
    }

    private func scanTailForMoov(
        _ data: Data,
        hasMoov: inout Bool,
        durationMs: inout Int64?,
        video: inout [String],
        audio: inout [String]
    ) {
        var offset = 0
        while offset + 8 <= data.count {
            let size32 = readU32(data, offset)
            let type = readFourCC(data, offset + 4)
            var boxSize = Int(size32)
            if size32 == 1, offset + 16 <= data.count {
                boxSize = Int(readU64(data, offset + 8))
            }
            if boxSize < 8 { break }
            if type == "moov" {
                hasMoov = true
                let header = size32 == 1 ? 16 : 8
                let end = min(offset + boxSize, data.count)
                if offset + header < end {
                    let payload = data.subdata(in: (offset + header)..<end)
                    parseMoov(payload, durationMs: &durationMs, video: &video, audio: &audio)
                }
                return
            }
            offset += boxSize
        }
    }

    private func parseMoov(
        _ data: Data,
        durationMs: inout Int64?,
        video: inout [String],
        audio: inout [String]
    ) {
        var offset = 0
        var timescale: Int64 = 1000
        while offset + 8 <= data.count {
            let size32 = readU32(data, offset)
            let type = readFourCC(data, offset + 4)
            let boxSize = size32 == 0 ? data.count - offset : Int(size32)
            if boxSize < 8 { break }
            let header = 8
            let payloadStart = offset + header
            let payloadEnd = min(offset + boxSize, data.count)
            if payloadStart >= payloadEnd {
                offset += boxSize
                continue
            }
            let payload = data.subdata(in: payloadStart..<payloadEnd)

            if type == "mvhd", payload.count >= 20 {
                let version = payload[0]
                if version == 1, payload.count >= 32 {
                    timescale = Int64(readU32(payload, 20))
                    let dur = readU64(payload, 24)
                    if timescale > 0 {
                        durationMs = Int64(dur) * 1000 / timescale
                    }
                } else if payload.count >= 24 {
                    timescale = Int64(readU32(payload, 12))
                    let dur = readU32(payload, 16)
                    if timescale > 0 {
                        durationMs = Int64(dur) * 1000 / timescale
                    }
                }
            }
            if type == "hdlr", payload.count >= 12 {
                let comp = readFourCC(payload, 8)
                // look ahead in sibling stsd via full moov walk for codec — simplified: scan for stsd tags
            }
            // Codec fourccs inside stsd
            if type == "stsd", payload.count > 16 {
                scanStsd(payload, video: &video, audio: &audio)
            }
            // Recurse into containers
            if ["trak", "mdia", "minf", "stbl", "edts"].contains(type) {
                parseMoov(payload, durationMs: &durationMs, video: &video, audio: &audio)
            }
            offset += boxSize
        }
    }

    private func scanStsd(_ data: Data, video: inout [String], audio: inout [String]) {
        // stsd: version/flags(4) + entry_count(4) + sample entries
        guard data.count >= 8 else { return }
        var offset = 8
        while offset + 8 <= data.count {
            let size = Int(readU32(data, offset))
            guard size >= 8, offset + size <= data.count else { break }
            let format = readFourCC(data, offset + 4)
            switch format.lowercased() {
            case "avc1", "avc3", "h264":
                video.append("h264")
            case "hvc1", "hev1", "h265":
                video.append("hevc")
            case "mp4a":
                audio.append("aac")
            case "ac-3", "ac3":
                audio.append("ac3")
            case "ec-3":
                audio.append("eac3")
            case "vp09":
                video.append("vp9")
            case "av01":
                video.append("av1")
            default:
                break
            }
            offset += size
        }
    }

    private func readU32(_ data: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= data.count else { return 0 }
        return UInt32(data[o]) << 24
            | UInt32(data[o + 1]) << 16
            | UInt32(data[o + 2]) << 8
            | UInt32(data[o + 3])
    }

    private func readU64(_ data: Data, _ o: Int) -> UInt64 {
        guard o + 8 <= data.count else { return 0 }
        return UInt64(readU32(data, o)) << 32 | UInt64(readU32(data, o + 4))
    }

    private func readFourCC(_ data: Data, _ o: Int) -> String {
        guard o + 4 <= data.count else { return "" }
        return String(data: data.subdata(in: o..<(o + 4)), encoding: .ascii) ?? ""
    }
}
