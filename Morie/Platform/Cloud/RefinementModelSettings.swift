import Combine
import Foundation
import FoundationModels
import Security

enum RefinementModelSettings {
    static let modeDefaultsKey = "refinement.model.mode"
    static let cloudBaseURLDefaultsKey = "refinement.cloud.baseURL"
    static let cloudModelNameDefaultsKey = "refinement.cloud.modelName"

    /// Loads only non-secret preferences. Launch-time callers must never touch Keychain.
    static func load() -> RefinementModelConfiguration {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: modeDefaultsKey)
            .flatMap(RefinementModelMode.init(rawValue:)) ?? .local

        return RefinementModelConfiguration(
            mode: mode,
            cloudBaseURL: defaults.string(forKey: cloudBaseURLDefaultsKey) ?? "",
            cloudModelName: defaults.string(forKey: cloudModelNameDefaultsKey) ?? "",
            cloudAPIKey: ""
        )
    }

    static func readAPIKey() throws -> String {
        try RefinementCredentialStore.readAPIKey()
    }

    static func saveMode(_ mode: RefinementModelMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
    }

    /// Saves public endpoint metadata and optionally replaces the Keychain credential.
    /// Passing nil leaves the existing credential untouched so Settings never needs to
    /// read the secret just to round-trip the rest of the form.
    static func saveCloudConfiguration(
        baseURL: String,
        modelName: String,
        newAPIKey: String?
    ) throws -> RefinementModelConfiguration {
        let baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !baseURL.isEmpty {
            guard let url = URL(string: baseURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host != nil
            else {
                throw RefinementModelSettingsError.invalidBaseURL
            }        }

        UserDefaults.standard.set(baseURL, forKey: cloudBaseURLDefaultsKey)
        UserDefaults.standard.set(modelName, forKey: cloudModelNameDefaultsKey)

        if let newAPIKey {
            try RefinementCredentialStore.writeAPIKey(
                newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let mode = UserDefaults.standard.string(forKey: modeDefaultsKey)
            .flatMap(RefinementModelMode.init(rawValue:)) ?? .local
        return RefinementModelConfiguration(
            mode: mode,
            cloudBaseURL: baseURL,
            cloudModelName: modelName,
            cloudAPIKey: ""
        )
    }

    static func clearAPIKey() throws {
        try RefinementCredentialStore.writeAPIKey("")
    }

    static func resetToDefaults() throws {
        try RefinementCredentialStore.writeAPIKey("")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: modeDefaultsKey)
        defaults.removeObject(forKey: cloudBaseURLDefaultsKey)
        defaults.removeObject(forKey: cloudModelNameDefaultsKey)
    }
}

@MainActor
final class RefinementModelController: ObservableObject {
    @Published private(set) var mode: RefinementModelMode
    @Published private(set) var cloudBaseURL: String
    @Published private(set) var cloudModelName: String
    @Published private(set) var settingsMessage: String?

    /// A successful Keychain read/write is kept only for this process lifetime.
    /// Relaunch stays Keychain-free until an external model is actually needed.
    private var cachedAPIKey: String?
    private let credentialReader: () throws -> String

    init(
        load: () -> RefinementModelConfiguration = RefinementModelSettings.load,
        credentialReader: @escaping () throws -> String = RefinementModelSettings.readAPIKey
    ) {
        let saved = load()
        self.credentialReader = credentialReader
        mode = saved.mode
        cloudBaseURL = saved.cloudBaseURL
        cloudModelName = saved.cloudModelName
        settingsMessage = nil
        DevelopmentDiagnostics.record(
            "CloudConfig",
            "controllerInit; mode=\(saved.mode.rawValue); host=\(saved.cloudURL?.host ?? "none"); model=\(saved.trimmedCloudModelName.isEmpty ? "none" : saved.trimmedCloudModelName); keychainRead=false"
        )
    }

    var configuration: RefinementModelConfiguration {
        RefinementModelConfiguration(
            mode: mode,
            cloudBaseURL: cloudBaseURL,
            cloudModelName: cloudModelName,
            cloudAPIKey: cachedAPIKey ?? ""
        )
    }

    var configurationStatusTitle: String {
        configuration.hasUsableCloudConfiguration ? "已配置" : "待配置"
    }

    var modelName: String {
        let externalName = configuration.trimmedCloudModelName
        switch mode {
        case .local:
            return "Apple Foundation Models"
        case .cloud:
            return externalName.isEmpty ? "外部模型" : externalName
        case .automatic:
            return configuration.hasUsableCloudConfiguration
                ? "\(externalName) / Apple Foundation Models"
                : "Apple Foundation Models"
        }
    }

    var modelDetail: String {
        switch mode {
        case .local:
            return "SystemLanguageModel.default · 本机"
        case .cloud:
            return configuration.hasUsableCloudConfiguration
                ? "OpenAI-compatible Chat Completions · 云端"
                : "OpenAI-compatible API 尚未配置完整"
        case .automatic:
            return configuration.hasUsableCloudConfiguration
                ? "外部 API 优先 · 失败回退 Apple 本机"
                : "外部 API 未配置 · 当前使用 Apple 本机"
        }
    }

    func modelStatusTitle(inputRefinementEnabled: Bool) -> String {
        guard inputRefinementEnabled else { return "已关闭" }
        if mode == .cloud {
            return configuration.hasUsableCloudConfiguration ? "已配置" : "待配置"
        }
        if mode == .automatic, configuration.hasUsableCloudConfiguration {
            return "自动"
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(.modelNotReady):
            return "模型准备中"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple 智能未开启"
        case .unavailable(.deviceNotEligible):
            return "设备不支持"
        case .unavailable:
            return "暂不可用"
        }
    }

    func setMode(_ mode: RefinementModelMode) {
        self.mode = mode
        RefinementModelSettings.saveMode(mode)
        DevelopmentDiagnostics.record(
            "CloudConfig",
            "modeChanged=\(mode.rawValue)"
        )
    }

    @discardableResult
    func saveCloudConfiguration(
        baseURL: String,
        modelName: String,
        apiKey: String
    ) -> Bool {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementKey = trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
        let parsedURL = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        DevelopmentDiagnostics.record(
            "CloudConfig",
            "saveRequested; host=\(parsedURL?.host ?? "none"); model=\(modelName.trimmingCharacters(in: .whitespacesAndNewlines)); replaceKey=\(replacementKey != nil); keyLength=\(replacementKey?.count ?? 0); keyContentLogged=false"
        )

        do {
            let saved = try RefinementModelSettings.saveCloudConfiguration(
                baseURL: baseURL,
                modelName: modelName,
                newAPIKey: replacementKey
            )
            cloudBaseURL = saved.cloudBaseURL
            cloudModelName = saved.cloudModelName
            if let replacementKey {
                cachedAPIKey = replacementKey
                settingsMessage = "API 配置和 API Key 已保存。"
            } else {
                settingsMessage = "API 配置已保存；API Key 保持不变。"
            }
            DevelopmentDiagnostics.record(
                "CloudConfig",
                "saveSucceeded; host=\(saved.cloudURL?.host ?? "none"); model=\(saved.trimmedCloudModelName); keyReplaced=\(replacementKey != nil); keyContentLogged=false"
            )
            return true
        } catch {
            DevelopmentDiagnostics.record(
                "CloudConfig",
                level: .warning,
                "saveFailed; errorType=\(DevelopmentDiagnostics.errorType(error)); keyContentLogged=false"
            )
            settingsMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clearCloudAPIKey() -> Bool {
        DevelopmentDiagnostics.record(
            "Keychain",
            "clearRequested; keyContentLogged=false"
        )
        do {
            try RefinementModelSettings.clearAPIKey()
            cachedAPIKey = ""
            settingsMessage = "已清除保存的 API Key。"
            DevelopmentDiagnostics.record(
                "Keychain",
                "clearSucceeded; keyContentLogged=false"
            )
            return true
        } catch {
            DevelopmentDiagnostics.record(
                "Keychain",
                level: .warning,
                "clearFailed; errorType=\(DevelopmentDiagnostics.errorType(error)); keyContentLogged=false"
            )
            settingsMessage = error.localizedDescription
            return false
        }
    }

    /// Resolves the secret only when refinement is actually about to use an
    /// external model. The supplied configuration is the Capture's frozen
    /// endpoint/model snapshot; current Settings changes must not rewrite it.
    func runtimeConfiguration(
        for snapshot: RefinementModelConfiguration
    ) -> RefinementModelConfiguration {
        guard snapshot.mode != .local, snapshot.hasUsableCloudConfiguration else {
            DevelopmentDiagnostics.record(
                "Keychain",
                "runtimeCredentialSkipped; mode=\(snapshot.mode.rawValue); cloudConfigured=\(snapshot.hasUsableCloudConfiguration)"
            )
            return snapshot
        }
        if !snapshot.cloudAPIKey.isEmpty {
            DevelopmentDiagnostics.record(
                "Keychain",
                "runtimeCredentialAlreadyFrozen; keyPresent=true; keyContentLogged=false"
            )
            return snapshot
        }

        let apiKey: String
        if let cachedAPIKey {
            apiKey = cachedAPIKey
            DevelopmentDiagnostics.record(
                "Keychain",
                "runtimeCredentialFromMemoryCache; keyPresent=\(!apiKey.isEmpty); keyContentLogged=false"
            )
        } else {
            DevelopmentDiagnostics.record(
                "Keychain",
                "runtimeCredentialReadRequested; service=me.morie.mac.refinement-cloud; keyContentLogged=false"
            )
            do {
                apiKey = try credentialReader()
                cachedAPIKey = apiKey
                DevelopmentDiagnostics.record(
                    "Keychain",
                    "runtimeCredentialReadSucceeded; keyPresent=\(!apiKey.isEmpty); keyLength=\(apiKey.count); keyContentLogged=false"
                )
            } catch {
                DevelopmentDiagnostics.record(
                    "Keychain",
                    level: .warning,
                    "runtimeCredentialReadFailed; errorType=\(DevelopmentDiagnostics.errorType(error)); keyContentLogged=false"
                )
                settingsMessage = error.localizedDescription
                Diagnostics.record(
                    "Refinement",
                    "Could not read external API credential from Keychain; continuing without a credential",
                    level: .warning
                )
                return snapshot
            }
        }

        return RefinementModelConfiguration(
            mode: snapshot.mode,
            cloudBaseURL: snapshot.cloudBaseURL,
            cloudModelName: snapshot.cloudModelName,
            cloudAPIKey: apiKey
        )
    }
}

enum RefinementModelSettingsError: LocalizedError {
    case invalidBaseURL
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效，请填写 http 或 https 地址。"
        case .keychain(let status):
            "无法访问 macOS 钥匙串中的 API Key（状态码 \(status)）。"
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard !apiKey.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw RefinementModelSettingsError.keychain(status)
            }
            return
        }

        let data = Data(apiKey.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = query
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
