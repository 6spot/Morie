import Foundation

@MainActor
protocol ControlCenterControlling: AnyObject {
    var runtime: AppRuntimeController { get }
    var capabilities: AppCapabilityController { get }
    var preferences: AppPreferencesController { get }
    var setup: PermissionSetupController { get }
    var refinementModels: RefinementModelController { get }
    var refinementPrompts: RefinementPromptController { get }
    var applicationContextInspector:
        ApplicationContextInspectionStore { get }
    var memory: MemoryStore? { get }
    var dictionary: DictionaryStore? { get }

    var canStartCapture: Bool { get }
    var canCompleteSetup: Bool { get }
    var isCaptureActive: Bool { get }

    func makeControlCenterHistoryController()
        -> CaptureHistoryController?
    func controlCenterUsageMetrics()
        throws -> CaptureUsageMetricsSnapshot

    func startCaptureOnly()
    func refreshPermissions() async
    func performPermissionAction(
        _ requirement: SetupRequirement
    ) async
    func bootstrap(completingSetup: Bool) async
    func factoryReset() async throws

    func setAudioRetentionDays(_ days: Int)
    func setInputRefinementEnabled(_ enabled: Bool)
    func setPersonalMemoryEnabled(_ enabled: Bool)
    func setCorrectionSuggestionsEnabled(_ enabled: Bool)
    func setExpressionLearningEnabled(_ enabled: Bool)
    func setSoundFeedbackEnabled(_ enabled: Bool)
    func setCaptureShortcut(_ shortcut: CaptureShortcut)
    func setICloudSyncEnabled(_ enabled: Bool)
    func refreshICloudSyncState()
    func clearExpressionProfile()
    func notifyRuntimeOfSharedStateChange()
}
