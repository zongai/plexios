import CoreGraphics
import Foundation

/// Bitmap subtitle cue (PGS / VobSub).
struct BitmapSubtitleCue: Sendable, Identifiable {
    var id: String { "\(startMs)-\(endMs)-\(width)x\(height)" }
    var startMs: Int64
    var endMs: Int64
    /// RGBA8888 pixel data.
    var rgba: Data
    var width: Int
    var height: Int
    /// Placement in video frame coordinates (0...1 origin top-left).
    var x: CGFloat
    var y: CGFloat
    var videoWidth: Int
    var videoHeight: Int
}

enum BitmapSubtitleFormat: String, Sendable {
    case pgs
    case vobsub
    case unknown

    static func from(codecOrFormat: String?) -> BitmapSubtitleFormat {
        let c = (codecOrFormat ?? "").lowercased()
        if c.contains("pgs") || c == "hdmv_pgs_subtitle" { return .pgs }
        if c.contains("vobsub") || c == "dvd_subtitle" || c == "dvdsub" { return .vobsub }
        return .unknown
    }
}
