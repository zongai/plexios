import SwiftUI

/// SwiftUI overlay for timed text subtitles (Native path).
/// Bitmap PGS/VobSub is Phase 8.
struct SubtitleOverlayView: View {
    var event: SubtitleCueEvent?
    var style: SubtitleStyle

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                if let event, !event.active.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(event.active) { cue in
                            Text(cue.text)
                                .font(.custom(style.fontName, size: style.fontSize * scale(for: geo.size)))
                                .foregroundStyle(Color(
                                    red: style.primaryColor.r,
                                    green: style.primaryColor.g,
                                    blue: style.primaryColor.b
                                ).opacity(style.primaryColor.a))
                                .shadow(
                                    color: Color(
                                        red: style.outlineColor.r,
                                        green: style.outlineColor.g,
                                        blue: style.outlineColor.b
                                    ).opacity(style.outlineColor.a),
                                    radius: style.outlineWidth,
                                    x: 0,
                                    y: style.shadowOffset
                                )
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, geo.size.height * (1.0 - style.verticalPosition))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func scale(for size: CGSize) -> CGFloat {
        // Relative to 1080p reference height
        max(0.55, min(size.height / 1080.0, 1.4))
    }
}

/// Observable bridge for pipeline → UI.
@Observable
@MainActor
final class SubtitlePresenter {
    var event: SubtitleCueEvent?
    var style: SubtitleStyle = SubtitleStyle()
    let controller = SubtitleTrackController()

    func update(mediaTimeMs: Int64) {
        style = controller.subtitleStyle
        event = controller.event(atMs: mediaTimeMs)
    }

    func clear() {
        controller.clear()
        event = nil
    }
}
