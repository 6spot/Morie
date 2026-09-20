import Combine
import Foundation

@MainActor
final class AppPreferencesController: ObservableObject {
    @Published var captureShortcut: CaptureShortcut
    @Published var audioRetentionDays: Int
    @Published var inputRefinementEnabled: Bool
    @Published var personalMemoryEnabled: Bool
    @Published var correctionSuggestionsEnabled: Bool
    @Published var expressionLearningEnabled: Bool
    @Published var soundFeedbackEnabled: Bool
    @Published var iCloudSyncEnabled: Bool
    @Published var iCloudSyncState: ICloudSyncState

    init(
        captureShortcut: CaptureShortcut,
        audioRetentionDays: Int,
        inputRefinementEnabled: Bool,
        personalMemoryEnabled: Bool,
        correctionSuggestionsEnabled: Bool,
        expressionLearningEnabled: Bool,
        soundFeedbackEnabled: Bool,
        iCloudSyncEnabled: Bool,
        iCloudSyncState: ICloudSyncState
    ) {
        self.captureShortcut = captureShortcut
        self.audioRetentionDays = audioRetentionDays
        self.inputRefinementEnabled = inputRefinementEnabled
        self.personalMemoryEnabled = personalMemoryEnabled
        self.correctionSuggestionsEnabled = correctionSuggestionsEnabled
        self.expressionLearningEnabled = expressionLearningEnabled
        self.soundFeedbackEnabled = soundFeedbackEnabled
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.iCloudSyncState = iCloudSyncState
    }
}
