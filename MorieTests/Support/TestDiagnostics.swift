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


enum DevelopmentDiagnostics {
    static let isEnabled = false

    static func record(
        _ category: String,
        captureID: UUID? = nil,
        level: DiagnosticLevel = .info,
        _ message: @autoclosure () -> String
    ) {}

    static func text(
        _ category: String,
        captureID: UUID? = nil,
        label: String,
        _ value: String?,
        limit: Int = 8_000
    ) {}

    static func list(
        _ category: String,
        captureID: UUID? = nil,
        label: String,
        _ values: [String],
        limit: Int = 128
    ) {}

    static func recordEnvironment() {}

    static func errorType(_ error: Error) -> String {
        String(reflecting: type(of: error))
    }
}
