import Combine
import Foundation

struct RefinementConfiguration: Equatable, Sendable {
    let model: RefinementModelConfiguration
    let instructions: String

    static let local = RefinementConfiguration(
        model: .local,
        instructions: RefinementPromptSettings.defaultInstructions
    )
}

private final class RefinementPromptBundleToken: NSObject {}

enum RefinementPromptSettings {
    static let defaultsKey = "refinement.prompt.instructions"

    /// The shipped baseline lives as a bundle text resource. Runtime edits are
    /// stored in UserDefaults and therefore do not require rebuilding Morie.
    static let defaultInstructions: String = {
        let bundle = Bundle(for: RefinementPromptBundleToken.self)
        guard let url = bundle.url(
            forResource: "DefaultRefinementInstructions",
            withExtension: "txt"
        ),
        let text = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
        else {
            preconditionFailure("DefaultRefinementInstructions.txt is missing or empty")
        }
        return text
    }()

    static func load(from defaults: UserDefaults = .standard) -> String {
        guard let saved = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !saved.isEmpty
        else {
            return defaultInstructions
        }
        return saved
    }

    @discardableResult
    static func save(_ instructions: String, to defaults: UserDefaults = .standard) -> Bool {
        let value = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        defaults.set(value, forKey: defaultsKey)
        return true
    }

    static func restoreDefault(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

@MainActor
final class RefinementPromptController: ObservableObject {
    @Published private(set) var instructions: String
    @Published private(set) var settingsMessage: String?

    init(load: () -> String = RefinementPromptSettings.load) {
        instructions = load()
    }

    var isDefault: Bool {
        instructions == RefinementPromptSettings.defaultInstructions
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        guard RefinementPromptSettings.save(value) else {
            settingsMessage = "提示词不能为空。"
            return false
        }
        instructions = RefinementPromptSettings.load()
        settingsMessage = "润色提示词已保存，将从下一次录音开始生效。"
        return true
    }

    func restoreDefault() {
        RefinementPromptSettings.restoreDefault()
        instructions = RefinementPromptSettings.defaultInstructions
        settingsMessage = "已恢复 Morie 默认润色提示词。"
    }
}
