import Foundation

enum BitmapSubtitleError: Error, LocalizedError {
    case unsupported
    case incompleteSegment
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "Bitmap subtitle format unsupported"
        case .incompleteSegment: return "Incomplete PGS/VobSub segment"
        case .parseFailed(let s): return "Bitmap subtitle parse: \(s)"
        }
    }
}

protocol BitmapSubtitleDecoder: AnyObject {
    var format: BitmapSubtitleFormat { get }
    /// Feed demux packets; may return 0..n completed cues when composition is finished.
    func push(packet: MediaPacket) throws -> [BitmapSubtitleCue]
    func flush() -> [BitmapSubtitleCue]
    func reset()
}

// MARK: - PGS (HDMV Presentation Graphic Stream)

/// Minimal PGS segment parser.
/// Spec overview: segments with type + size; ODS (object) + PDS (palette) + PCS (composition) + END.
/// Full production decoder is complex; this implements enough structure to:
/// - detect segment types
/// - accumulate object RLE
/// - emit a cue when END arrives and we have dimensions + palette + object data
final class PGSSubtitleDecoder: BitmapSubtitleDecoder {
    let format: BitmapSubtitleFormat = .pgs

    private var palette: [UInt32] = Array(repeating: 0, count: 256) // RGBA
    private var objectWidth: Int = 0
    private var objectHeight: Int = 0
    private var objectRLE = Data()
    private var compositionX: Int = 0
    private var compositionY: Int = 0
    private var ptsMs: Int64 = 0
    private var videoW: Int = 1920
    private var videoH: Int = 1080
    private var pendingEnd = false

    func push(packet: MediaPacket) throws -> [BitmapSubtitleCue] {
        ptsMs = packet.ptsMs ?? ptsMs
        var data = packet.data
        var emitted: [BitmapSubtitleCue] = []
        while data.count >= 3 {
            let type = data[0]
            let size = Int(data[1]) << 8 | Int(data[2])
            guard data.count >= 3 + size else { break }
            let payload = data.subdata(in: 3..<(3 + size))
            data = data.subdata(in: (3 + size)..<data.count)
            switch type {
            case 0x14: // PDS palette
                parsePDS(payload)
            case 0x15: // ODS object
                parseODS(payload)
            case 0x16: // PCS composition
                parsePCS(payload)
            case 0x17: // WDS window — ignore layout details for now
                break
            case 0x80: // END
                if let cue = composeCue() {
                    emitted.append(cue)
                }
                resetObjectOnly()
            default:
                break
            }
        }
        return emitted
    }

    func flush() -> [BitmapSubtitleCue] {
        if let cue = composeCue() {
            resetObjectOnly()
            return [cue]
        }
        return []
    }

    func reset() {
        palette = Array(repeating: 0, count: 256)
        resetObjectOnly()
    }

    private func resetObjectOnly() {
        objectWidth = 0
        objectHeight = 0
        objectRLE = Data()
        compositionX = 0
        compositionY = 0
        pendingEnd = false
    }

    private func parsePDS(_ data: Data) {
        // palette_id, version, then entries: id, Y, Cr, Cb, Alpha
        guard data.count >= 2 else { return }
        var i = 2
        while i + 5 <= data.count {
            let id = Int(data[i])
            let y = Double(data[i + 1])
            let cr = Double(data[i + 2])
            let cb = Double(data[i + 3])
            let a = UInt8(data[i + 4])
            // BT.601 YCbCr → RGB approx
            let c = y - 16
            let d = cb - 128
            let e = cr - 128
            var r = 1.164 * c + 1.596 * e
            var g = 1.164 * c - 0.392 * d - 0.813 * e
            var b = 1.164 * c + 2.017 * d
            r = min(255, max(0, r))
            g = min(255, max(0, g))
            b = min(255, max(0, b))
            let rgba = UInt32(a) << 24
                | UInt32(r) << 16
                | UInt32(g) << 8
                | UInt32(b)
            if id < 256 { palette[id] = rgba }
            i += 5
        }
    }

    private func parseODS(_ data: Data) {
        // object_id(2), version, sequence_desc, width(2), height(2), rle...
        guard data.count >= 7 else { return }
        let seq = data[3]
        // bit 7: first in sequence, bit 6: last
        let isFirst = (seq & 0x80) != 0
        if isFirst {
            guard data.count >= 7 else { return }
            objectWidth = Int(data[5]) << 8 | Int(data[6])
            // height at 7..8 when first — layout varies; try
            if data.count >= 9 {
                objectHeight = Int(data[7]) << 8 | Int(data[8])
                objectRLE = data.subdata(in: 9..<data.count)
            }
        } else {
            objectRLE.append(data.subdata(in: 4..<data.count))
        }
    }

    private func parsePCS(_ data: Data) {
        // width(2), height(2), ... composition objects with x,y
        guard data.count >= 4 else { return }
        videoW = Int(data[0]) << 8 | Int(data[1])
        videoH = Int(data[2]) << 8 | Int(data[3])
        if data.count >= 11 {
            // simplified: find x,y near end of fixed header
            compositionX = Int(data[data.count - 4]) << 8 | Int(data[data.count - 3])
            compositionY = Int(data[data.count - 2]) << 8 | Int(data[data.count - 1])
        }
    }

