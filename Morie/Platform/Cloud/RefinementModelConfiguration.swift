import Foundation

enum RefinementModelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case local
    case cloud

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .local: "Apple 本机"
        case .cloud: "外部 API"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "优先使用已配置的外部模型，失败时回退 Apple 本机模型。"
        case .local:
            "始终使用这台 Mac 上的 Apple Foundation Models。"
        case .cloud:
            "始终使用已配置的 OpenAI-compatible Chat Completions API。"
        }
    }
}

struct RefinementModelConfiguration: Equatable, Sendable {
    let mode: RefinementModelMode
    let cloudBaseURL: String
    let cloudModelName: String
    let cloudAPIKey: String

    static let local = RefinementModelConfiguration(
        mode: .local,
        cloudBaseURL: "",
        cloudModelName: "",
        cloudAPIKey: ""
    )

    var cloudURL: URL? {
        let value = cloudBaseURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else {
            return nil
        }
        return url
    }

    var trimmedCloudModelName: String {
        cloudModelName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var hasUsableCloudConfiguration: Bool {
        cloudURL != nil && !trimmedCloudModelName.isEmpty
    }
}
