import Foundation

enum CaptureShortcut: String, Codable, CaseIterable, Identifiable {
    case functionKey
    case controlSpace
    case optionSpace
    case commandShiftSpace

    static let defaultsKey = "captureShortcut"
    static let defaultValue: CaptureShortcut = .functionKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .functionKey: "Fn / 地球仪"
        case .controlSpace: "⌃ 空格"
        case .optionSpace: "⌥ 空格"
        case .commandShiftSpace: "⇧⌘ 空格"
        }
    }

    var logName: String {
        switch self {
        case .functionKey: "Fn"
        case .controlSpace: "Control+Space"
        case .optionSpace: "Option+Space"
        case .commandShiftSpace: "Command+Shift+Space"
        }
    }
}
