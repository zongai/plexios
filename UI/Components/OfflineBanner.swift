import SwiftUI

/// Thin banner shown when the device path is unsatisfied.
struct OfflineBanner: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if !environment.networkMonitor.isSatisfied {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "wifi.slash")
                Text("You’re offline — showing cached content when available")
                    .font(AppTypography.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.95))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Offline. Showing cached content when available.")
        }
    }
}

extension View {
    func offlineBanner() -> some View {
        VStack(spacing: 0) {
            OfflineBanner()
            self
        }
    }
}
