import Foundation
import ServiceManagement

private final class MorieXPCContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

@MainActor
final class MorieRuntimeClient {
    enum ClientError: LocalizedError {
        case serviceUnavailable(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable(let message):
                message
            case .invalidResponse:
                "Morie Runtime 返回了无法读取的数据。"
            }
        }
    }

    private var connection: NSXPCConnection?

    func ensureRegistered() throws {
        let service = SMAppService.agent(
            plistName: MorieRuntimeIPC.launchAgentPlistName
        )
        switch service.status {
        case .enabled:
            break
        case .notRegistered:
            try service.register()
        case .requiresApproval:
            throw ClientError.serviceUnavailable(
                "Morie Runtime 需要在“系统设置 → 通用 → 登录项与扩展”中允许后台运行。"
            )
        case .notFound:
            throw ClientError.serviceUnavailable(
                "Morie Runtime 未正确嵌入当前应用。"
            )
        @unknown default:
            throw ClientError.serviceUnavailable(
                "无法确认 Morie Runtime 的后台服务状态。"
            )
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    func snapshot() async throws -> MorieRuntimeSnapshotDTO {
        let data = try await dataRequest { proxy, reply in
            proxy.runtimeSnapshot(reply: reply)
        }
        return try MorieRuntimeCodec.decode(
            MorieRuntimeSnapshotDTO.self,
            from: data
        )
    }

    func startCaptureOnly() async throws {
        try await voidRequest { proxy, reply in
            proxy.startCaptureOnly(reply: reply)
        }
    }

    func bootstrap(completingSetup: Bool) async throws {
        try await voidRequest { proxy, reply in
            proxy.bootstrap(completingSetup, reply: reply)
        }
    }

    func performPermissionAction(
        _ requirement: String
    ) async throws {
        try await voidRequest { proxy, reply in
            proxy.performPermissionAction(requirement, reply: reply)
        }
    }

    func historyPage(limit: Int) async throws -> MorieHistoryPageDTO {
        let data = try await dataRequest { proxy, reply in
            proxy.historyPage(limit, reply: reply)
        }
        return try MorieRuntimeCodec.decode(MorieHistoryPageDTO.self, from: data)
    }

    func historyDetail(_ id: UUID) async throws -> MorieCaptureDTO {
        let data = try await dataRequest { proxy, reply in
            proxy.historyDetail(id.uuidString, reply: reply)
        }
        return try MorieRuntimeCodec.decode(MorieCaptureDTO.self, from: data)
    }

    func deleteHistory(_ id: UUID) async throws {
        try await voidRequest { proxy, reply in
            proxy.deleteHistory(id.uuidString, reply: reply)
        }
    }

    func rerecognizeHistory(_ id: UUID) async throws -> MorieCaptureDTO {
        let data = try await dataRequest { proxy, reply in
            proxy.rerecognizeHistory(id.uuidString, reply: reply)
        }
        return try MorieRuntimeCodec.decode(MorieCaptureDTO.self, from: data)
    }

    func cancelRerecognition(_ id: UUID) async throws {
        try await voidRequest { proxy, reply in
            proxy.cancelRerecognition(id.uuidString, reply: reply)
        }
    }

    func dictionarySnapshot() async throws -> [MorieDictionaryEntryDTO] {
        let data = try await dataRequest { proxy, reply in
            proxy.dictionarySnapshot(reply: reply)
        }
        return try MorieRuntimeCodec.decode([MorieDictionaryEntryDTO].self, from: data)
    }

    func mutateDictionary(
        _ mutation: MorieDictionaryMutationDTO
    ) async throws -> [MorieDictionaryEntryDTO] {
        let request = try MorieRuntimeCodec.encode(mutation)
        let data = try await dataRequest { proxy, reply in
            proxy.mutateDictionary(request, reply: reply)
        }
        return try MorieRuntimeCodec.decode([MorieDictionaryEntryDTO].self, from: data)
    }

    func memorySnapshot() async throws -> [MorieMemoryDTO] {
        let data = try await dataRequest { proxy, reply in
            proxy.memorySnapshot(reply: reply)
        }
        return try MorieRuntimeCodec.decode([MorieMemoryDTO].self, from: data)
    }

    func mutateMemory(
        _ mutation: MorieMemoryMutationDTO
    ) async throws -> [MorieMemoryDTO] {
        let request = try MorieRuntimeCodec.encode(mutation)
        let data = try await dataRequest { proxy, reply in
            proxy.mutateMemory(request, reply: reply)
        }
        return try MorieRuntimeCodec.decode([MorieMemoryDTO].self, from: data)
    }

    func mutateSettings(
        _ mutation: MorieSettingsMutationDTO
    ) async throws -> MorieRuntimeSnapshotDTO {
        let request = try MorieRuntimeCodec.encode(mutation)
        let data = try await dataRequest { proxy, reply in
            proxy.mutateSettings(request, reply: reply)
        }
        return try MorieRuntimeCodec.decode(MorieRuntimeSnapshotDTO.self, from: data)
    }

    func clearExpressionProfile() async throws -> MorieRuntimeSnapshotDTO {
        let data = try await dataRequest { proxy, reply in
            proxy.clearExpressionProfile(reply: reply)
        }
        return try MorieRuntimeCodec.decode(MorieRuntimeSnapshotDTO.self, from: data)
    }

    func factoryReset() async throws {
        try await voidRequest { proxy, reply in
            proxy.factoryReset(reply: reply)
        }
    }

    private func remoteProxy(
        errorHandler: @escaping @Sendable (Error) -> Void
    ) throws -> MorieRuntimeXPCProtocol {
        let connection = try resolvedConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(
            errorHandler
        ) as? MorieRuntimeXPCProtocol else {
            throw ClientError.serviceUnavailable(
                "无法连接 Morie Runtime。"
            )
        }
        return proxy
    }

    private func resolvedConnection() throws -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: MorieRuntimeIPC.serviceName,
            options: []
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: MorieRuntimeXPCProtocol.self
        )
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
            }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func dataRequest(
        _ body: @escaping (
            MorieRuntimeXPCProtocol,
            @escaping @Sendable (Data?, String?) -> Void
        ) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = MorieXPCContinuationGate(continuation)
            do {
                let proxy = try remoteProxy { error in
                    gate.resume(throwing: error)
                }
                body(proxy) { data, message in
                    if let message {
                        gate.resume(
                            throwing: ClientError.serviceUnavailable(message)
                        )
                    } else if let data {
                        gate.resume(returning: data)
                    } else {
                        gate.resume(throwing: ClientError.invalidResponse)
                    }
                }
            } catch {
                gate.resume(throwing: error)
            }
        }
    }

    private func voidRequest(
        _ body: @escaping (
            MorieRuntimeXPCProtocol,
            @escaping @Sendable (String?) -> Void
        ) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let gate = MorieXPCContinuationGate(continuation)
            do {
                let proxy = try remoteProxy { error in
                    gate.resume(throwing: error)
                }
                body(proxy) { message in
                    if let message {
                        gate.resume(
                            throwing: ClientError.serviceUnavailable(message)
                        )
                    } else {
                        gate.resume(returning: ())
                    }
                }
            } catch {
                gate.resume(throwing: error)
            }
        }
    }

}
