import XCTest

@MainActor
final class CaptureHUDTests: XCTestCase {
    func testHUDModelHasNoLiveWaveformBeforeOrAfterRecording() {
        let model = CaptureHUDModel()
        XCTAssertEqual(model.phase, .hidden)

        model.beginRecording()
        model.updateAudioLevel(0.75)
        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.audioLevel.current, 0.75)

        model.hide()
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertEqual(model.audioLevel.current, 0)
    }
}
