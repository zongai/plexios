import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isStarting = false

    private var auth: AuthenticationService { environment.authenticationService }

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accent)

            Text("Sign in to Plex")
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

            Text(code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.primaryText)
                .padding()
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md))
                .accessibilityLabel("Link code \(Array(code).map(String.init).joined(separator: " "))")
                .accessibilityAddTraits(.updatesFrequently)

            ProgressView("Waiting for authorization…")
                .font(AppTypography.caption)
                .accessibilityLabel("Waiting for authorization")

            Button("Cancel") {
                auth.cancelSignIn()
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColors.secondaryText)
        }
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment())
}
