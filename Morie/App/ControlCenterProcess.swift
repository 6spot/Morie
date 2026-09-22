import AppKit
import Darwin
import Foundation

enum MorieProcessRole: Equatable {
    case runtime
    case controlCenter

    static let controlCenterArgument = "--morie-control-center"

    static var current: Self {
        ProcessInfo.processInfo.arguments.contains(controlCenterArgument)
            ? .controlCenter
            : .runtime
    }
}

enum ControlCenterLaunchRoute: String {
    case overview
    case settings

    private static let argumentPrefix = "--morie-control-center-route="

    static var current: Self {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(argumentPrefix) }
            .flatMap { argument in
                Self(
                    rawValue: String(
                        argument.dropFirst(argumentPrefix.count)
                    )
                )
            }
            ?? .overview
    }

    var argument: String {
        Self.argumentPrefix + rawValue
    }
}

struct ControlCenterRuntimeSnapshot: Codable, Sendable {
    let checks: [CapabilityCheck]
    let isBootstrapping: Bool
    let setupError: String?
    let canStartCapture: Bool
    let isCaptureActive: Bool
    let speechBackend: SpeechBackendPresentation?
    let localModelStatusTitle: String
}

extension Notification.Name {
    static let morieShowSettings = Notification.Name(
        "MorieShowSettings"
    )
    static let morieControlCenterRouteRequest = Notification.Name(
        "me.morie.mac.control-center.route-request"
    )
    static let morieRuntimeSharedStateChanged = Notification.Name(
        "me.morie.mac.runtime.shared-state-changed"
    )
    static let morieRuntimeSnapshotRequest = Notification.Name(
        "me.morie.mac.runtime.snapshot-request"
    )
    static let morieControlCenterRuntimeSnapshot = Notification.Name(
        "me.morie.mac.control-center.runtime-snapshot"
    )
    static let morieRuntimePermissionActionRequest = Notification.Name(
        "me.morie.mac.runtime.permission-action-request"
    )
    static let morieRuntimeHistoryRecognitionRequest =
        Notification.Name(
            "me.morie.mac.runtime.history-recognition-request"
        )
    static let morieControlCenterHistoryRecognitionResult =
        Notification.Name(
            "me.morie.mac.control-center.history-recognition-result"
        )
    static let morieControlCenterSharedDataChanged = Notification.Name(
        "me.morie.mac.control-center.shared-data-changed"
    )
    static let morieControlCenterHistoryChanged = Notification.Name(
        "me.morie.mac.control-center.history-changed"
    )
    static let morieRuntimeStartCaptureOnlyRequest = Notification.Name(
        "me.morie.mac.runtime.start-capture-only"
    )
    static let morieRuntimeBootstrapRequest = Notification.Name(
        "me.morie.mac.runtime.bootstrap"
    )
    static let morieRuntimeFactoryResetRequest = Notification.Name(
        "me.morie.mac.runtime.factory-reset"
    )
    static let morieControlCenterWillTerminate = Notification.Name(
        "me.morie.mac.control-center.will-terminate"
    )
}

enum ControlCenterProcessBridge {
    private static let routeKey = "route"
    private static let snapshotKey = "snapshot"
    private static let requirementKey = "requirement"
    private static let requestIDKey = "requestID"
    private static let captureIDKey = "captureID"
    private static let textKey = "text"
    private static let errorKey = "error"

    static func requestRoute(_ route: ControlCenterLaunchRoute) {
        DistributedNotificationCenter.default().postNotificationName(
            .morieControlCenterRouteRequest,
            object: nil,
            userInfo: [routeKey: route.rawValue],
            deliverImmediately: true
        )
    }

    static func route(from notification: Notification) -> ControlCenterLaunchRoute? {
        guard let rawValue = notification.userInfo?[routeKey] as? String else {
            return nil
        }
        return ControlCenterLaunchRoute(rawValue: rawValue)
    }

    static func requestRuntimeSnapshot() {
        post(.morieRuntimeSnapshotRequest)
    }

