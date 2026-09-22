import CloudKit
import Foundation

enum ICloudSyncSettings {
    static let enabledDefaultsKey = "iCloudSyncEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledDefaultsKey)
    }
}

@MainActor
enum ICloudAccountInspector {
    static func status() async -> Result<CKAccountStatus, Error> {
        do {
            return .success(try await CKContainer.default().accountStatus())
        } catch {
            return .failure(error)
        }
    }

    static func unavailableMessage(for status: CKAccountStatus) -> String? {
        switch status {
        case .available:
            nil
        case .noAccount:
            "这台 Mac 当前没有可用的 iCloud 账户。"
        case .restricted:
            "这台 Mac 的 iCloud 使用受到系统限制。"
        case .couldNotDetermine:
            "暂时无法确认 iCloud 账户状态，请稍后重试。"
        case .temporarilyUnavailable:
            "iCloud 暂时不可用，请稍后重试。"
        @unknown default:
            "当前无法使用 iCloud。"
        }
    }
}
