import Foundation

enum MorieDefaults {
    static let runtimeDomain = "me.morie.mac"

    static var shared: UserDefaults {
        if Bundle.main.bundleIdentifier == runtimeDomain {
            return .standard
        }
        return UserDefaults(suiteName: runtimeDomain) ?? .standard
    }
}
