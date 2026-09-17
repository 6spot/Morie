import AppKit
import Foundation

struct FrontmostAppTarget {
    let pid: pid_t
    let bundleIdentifier: String?

    static func capture(excluding ownBundleIdentifier: String?) -> FrontmostAppTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier { return nil }
        return FrontmostAppTarget(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }

    func restoreFocus() {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }
}
