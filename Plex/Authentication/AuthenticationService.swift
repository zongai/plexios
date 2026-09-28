import Foundation
import Observation

/// Owns Plex account authentication state and PIN flow.
@Observable
@MainActor
final class AuthenticationService {
    enum State: Equatable {
        case unknown
        case signedOut
        case signingIn(code: String, pinID: Int)
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var authToken: String?
    private(set) var lastError: PlexError?

    private let api: PlexAPIClient
    private let keychain: KeychainStore
    private let logger: LogRouter

    private var pollTask: Task<Void, Never>?

    init(api: PlexAPIClient, keychain: KeychainStore, logger: LogRouter) {
        self.api = api
        self.keychain = keychain
        self.logger = logger
    }

    // MARK: - Lifecycle

    /// Restore token from Keychain on launch.
    func restoreSession() async {
        do {
            if let token = try keychain.get(KeychainStore.Keys.plexAuthToken), !token.isEmpty {
                authToken = token
                state = .signedIn
                logger.plex.info("Session restored from Keychain")
            } else {
                state = .signedOut
            }
        } catch {
            logger.plex.error("Keychain restore failed: \(error.localizedDescription)")
            state = .signedOut
        }
    }

    // MARK: - PIN Sign-In

    /// Start PIN flow. Returns the code the user should enter at plex.tv/link.
    @discardableResult
    func startPINSignIn() async throws -> String {
        cancelPolling()
        lastError = nil

        do {
            let pin = try await api.createPIN()
            state = .signingIn(code: pin.code, pinID: pin.id)
            logger.plex.info("PIN created id=\(pin.id)")
            startPolling(pinID: pin.id, code: pin.code)
            return pin.code
        } catch let error as PlexError {
            lastError = error
            state = .signedOut
            throw error
        } catch {
            let mapped = PlexError.network(.transport(error.localizedDescription))
            lastError = mapped
            state = .signedOut
            throw mapped
        }
    }

    /// Link URL for the user (or open in browser / ASWebAuthenticationSession).
    /// User enters the 4-character code at this page (matches plex-for-kodi flow).
    var linkURL: URL {
        if case .signingIn(let code, _) = state {
            var components = URLComponents(string: "https://plex.tv/link")!
            components.queryItems = [URLQueryItem(name: "pin", value: code)]
            return components.url ?? URL(string: "https://plex.tv/link")!
        }
        return URL(string: "https://plex.tv/link")!
    }

    func cancelSignIn() {
        cancelPolling()
        if case .signingIn = state {
            state = .signedOut
        }
    }

    func signOut() {
        cancelPolling()
        authToken = nil
        state = .signedOut
        try? keychain.remove(KeychainStore.Keys.plexAuthToken)
        logger.plex.info("Signed out")
    }

    /// Called when API returns 401.
    func handleTokenInvalidation() {
        logger.plex.warning("Token invalidated")
        signOut()
        lastError = .authentication(.tokenInvalid)
    }

    // MARK: - Polling

    private func startPolling(pinID: Int, code: String) {
        pollTask = Task { [weak self] in
            // Poll every 1.5s for up to ~15 minutes (strong PIN lifetime)
            let maxAttempts = 600
            for attempt in 0..<maxAttempts {
                guard !Task.isCancelled else { return }
                guard let self else { return }

                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(1500))
                }
                guard !Task.isCancelled else { return }

                do {
                    let pin = try await self.api.checkPIN(id: pinID, code: code)
                    if let token = pin.authToken, !token.isEmpty {
                        await self.completeSignIn(token: token)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // Transient errors: keep polling
                    self.logger.plex.debug("PIN poll error: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self?.lastError = .authentication(.pinExpired)
                self?.state = .signedOut
            }
        }
    }

    private func completeSignIn(token: String) async {
        do {
            try keychain.set(token, forKey: KeychainStore.Keys.plexAuthToken)
            authToken = token
            state = .signedIn
            lastError = nil
            logger.plex.info("Sign-in complete")
        } catch {
            lastError = .authentication(.keychain(error))
            state = .signedOut
            logger.plex.error("Failed to store token: \(error.localizedDescription)")
        }
        cancelPolling()
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
