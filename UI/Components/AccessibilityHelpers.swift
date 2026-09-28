import SwiftUI

// MARK: - Accessibility modifiers

extension View {
    /// Combines children and sets a clear VoiceOver label for media cards.
    func mediaAccessibility(title: String, subtitle: String? = nil, progress: Double? = nil) -> some View {
        let progressText: String = {
            guard let progress, progress > 0, progress < 1 else { return "" }
            let pct = Int(progress * 100)
            return ", \(pct) percent watched"
        }()
        let label = [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") + progressText
        return self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    /// Limits readable width on wide regular-size screens (iPad landscape).
    func readableWidth(maxWidth: CGFloat = AppLayout.readableContentWidth) -> some View {
        self.frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Keyboard shortcuts (iPad / Mac Catalyst ready)

struct AppKeyboardShortcuts: ViewModifier {
    var onSearch: (() -> Void)?
    var onHome: (() -> Void)?
    var onRefresh: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .keyboardShortcut("r", modifiers: [.command], localization: .automatic)
            // Note: actual action binding should be on Buttons; this documents intent.
    }
}
