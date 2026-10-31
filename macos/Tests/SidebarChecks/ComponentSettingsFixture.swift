// Standalone geometry fixture only. Production SettingsManager is not linked
// into this component runner. Color preference behavior is outside these checks.
final class SettingsManager: Sendable {
    static let shared = SettingsManager()
    let monochromeControls = true
}
