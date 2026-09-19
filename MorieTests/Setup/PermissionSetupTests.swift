import Foundation
import Speech
import XCTest

@MainActor
final class PermissionSetupTests: XCTestCase {
    func testEveryRequirementIsMandatoryIncludingSpeechAuthorization() async {
        let fixture = SetupFixture()
        XCTAssertFalse(fixture.controller.isReady)

        for requirement in SetupRequirement.allCases {
            fixture.snapshot = SetupFixture.readyChecks.filter { $0.requirement != requirement }
            await fixture.controller.refresh()
            XCTAssertFalse(fixture.controller.isReady, "\(requirement) must not be optional")
        }

        fixture.snapshot = SetupFixture.readyChecks
        await fixture.controller.refresh()
        XCTAssertTrue(fixture.controller.isReady)
    }

    func testRefreshOnlyInspectsAndDetectsRevocationAndRecovery() async {
        let fixture = SetupFixture()
        await fixture.controller.refresh()
        XCTAssertTrue(fixture.controller.isReady)

        fixture.set(.microphone, state: .denied, action: .openSettings)
        await fixture.controller.refresh()
        XCTAssertFalse(fixture.controller.isReady)
        XCTAssertEqual(fixture.controller.firstIssue?.requirement, .microphone)

        fixture.snapshot = SetupFixture.readyChecks
        await fixture.controller.refresh()
        XCTAssertTrue(fixture.controller.isReady)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertTrue(fixture.settingsOpened.isEmpty)
    }

    func testPermissionIsRequestedOnlyAfterExplicitAction() async {
        let fixture = SetupFixture()
        fixture.set(.microphone, state: .notDetermined, action: .requestPermission)
        fixture.requestAction = { requirement in fixture.set(requirement, state: .ready) }

        await fixture.controller.refresh()
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertFalse(fixture.controller.isReady)

        await fixture.controller.performAction(for: .microphone)
        XCTAssertEqual(fixture.requests, [.microphone])
        XCTAssertTrue(fixture.settingsOpened.isEmpty)
        XCTAssertTrue(fixture.controller.isReady)
        XCTAssertFalse(fixture.controller.isBusy)
    }

    func testDeniedPermissionOpensSettingsWithoutReprompting() async {
        let fixture = SetupFixture()
        fixture.set(.speechRecognition, state: .denied, action: .openSettings)

        await fixture.controller.performAction(for: .speechRecognition)
        XCTAssertEqual(fixture.settingsOpened, [.speechRecognition])
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertFalse(fixture.controller.isReady)

        fixture.set(.speechRecognition, state: .ready)
        await fixture.controller.refresh()
        XCTAssertTrue(fixture.controller.isReady)
        XCTAssertEqual(fixture.settingsOpened.count, 1)
    }

    func testAccessibilityUsesAuthorizationLabelForNativeRegistrationFlow() {
        let check = CapabilityCheck(requirement: .accessibility, state: .denied, action: .openSettings)
        XCTAssertEqual(check.actionTitle, "授权")
        XCTAssertEqual(
            CapabilityCheck(requirement: .microphone, state: .denied, action: .openSettings).actionTitle,
            "打开系统设置"
        )
    }

    func testSpeechAuthorizationBackgroundCallbackResumesSetupForAllowAndDeny() async {
        let cases: [(SFSpeechRecognizer.Type, Bool)] = [
            (BackgroundSpeechRecognizer.self, true),
            (DeniedSpeechRecognizer.self, false)
        ]
        for (recognizer, authorized) in cases {
            let fixture = SetupFixture()
            fixture.set(.speechRecognition, state: .notDetermined, action: .requestPermission)
            fixture.requestAction = { requirement in
                await CapabilityGate.requestSpeechAuthorization(using: recognizer)
                MainActor.assertIsolated()
                fixture.set(requirement, state: authorized ? .ready : .denied,
                            action: authorized ? nil : .openSettings)
            }

            await fixture.controller.performAction(for: .speechRecognition)
            XCTAssertEqual(fixture.requests, [.speechRecognition])
            XCTAssertEqual(fixture.inspections, 2)
            XCTAssertEqual(fixture.controller.isReady, authorized)
            XCTAssertFalse(fixture.controller.isBusy)
            XCTAssertNil(fixture.controller.activeRequest)
            XCTAssertTrue(fixture.settingsOpened.isEmpty)
            if !authorized {
                XCTAssertEqual(fixture.controller.firstIssue?.action, .openSettings)
            }
        }
    }

    func testSpeechAuthorizationAlsoAcceptsASynchronousCallback() async {
        await CapabilityGate.requestSpeechAuthorization(using: SynchronousSpeechRecognizer.self)
        MainActor.assertIsolated()
    }

