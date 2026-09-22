import Foundation

enum ICloudSyncState: Equatable {
    case off
    case checking
    case ready
    case restartRequired(String)
    case unavailable(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .off:
            "关闭。数据只保存在这台 Mac 上。"
        case .checking:
            "正在检查 iCloud…"
        case .ready:
            "已启用，使用你的 iCloud 私有数据库同步。"
        case .restartRequired(let message):
            message
        case .unavailable(let message):
            message
        }
    }
}
