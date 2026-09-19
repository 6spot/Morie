import Foundation
import Security

enum RefinementModelSettings {
    static let modeDefaultsKey = "refinement.model.mode"
    static let cloudBaseURLDefaultsKey = "refinement.cloud.baseURL"
    static let cloudModelNameDefaultsKey = "refinement.cloud.modelName"

    static func load() -> RefinementModelConfiguration {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: modeDefaultsKey)
            .flatMap(RefinementModelMode.init(rawValue:)) ?? .local

        return RefinementModelConfiguration(
            mode: mode,
            cloudBaseURL: defaults.string(forKey: cloudBaseURLDefaultsKey) ?? "",
            cloudModelName: defaults.string(forKey: cloudModelNameDefaultsKey) ?? "",
            cloudAPIKey: (try? RefinementCredentialStore.readAPIKey()) ?? ""
        )
    }

    static func saveMode(_ mode: RefinementModelMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
    }

    static func saveCloudConfiguration(
        baseURL: String,
        modelName: String,
        apiKey: String
    ) throws -> RefinementModelConfiguration {
        let baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !baseURL.isEmpty {
            guard let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host != nil
            else {
                throw RefinementModelSettingsError.invalidBaseURL
            }

            if url.path.lowercased().hasSuffix("/chat/completions") {
                throw RefinementModelSettingsError.chatCompletionsPathIncluded
            }
        }

        UserDefaults.standard.set(baseURL, forKey: cloudBaseURLDefaultsKey)
        UserDefaults.standard.set(modelName, forKey: cloudModelNameDefaultsKey)
        try RefinementCredentialStore.writeAPIKey(apiKey)

        let mode = UserDefaults.standard.string(forKey: modeDefaultsKey)
            .flatMap(RefinementModelMode.init(rawValue:)) ?? .local
        return RefinementModelConfiguration(
            mode: mode,
            cloudBaseURL: baseURL,
            cloudModelName: modelName,
            cloudAPIKey: apiKey
        )
    }
}

enum RefinementModelSettingsError: LocalizedError {
    case invalidBaseURL
    case chatCompletionsPathIncluded
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效，请填写 http 或 https 地址。"
        case .chatCompletionsPathIncluded:
            "请填写 API Base URL，不要包含 /chat/completions；Morie 会自动补全接口路径。"
        case .keychain(let status):
            "无法保存 API Key 到钥匙串（状态码 \(status)）。"
        }
    }
}

private enum RefinementCredentialStore {
    private static let service = "me.morie.mac.refinement-cloud"
    private static let account = "api-key"

    static func readAPIKey() throws -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &result
        )

        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw RefinementModelSettingsError.keychain(status)
        }
        return key
    }

    static func writeAPIKey(_ apiKey: String) throws {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary

        guard !apiKey.isEmpty else {
            let status = SecItemDelete(query)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw RefinementModelSettingsError.keychain(status)
            }
            return
        }

        let data = Data(apiKey.utf8)
        let updateStatus = SecItemUpdate(
            query,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = query as! [String: Any]
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw RefinementModelSettingsError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw RefinementModelSettingsError.keychain(updateStatus)
        }
    }
}
