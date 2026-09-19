// Logic tests must not truncate or append to the running app's diagnostic log.
enum DiagnosticLevel: Sendable {
    case info
    case warning
    case error
}

enum Diagnostics {
    static func record(_ category: String, _ message: String, level: DiagnosticLevel = .info) {}
    static func recordMemory(_ phase: String) {}
}
