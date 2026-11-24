import Foundation

// The user's choice is independent of the effective (permission-gated) switch.
final class PalettePermissionState {
    private static let choiceKey = "paletteUserChoiceV1"
    private let defaults: UserDefaults
    private(set) var trusted: Bool
    private(set) var pendingEnable = false
    var enabled: Bool { trusted && (defaults.object(forKey: Self.choiceKey) as? Bool ?? true) }

    init(trusted: Bool, defaults: UserDefaults = .standard) {
        self.trusted = trusted
        self.defaults = defaults
        // Preserve choices made before this policy existed. New installs have no
        // choice yet; postponing authorization must never write a negative choice.
        if defaults.object(forKey: Self.choiceKey) == nil,
           let previous = defaults.object(forKey: "paletteEnabled") as? Bool {
            defaults.set(previous, forKey: Self.choiceKey)
        }
    }
    func updatePermission(_ granted: Bool) {
        trusted = granted
        if granted, pendingEnable {
            defaults.set(true, forKey: Self.choiceKey)
            pendingEnable = false
        }
    }
    // Returns true when the switch needs authorization before it can turn on.
    func request(_ enabled: Bool) -> Bool {
        if !enabled {
            pendingEnable = false
            defaults.set(false, forKey: Self.choiceKey)
        } else if trusted {
            defaults.set(true, forKey: Self.choiceKey)
        } else {
            pendingEnable = true
            return true
        }
        return false
    }
    func cancelAuthorization() { pendingEnable = false }
}
