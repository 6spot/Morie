import Carbon
import Foundation

final class GlobalHotKey {
    enum Error: LocalizedError {
        case installHandler(OSStatus)
        case register(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandler(let status): "Unable to install global hotkey handler (OSStatus \(status))."
            case .register(let status): "Unable to register global hotkey (OSStatus \(status))."
            }
        }
    }

    private static let signature: OSType = 0x4D4F5249 // 'MORI'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) throws {
        self.onPress = onPress
        self.onRelease = onRelease

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let handlerStatus = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventHandler,
                UInt32(buffer.count),
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }
        guard handlerStatus == noErr else { throw Error.installHandler(handlerStatus) }

        var id = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else { throw Error.register(registerStatus) }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

        var id = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &id
        )
        guard status == noErr, id.signature == signature, id.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            Task { @MainActor in instance.onPress?() }
        case UInt32(kEventHotKeyReleased):
            Task { @MainActor in instance.onRelease?() }
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
