import SwiftUI
import UIKit

struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isStarting = false
    @State private var didCopyCode = false

    private var auth: AuthenticationService { environment.authenticationService }

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accent)

            Text(L10n.signInTitle)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("You’ll authorize this device on plex.tv")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            switch auth.state {
            case .signingIn(let code, _):
                pinContent(code: code)
            default:
                signInButton
            }

            if let error = auth.lastError {
                Text(error.localizedDescription)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var signInButton: some View {
        Button {
            Task {
                isStarting = true
                defer { isStarting = false }
                try? await auth.startPINSignIn()
            }
        } label: {
            Group {
                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue with Plex")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: 280)
            .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isStarting)
    }

    private func pinContent(code: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Text("Enter this code at")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.secondaryText)

            Link("plex.tv/link", destination: auth.linkURL)
                .font(AppTypography.headline)

            Button {
                UIPasteboard.general.string = code
                didCopyCode = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    didCopyCode = false
                }
            } label: {
                VStack(spacing: AppSpacing.xs) {
                    Text(code)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.primaryText)
                        .textSelection(.enabled)
                    Label(
                        didCopyCode ? L10n.copied : "Tap to copy",
                        systemImage: didCopyCode ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(didCopyCode ? AppColors.accent : AppColors.secondaryText)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link code \(Array(code).map(String.init).joined(separator: " "))")
            .accessibilityHint("Copies the code to the clipboard")
            .accessibilityAddTraits(.isButton)

            ProgressView("Waiting for authorization…")
                .font(AppTypography.caption)
                .accessibilityLabel("Waiting for authorization")

            Button("Cancel") {
                auth.cancelSignIn()
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColors.secondaryText)
        }
        .onChange(of: code) { _, _ in
            didCopyCode = false
        }
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment())
}
