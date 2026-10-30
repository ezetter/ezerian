import Foundation

/// Player preferences, kept between launches (Options menu).
enum Options {
    /// Report damage and remaining health with every blow ("for 7: 31 of 60 left").
    /// Off by default: the scroll just says who hit whom.
    static var showHitScores: Bool {
        get { override ?? showHitScores(in: .standard) }
        set {
            if override != nil { override = newValue } else { UserDefaults.standard.set(newValue, forKey: "showHitScores") }
        }
    }
    static func showHitScores(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: "showHitScores") }

    /// Set by the self-tests so they never touch the player's real preferences.
    static var override: Bool?
}
