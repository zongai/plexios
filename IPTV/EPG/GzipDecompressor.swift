import Foundation
import zlib

/// Reliable gzip / zlib inflate for XMLTV and other IPTV payloads.
enum GzipDecompressor {
    /// Decompress if payload looks like gzip or zlib; otherwise return original data.
    static func decompressIfNeeded(_ data: Data) -> Data {
        guard data.count > 2 else { return data }
        // gzip magic
        if data[0] == 0x1f, data[1] == 0x8b {
            if let out = gunzip(data) { return out }
            return data
        }
        // zlib header (0x78 0x01 / 0x9C / 0xDA)
        if data[0] == 0x78 {
            if let out = inflateZlib(data) { return out }
        }
        return data
    }

    static func gunzip(_ data: Data) -> Data? {
        inflate(data, windowBits: 16 + MAX_WBITS)
    }

    static func inflateZlib(_ data: Data) -> Data? {
        inflate(data, windowBits: MAX_WBITS)
    }

    /// Raw DEFLATE (no wrapper).
    static func inflateRaw(_ data: Data) -> Data? {
        inflate(data, windowBits: -MAX_WBITS)
    }

    private static func inflate(_ data: Data, windowBits: Int32) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        var status = inflateInit2_(
            &stream,
            windowBits,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)

        status = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int32 in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)

            var st: Int32 = Z_OK
            while st == Z_OK {
                st = buffer.withUnsafeMutableBufferPointer { dest in
                    stream.next_out = dest.baseAddress
                    stream.avail_out = uInt(chunk)
                    let r = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunk - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(dest.baseAddress!, count: produced)
                    }
                    return r
                }
                // Grow safety: abort absurd expansion (> 64× or 80 MB)
                if output.count > max(data.count * 64, 80 * 1024 * 1024) {
                    return Z_DATA_ERROR
                }
            }
            return st
        }

        guard status == Z_STREAM_END || (status == Z_OK && !output.isEmpty) else {
            // Fallback: strip gzip header and try raw deflate
            if windowBits == 16 + MAX_WBITS, let raw = stripGzipHeader(data) {
                return inflateRaw(raw)
            }
            return output.isEmpty ? nil : output
        }
        return output.isEmpty ? nil : output
    }

    private static func stripGzipHeader(_ data: Data) -> Data? {
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { return nil }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset + 8 < data.count else { return nil }
        return data.subdata(in: offset..<(data.count - 8))
    }
}
