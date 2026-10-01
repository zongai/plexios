import Foundation

/// Marketing + build display string, e.g. `0.1.0.b99`.
enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Settings / About: `0.1.0.b99` (build from CI `github.run_number`).
    static var displayString: String {
        "\(marketing).b\(build)"
    }
}
