import AppKit
import Foundation

@main
enum MorieRuntimeMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = MorieRuntimeApplicationDelegate()
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class MorieRuntimeApplicationDelegate: NSObject, NSApplicationDelegate {
    private var composition: MorieRuntimeComposition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let composition = try MorieRuntimeComposition()
            self.composition = composition
            composition.start()
        } catch {
            Diagnostics.record(
                "Runtime",
                "Runtime failed to start: \(error.localizedDescription)",
                level: .error
            )
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
final class MorieRuntimeComposition {
    let controller: MorieRuntimeController
    let server: MorieRuntimeXPCServer
    let statusItem: MorieRuntimeStatusItem

    init() throws {
        let wantsICloud = ICloudSyncSettings.isEnabled
        let store: CaptureStore?
        let persistenceError: Error?
        let cloudSyncStartupError: Error?

        do {
            store = try CaptureStore(cloudSyncEnabled: wantsICloud)
            persistenceError = nil
            cloudSyncStartupError = nil
        } catch let cloudError where wantsICloud {
            do {
                store = try CaptureStore(cloudSyncEnabled: false)
                persistenceError = nil
                cloudSyncStartupError = cloudError
            } catch {
                store = nil
                persistenceError = error
                cloudSyncStartupError = cloudError
            }
        } catch {
            store = nil
            persistenceError = error
            cloudSyncStartupError = nil
        }

        controller = MorieRuntimeController(
            captureStore: store,
            persistenceError: persistenceError,
            cloudSyncStartupError: cloudSyncStartupError
        )
        server = MorieRuntimeXPCServer(controller: controller)
        statusItem = MorieRuntimeStatusItem(controller: controller)
    }

    func start() {
        server.start()
        statusItem.install()
        Diagnostics.record(
            "Runtime",
            "Morie Runtime started; pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
        Diagnostics.recordMemory("runtime-started")
    }
}