    func testActionRechecksPermissionInsteadOfUsingAnOutdatedButton() async {
        let fixture = SetupFixture()
        fixture.set(.microphone, state: .notDetermined, action: .requestPermission)
        await fixture.controller.refresh()

        fixture.set(.microphone, state: .denied, action: .openSettings)
        await fixture.controller.performAction(for: .microphone)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(fixture.settingsOpened, [.microphone])

        fixture.set(.microphone, state: .ready)
        await fixture.controller.performAction(for: .microphone)
        XCTAssertEqual(fixture.settingsOpened.count, 1)
        XCTAssertTrue(fixture.controller.isReady)
    }

    func testRestrictedPermissionsAndUnsupportedHardwareCannotBeBypassed() async {
        let fixture = SetupFixture()
        fixture.set(.microphone, state: .restricted)
        fixture.set(.appleIntelligence, state: .unavailable)
        for requirement in [SetupRequirement.microphone, .appleIntelligence] {
            await fixture.controller.performAction(for: requirement)
            XCTAssertFalse(fixture.controller.isReady)
            XCTAssertFalse(fixture.controller.isBusy)
        }
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertTrue(fixture.settingsOpened.isEmpty)
    }

    func testConcurrentRefreshesShareOneInspection() async {
        let fixture = SetupFixture()
        let pending = PendingSetupOperation()
        fixture.inspectAction = { await pending.suspend() }

        let first = Task { await fixture.controller.refresh() }
        await pending.waitUntilStarted()
        let second = Task { await fixture.controller.refresh() }
        await Task.yield()
        XCTAssertTrue(fixture.controller.isRefreshing)

        pending.finish()
        await first.value
        await second.value
        XCTAssertEqual(fixture.inspections, 1)
        XCTAssertTrue(fixture.controller.isReady)
        XCTAssertFalse(fixture.controller.isBusy)
    }

    func testDuplicateActionsAndDialogActivationDoNotRaceTheRequest() async {
        let fixture = SetupFixture()
        let pending = PendingSetupOperation()
        fixture.set(.microphone, state: .notDetermined, action: .requestPermission)
        fixture.requestAction = { requirement in
            await pending.suspend()
            fixture.set(requirement, state: .ready)
        }

        let action = Task { await fixture.controller.performAction(for: .microphone) }
        await pending.waitUntilStarted()
        await fixture.controller.performAction(for: .microphone)
        await fixture.controller.performAction(for: .speechRecognition)
        await fixture.controller.refresh() // Native dialog activation.
        XCTAssertEqual(fixture.requests, [.microphone])
        XCTAssertEqual(fixture.inspections, 1)
        XCTAssertEqual(fixture.controller.activeRequest, .microphone)

        pending.finish()
        await action.value
        XCTAssertTrue(fixture.controller.isReady)
        XCTAssertFalse(fixture.controller.isBusy)
        XCTAssertEqual(fixture.inspections, 2)
        XCTAssertTrue(fixture.settingsOpened.isEmpty)
    }
}

// Model the SDK's unannotated Objective-C callback transfer. The production
// completion must be safe on the background queue; the fake must not hop actors.
private struct UnannotatedSpeechCallback: @unchecked Sendable {
    let handler: (SFSpeechRecognizerAuthorizationStatus) -> Void
}

private class BackgroundSpeechRecognizer: SFSpeechRecognizer {
    class var result: SFSpeechRecognizerAuthorizationStatus { .authorized }

    override class func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        let callback = UnannotatedSpeechCallback(handler: handler)
        let status = result
        DispatchQueue.global(qos: .default).async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            callback.handler(status)
        }
    }
}

private final class DeniedSpeechRecognizer: BackgroundSpeechRecognizer {
    override class var result: SFSpeechRecognizerAuthorizationStatus { .denied }
}

private final class SynchronousSpeechRecognizer: SFSpeechRecognizer {
    override class func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        MainActor.assertIsolated()
        handler(.authorized)
    }
}

@MainActor
private final class SetupFixture {
    static var readyChecks: [CapabilityCheck] {
        SetupRequirement.allCases.map { CapabilityCheck(requirement: $0, state: .ready) }
    }

    var snapshot = SetupFixture.readyChecks
    var inspections = 0
    var requests: [SetupRequirement] = []
    var settingsOpened: [SetupRequirement] = []
    var inspectAction: (@MainActor () async -> Void)?
    var requestAction: (@MainActor (SetupRequirement) async -> Void)?

    lazy var controller = PermissionSetupController(
        inspect: { [unowned self] in
            inspections += 1
            await inspectAction?()
            return snapshot
        },
        requestPermission: { [unowned self] requirement in
            requests.append(requirement)
            await requestAction?(requirement)
        },
        openSettings: { [unowned self] in settingsOpened.append($0) }
    )

    func set(_ requirement: SetupRequirement, state: CapabilityCheck.State, action: CapabilityCheck.Action? = nil) {
        snapshot.removeAll { $0.requirement == requirement }
        snapshot.append(.init(requirement: requirement, state: state, action: action))
    }
}

@MainActor
private final class PendingSetupOperation {
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard pending == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        pending?.resume()
        pending = nil
    }
}
