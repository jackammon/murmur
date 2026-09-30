import Foundation

// Maps a logical release channel to its hosted appcast URL. The mapping
// stays in MurmurKit so it can be tested without AppKit or Sparkle.

public enum UpdateChannel: String, Sendable, Equatable, CaseIterable {
    /// Stable releases only — non-prerelease tags.
    case stable
    /// Beta releases.
    case beta
    /// Alpha / prerelease feed — carries every release.
    case alpha
}

/// Maps an `UpdateChannel` to its appcast URL on `jackammon.github.io`.
/// Force-unwrapping the URLs is safe — they're static literals checked at
/// compile time by the tests; a typo would fail the unit test immediately.
public func chooseAppcastURL(channel: UpdateChannel) -> URL {
    let base = "https://jackammon.github.io/murmur"
    let filename: String
    switch channel {
    case .stable: filename = "appcast.xml"
    case .beta:   filename = "appcast-beta.xml"
    case .alpha:  filename = "appcast-alpha.xml"
    }
    return URL(string: "\(base)/\(filename)")!
}

/// Seed the prerelease preference on first launch. Enable it by default for
/// alpha or beta builds; otherwise start disabled. An existing user choice
/// always wins.
///
/// `persistedValue` is the current `receivePrereleases` UserDefaults
/// value, or `nil` if the key has never been written. Passed in
/// explicitly rather than read inside the function so callers can unit-
/// test without touching `UserDefaults.standard` global state.
public func defaultReceivePrereleases(
    version: String,
    persistedValue: Bool?
) -> Bool {
    if let persisted = persistedValue { return persisted }
    return version.contains("-alpha") || version.contains("-beta")
}
