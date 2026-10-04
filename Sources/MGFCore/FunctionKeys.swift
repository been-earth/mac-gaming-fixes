import Foundation

/// The "use F1, F2, etc. keys as standard function keys" switch from System Settings,
/// flipped without a logout.
public enum FunctionKeys {
    private static let key = "com.apple.keyboard.fnState" as CFString
    private static let activate = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    public static var isOn: Bool {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool ?? false
    }

    /// Writes the global default, then asks macOS to re-read its settings: the keyboard driver follows at once.
    public static func set(_ on: Bool) throws {
        CFPreferencesSetValue(key, on as CFBoolean, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        try Fixes.run(activate, ["-u"])
    }
}

/// Follows a condition (a chosen app is running, Game Mode is on) without fighting the user:
/// it only switches off what it switched on itself.
public struct AutoSwitch: Equatable {
    public private(set) var engaged = false
    private var wasActive = false

    public init() {}

    /// Call on every change of the condition or of the switch. Returns the state to set, nil to leave it.
    public mutating func update(conditionActive: Bool, isOn: Bool) -> Bool? {
        defer { wasActive = conditionActive }
        if conditionActive, !wasActive, !isOn { engaged = true; return true }
        if !conditionActive, wasActive, engaged { engaged = false; return isOn ? false : nil }
        return nil
    }

    /// The user flipped the switch by hand: from here on it is theirs.
    public mutating func manualChange() { engaged = false }
}