    static func publishRuntimeSnapshot(
        _ snapshot: ControlCenterRuntimeSnapshot
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            .morieControlCenterRuntimeSnapshot,
            object: nil,
            userInfo: [snapshotKey: data],
            deliverImmediately: true
        )
    }

    static func runtimeSnapshot(
        from notification: Notification
    ) -> ControlCenterRuntimeSnapshot? {
        guard let data =
            notification.userInfo?[snapshotKey] as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(
            ControlCenterRuntimeSnapshot.self,
            from: data
        )
    }

    static func requestPermissionAction(
        _ requirement: SetupRequirement
    ) {
        DistributedNotificationCenter.default().postNotificationName(
            .morieRuntimePermissionActionRequest,
            object: nil,
            userInfo: [requirementKey: requirement.rawValue],
            deliverImmediately: true
        )
    }

    static func permissionRequirement(
        from notification: Notification
    ) -> SetupRequirement? {
        guard let rawValue =
            notification.userInfo?[requirementKey] as? String else {
            return nil
        }
        return SetupRequirement(rawValue: rawValue)
    }

    static func requestHistoryRecognition(
        captureID: UUID,
        requestID: UUID
    ) {
        DistributedNotificationCenter.default()
            .postNotificationName(
                .morieRuntimeHistoryRecognitionRequest,
                object: nil,
                userInfo: [
                    requestIDKey: requestID.uuidString,
                    captureIDKey: captureID.uuidString,
                ],
                deliverImmediately: true
            )
    }

    static func historyRecognitionRequest(
        from notification: Notification
    ) -> (requestID: UUID, captureID: UUID)? {
        guard let requestRaw =
                notification.userInfo?[requestIDKey] as? String,
              let captureRaw =
                notification.userInfo?[captureIDKey] as? String,
              let requestID = UUID(uuidString: requestRaw),
              let captureID = UUID(uuidString: captureRaw)
        else {
            return nil
        }
        return (requestID, captureID)
    }

    static func publishHistoryRecognitionResult(
        requestID: UUID,
        text: String?,
        error: String?
    ) {
        var userInfo: [String: Any] = [
            requestIDKey: requestID.uuidString
        ]
        if let text {
            userInfo[textKey] = text
        }
        if let error {
            userInfo[errorKey] = error
        }

        DistributedNotificationCenter.default()
            .postNotificationName(
                .morieControlCenterHistoryRecognitionResult,
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
    }

    static func historyRecognitionResult(
        from notification: Notification
    ) -> (
        requestID: UUID,
        text: String?,
        error: String?
    )? {
        guard let requestRaw =
                notification.userInfo?[requestIDKey] as? String,
              let requestID = UUID(uuidString: requestRaw)
        else {
            return nil
        }
        return (
            requestID,
            notification.userInfo?[textKey] as? String,
            notification.userInfo?[errorKey] as? String
        )
    }

    static func notifySharedStateChanged() {
        post(.morieRuntimeSharedStateChanged)
    }

    static func notifyControlCenterSharedDataChanged() {
        post(.morieControlCenterSharedDataChanged)
    }

    static func notifyControlCenterHistoryChanged() {
        post(.morieControlCenterHistoryChanged)
    }

    static func requestCaptureOnly() {
        post(.morieRuntimeStartCaptureOnlyRequest)
    }

    static func requestBootstrap() {
        post(.morieRuntimeBootstrapRequest)
    }

    static func requestFactoryReset() {
        post(.morieRuntimeFactoryResetRequest)
    }

    static func notifyWillTerminate() {
        post(.morieControlCenterWillTerminate)
    }

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

@MainActor
enum ControlCenterProcessLauncher {
    private static var launchedPID: pid_t?

    static func open(
        _ route: ControlCenterLaunchRoute = .overview
    ) {
        Diagnostics.recordMemory(
            "control-center-process-launch-request"
        )

        if let existing = runningControlCenterProcess() {
            launchedPID = existing.processIdentifier
            ControlCenterProcessBridge.requestRoute(route)
            _ = existing.activate(options: [])
            return
        }

        if let launchedPID,
           kill(launchedPID, 0) == 0 {
            ControlCenterProcessBridge.requestRoute(route)
            return
        }

        let executableURL = controlCenterExecutableURL
        guard FileManager.default.isExecutableFile(
            atPath: executableURL.path
        ) else {
            Diagnostics.record(
                "ControlCenterProcess",
                "Embedded helper is missing or not executable at \(executableURL.path)",
                level: .error
            )
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [route.argument]

        do {
            try process.run()
            launchedPID = process.processIdentifier

            Diagnostics.record(
                "ControlCenterProcess",
                "Launched helper pid=\(process.processIdentifier); route=\(route.rawValue)"
            )

            if let application = NSRunningApplication(
                processIdentifier: process.processIdentifier
            ) {
                _ = application.activate(options: [])
            }
        } catch {
            launchedPID = nil
            Diagnostics.record(
                "ControlCenterProcess",
                "Could not launch Control Center helper: \(error.localizedDescription)",
                level: .error
            )
        }
    }

    private static var controlCenterExecutableURL: URL {
        Bundle.main.bundleURL
            .appending(path: "Contents/Helpers")
            .appending(path: "Morie Control Center")
    }

    private static func runningControlCenterProcess()
        -> NSRunningApplication? {
        let helperURL =
            controlCenterExecutableURL.standardizedFileURL
        return NSWorkspace.shared.runningApplications
            .first {
                $0.processIdentifier
                    != ProcessInfo.processInfo.processIdentifier
                    && $0.executableURL?
                        .standardizedFileURL == helperURL
            }
    }
}

