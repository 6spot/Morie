import Foundation

enum MorieDefaults {
    static let suiteName = "me.morie.mac"

    static var shared: UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not open Morie preferences domain.")
        }
        return defaults
    }
}
