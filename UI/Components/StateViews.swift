import SwiftUI

struct LoadingStateView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct EmptyStateView: View {
    let title: String
    var systemImage: String = "tray"
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let subtitle {
                Text(subtitle)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    var recoverySuggestion: String? = nil
    var retry: (() -> Void)? = nil

    init(message: String, recoverySuggestion: String? = nil, retry: (() -> Void)? = nil) {
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.retry = retry
    }

    init(error: PlexError, retry: (() -> Void)? = nil) {
        self.message = error.localizedDescription
        self.recoverySuggestion = ErrorMapping.recoverySuggestion(for: error)
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: AppSpacing.xs) {
                Text(message)
                if let recoverySuggestion {
                    Text(recoverySuggestion)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 160
    var cornerRadius: CGFloat = AppCornerRadius.md

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppColors.posterPlaceholder)
            .frame(width: width, height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}
