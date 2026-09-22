import AppKit
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
    static func open(_ route: ControlCenterLaunchRoute = .overview) {
        Diagnostics.recordMemory("control-center-process-launch-request")

        if let existing = runningControlCenterProcess() {
            if route != .overview {
                ControlCenterProcessBridge.requestRoute(route)
            }
            _ = existing.activate(options: [])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            MorieProcessRole.controlCenterArgument,
            route.argument,
        ]

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { application, error in
            if let error {
                Diagnostics.record(
                    "ControlCenterProcess",
                    "Could not launch Control Center process: \(error.localizedDescription)",
                    level: .error
                )
                return
            }

            Diagnostics.record(
                "ControlCenterProcess",
                "Launched pid=\(application?.processIdentifier ?? 0); route=\(route.rawValue)"
            )
        }
    }

    private static func runningControlCenterProcess() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return nil
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID }
    }
}