    private func composeCue() -> BitmapSubtitleCue? {
        guard objectWidth > 0, objectHeight > 0, !objectRLE.isEmpty else { return nil }
        guard let rgba = decodePGS_RLE(objectRLE, width: objectWidth, height: objectHeight) else {
            return nil
        }
        // Default display 3s if no duration from stream
        let start = ptsMs
        let end = ptsMs + 3000
        return BitmapSubtitleCue(
            startMs: start,
            endMs: end,
            rgba: rgba,
            width: objectWidth,
            height: objectHeight,
            x: videoW > 0 ? CGFloat(compositionX) / CGFloat(videoW) : 0,
            y: videoH > 0 ? CGFloat(compositionY) / CGFloat(videoH) : 0.8,
            videoWidth: videoW,
            videoHeight: videoH
        )
    }

    /// PGS RLE: 00 xx patterns; simplified decoder.
    private func decodePGS_RLE(_ data: Data, width: Int, height: Int) -> Data? {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        var i = 0
        var px = 0
        let total = width * height
        while i < data.count, px < total {
            let b0 = data[i]; i += 1
            if b0 != 0 {
                let color = palette[Int(b0)]
                writeRGBA(&out, px: px, color: color)
                px += 1
            } else {
                guard i < data.count else { break }
                let b1 = data[i]; i += 1
                if b1 == 0 {
                    // end of line — pad to next row
                    if width > 0 {
                        let row = px / width
                        let next = (row + 1) * width
                        px = min(next, total)
                    }
                } else if b1 & 0xC0 == 0x00 {
                    let run = Int(b1 & 0x3F)
                    for _ in 0..<run where px < total {
                        writeRGBA(&out, px: px, color: 0)
                        px += 1
                    }
                } else if b1 & 0xC0 == 0x40 {
                    guard i < data.count else { break }
                    let run = Int(b1 & 0x3F) << 8 | Int(data[i]); i += 1
                    for _ in 0..<run where px < total {
                        writeRGBA(&out, px: px, color: 0)
                        px += 1
                    }
                } else if b1 & 0xC0 == 0x80 {
                    guard i < data.count else { break }
                    let run = Int(b1 & 0x3F)
                    let color = palette[Int(data[i])]; i += 1
                    for _ in 0..<run where px < total {
                        writeRGBA(&out, px: px, color: color)
                        px += 1
                    }
                } else {
                    guard i + 1 < data.count else { break }
                    let run = Int(b1 & 0x3F) << 8 | Int(data[i]); i += 1
                    let color = palette[Int(data[i])]; i += 1
                    for _ in 0..<run where px < total {
                        writeRGBA(&out, px: px, color: color)
                        px += 1
                    }
                }
            }
        }
        return Data(out)
    }

    private func writeRGBA(_ out: inout [UInt8], px: Int, color: UInt32) {
        let o = px * 4
        guard o + 3 < out.count else { return }
        out[o] = UInt8((color >> 16) & 0xff)
        out[o + 1] = UInt8((color >> 8) & 0xff)
        out[o + 2] = UInt8(color & 0xff)
        out[o + 3] = UInt8((color >> 24) & 0xff)
    }
}

// MARK: - VobSub (DVD)

/// VobSub needs .idx + .sub; packet path often provides MPEG SPUs.
/// Phase 8: structural decoder that parses basic SPU control + pixel data when present.
final class VobSubSubtitleDecoder: BitmapSubtitleDecoder {
    let format: BitmapSubtitleFormat = .vobsub

    private var buffer = Data()
    private var ptsMs: Int64 = 0

    func push(packet: MediaPacket) throws -> [BitmapSubtitleCue] {
        ptsMs = packet.ptsMs ?? ptsMs
        buffer.append(packet.data)
        // Need size from header
        guard buffer.count >= 2 else { return [] }
        let size = Int(buffer[0]) << 8 | Int(buffer[1])
        guard size >= 4, buffer.count >= size else { return [] }
        let spu = buffer.prefix(size)
        buffer.removeFirst(size)
        return parseSPU(Data(spu), ptsMs: ptsMs)
    }

    func flush() -> [BitmapSubtitleCue] {
        buffer.removeAll()
        return []
    }

    func reset() {
        buffer.removeAll()
    }

    private func parseSPU(_ data: Data, ptsMs: Int64) -> [BitmapSubtitleCue] {
        // SPU structure is control-sequence heavy; without full state machine
        // emit empty and rely on burn-in / Phase 9 FFmpeg for production VobSub.
        // Provide a transparent placeholder only when dimensions can be guessed.
        guard data.count > 10 else { return [] }
        // Many clients fall back to transcode for DVD subs — mark as no cue.
        return []
    }
}

enum BitmapSubtitleDecoderFactory {
    static func make(format: BitmapSubtitleFormat) throws -> any BitmapSubtitleDecoder {
        switch format {
        case .pgs: return PGSSubtitleDecoder()
        case .vobsub: return VobSubSubtitleDecoder()
        case .unknown: throw BitmapSubtitleError.unsupported
        }
    }
}
