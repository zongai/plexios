import CoreGraphics
import SwiftUI
import UIKit

@Observable
@MainActor
final class BitmapSubtitlePresenter {
    var active: [BitmapSubtitleCue] = []
    private var cues: [BitmapSubtitleCue] = []
    private var decoder: (any BitmapSubtitleDecoder)?

    func setFormat(_ format: BitmapSubtitleFormat) {
        decoder = try? BitmapSubtitleDecoderFactory.make(format: format)
        cues.removeAll()
        active = []
    }

    func push(packet: MediaPacket) {
        guard let decoder else { return }
        if let more = try? decoder.push(packet: packet) {
            cues.append(contentsOf: more)
        }
    }

    func update(mediaTimeMs: Int64) {
        active = cues.filter { mediaTimeMs >= $0.startMs && mediaTimeMs < $0.endMs }
    }

    func clear() {
        decoder?.reset()
        cues.removeAll()
        active = []
    }
}

struct BitmapSubtitleOverlayView: View {
    var cues: [BitmapSubtitleCue]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    if let image = makeImage(cue) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(
                                width: geo.size.width * CGFloat(cue.width) / CGFloat(max(cue.videoWidth, 1)),
                                height: geo.size.height * CGFloat(cue.height) / CGFloat(max(cue.videoHeight, 1))
                            )
                            .offset(
                                x: geo.size.width * cue.x,
                                y: geo.size.height * cue.y
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func makeImage(_ cue: BitmapSubtitleCue) -> UIImage? {
        let w = cue.width
        let h = cue.height
        guard w > 0, h > 0, cue.rgba.count >= w * h * 4 else { return nil }
        let bytesPerRow = w * 4
        guard let provider = CGDataProvider(data: cue.rgba as CFData) else { return nil }
        guard let cg = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Combined text + bitmap overlay for Native player chrome.
struct NativeSubtitleStack: View {
    var textEvent: SubtitleCueEvent?
    var textStyle: SubtitleStyle
    var bitmapCues: [BitmapSubtitleCue]

    var body: some View {
        ZStack {
            BitmapSubtitleOverlayView(cues: bitmapCues)
            SubtitleOverlayView(event: textEvent, style: textStyle)
        }
    }
}
