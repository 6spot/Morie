import Foundation
import SwiftData
import XCTest

@MainActor
final class PersonalizationTests: XCTestCase {
    func testBasicCleanupRemovesFillerAndFormatsExistingStructureWithoutMemory() throws {
        let cases = [
            ("嗯 我我今天想说的就是说先做设置", "我今天想说先做设置。"),
            ("先打开设置 然后选择字典 最后添加词条", "1. 打开设置\n2. 选择字典\n3. 添加词条"),
            ("okay  keep this", "Okay, keep this."), ("好的", "好的。"), ("真的!", "真的！"),
            ("周三，不，周四开会", "周四开会。"),
            ("15，不，16个", "16个。")
        ]
        for (before, after) in cases {
            let input = RefinementInput(captureID: UUID(), text: before)
            XCTAssertEqual(try ValidatedRefinement.accepting(after, for: input).text, after)
        }
    }

    func testStructuredModelTextIsTrustedWithoutMechanicalContentChecks() throws {
        let input = RefinementInput(captureID: UUID(), text: "我觉得可能周四吧")
        XCTAssertEqual(try ValidatedRefinement.accepting("周四。", for: input).text, "周四。")
        XCTAssertEqual(try ValidatedRefinement.accepting("这是模型给出的完整新表达。", for: input).text, "这是模型给出的完整新表达。")
        XCTAssertThrowsError(try ValidatedRefinement.accepting("   ", for: input))
        XCTAssertThrowsError(try ValidatedRefinement.accepting("无效\0文本", for: input))
    }

    func testContextualChineseRecognitionCorrectionUsesContextInsteadOfACharacterLimit() throws {
        let input = RefinementInput(captureID: UUID(), text: "我再次尝试常文字效果怎么样？")
        XCTAssertEqual(
            try ValidatedRefinement.accepting("我再次尝试长文字效果怎么样？", for: input).text,
            "我再次尝试长文字效果怎么样？"
        )
        XCTAssertEqual(
            try ValidatedRefinement.accepting(
                "现在我再来试一试长文字，看看怎么样。",
                for: request("现在我再来试一试长蚊子，看看怎么样。")
            ).text,
            "现在我再来试一试长文字，看看怎么样。"
        )
        XCTAssertEqual(
            try ValidatedRefinement.accepting(
                "我们明天去公园。",
                for: request("窝门鸣添曲工圆。")
            ).text,
            "我们明天去公园。"
        )
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 任务目标"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 绝对边界"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 口语整理"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 自然格式"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 结构与语境"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("Gethab"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("GitHub"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("界面标签"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("标点整理是必做项"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("不得新增用户没有说过"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("原文没有，就不能出现在输出里"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("9:00 → 9点"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("同一词在后续分句中再次指代对象"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("非正式内容以自然表达为主"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("明显中途改口 / 句子重启"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("废弃半句"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("中文、英文或中英文混合"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("当前输入本身没有指向某条记忆时忽略它"))
        XCTAssertFalse(InputRefiner.instructionsText.contains("已输入我觉得有必要存在吗"))
        XCTAssertFalse(InputRefiner.instructionsText.contains("授权的时候我们的窗口授权完之后"))
    }

    func testFalseStartCleanupCanKeepFinalCompleteRestartWithoutMechanicalRule() throws {
        let input = RefinementInput(
            captureID: UUID(),
            text: "这个功能要让他就是先，算了我重新说，让这个功能只在当前窗口生效"
        )
        XCTAssertEqual(
            try ValidatedRefinement.accepting(
                "让这个功能只在当前窗口生效。",
                for: input
            ).text,
            "让这个功能只在当前窗口生效。"
        )

        let independent = RefinementInput(
            captureID: UUID(),
            text: "先保存当前内容，然后重新打开窗口"
        )
        XCTAssertEqual(
            try ValidatedRefinement.accepting(
                "先保存当前内容，然后重新打开窗口。",
                for: independent
            ).text,
            "先保存当前内容，然后重新打开窗口。"
        )
    }

    func testModelPromptSendsOnlyDictionaryWordsAndUsefulMemoryText() throws {
        let dictionaryID = UUID()
        let memoryID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let input = RefinementInput(
            captureID: UUID(),
            text: "Gethab is where Morie lives",
            context: [
                MemoryContextMatch(
                    memory: MemorySnapshot(
                        id: memoryID,
                        kind: .project,
                        status: .active,
                        name: "Morie",
                        notes: "Morie is a voice input project.",
                        origin: .automatic,
                        updatedAt: updatedAt
                    ),
                    matchedTerm: "Morie"
                )
            ],
            dictionary: [
                DictionarySnapshot(id: dictionaryID, name: "GitHub", updatedAt: updatedAt)
            ],
            expressionStyle: ["倾向保留句末标点。"]
        )

        let prompt = try InputRefiner.promptText(for: input)
        XCTAssertTrue(prompt.contains(#""dictionary":["GitHub"]"#))
        XCTAssertTrue(prompt.contains(#""name":"Morie""#))
        XCTAssertTrue(prompt.contains(#""notes":"Morie is a voice input project.""#))
        XCTAssertTrue(prompt.contains(#""expressionStyle":["倾向保留句末标点。"]"#))
        XCTAssertFalse(prompt.contains(dictionaryID.uuidString))
        XCTAssertFalse(prompt.contains(memoryID.uuidString))
        XCTAssertFalse(prompt.contains("updatedAt"))
        XCTAssertFalse(prompt.contains("matchedTerm"))
        XCTAssertFalse(prompt.contains("origin"))
        XCTAssertFalse(prompt.contains("status"))
        XCTAssertFalse(prompt.contains("kind"))
    }

    func testDictionaryNormalizesSavedSpellingBeforeCleanupWithoutMemory() throws {
        let input = request("嗯 今天不要发布 morie 2.0")
        XCTAssertEqual(input.prepared.text, "嗯 今天不要发布 Morie 2.0")
        let result = try ValidatedRefinement.accepting("嗯，今天不要发布 Morie 2.0。", for: input)
        XCTAssertEqual(result.edits.first?.dictionaryEntryID, input.dictionary.first?.id)
        XCTAssertEqual(result.text, "嗯，今天不要发布 Morie 2.0。")
    }

    func testPersonalMemoryIsPromptContextRatherThanALocalOutputFilter() throws {
        let memory = MemorySnapshot(id: UUID(), kind: .fact, status: .active, name: "职业", notes: "我是开发者。", origin: .automatic, updatedAt: Date())
        let input = RefinementInput(captureID: UUID(), text: "开始吧", context: [MemoryContextMatch(memory: memory, matchedTerm: "职业")])
        XCTAssertEqual(try ValidatedRefinement.accepting("我是开发者，开始吧。", for: input).text, "我是开发者，开始吧。")
        XCTAssertTrue(InputRefiner.instructionsText.contains("个人记忆仅用于理解当前表达"))
    }

    func testRefinementUsesLiveStateAndFlushMakesResultDurable() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("morie is my project", mode: .currentApp)
        let dictionaryID = try fixture.addWord()
        let runner = InputRefinementRunner { input in
            XCTAssertEqual(input.dictionary.map(\.id), [dictionaryID])
            XCTAssertEqual(input.prepared.text, "Morie is my project")
            XCTAssertTrue(input.context.isEmpty)
            return "Morie is my project."
        }

        let result = try await fixture.personalizer(runner).refine(id, enabled: true)
        let live = try fixture.store.capture(id)
        XCTAssertEqual(result, "Morie is my project.")
        XCTAssertEqual(live.finalText, result)
        XCTAssertEqual(live.recognizedText, "morie is my project")
        XCTAssertEqual(live.refinement?.input.dictionary.map(\.id), [dictionaryID])

        let durable = try await fixture.saved(id)
        XCTAssertEqual(durable.finalText, result)
        XCTAssertEqual(durable.refinement?.status, .applied)

        try fixture.store.markDelivered(
            id,
            applicationName: "Test",
            bundleIdentifier: "me.morie.tests"
        )
        try await fixture.store.flushPersistence(for: id)
        try fixture.memory.enqueueCompletedInput(captureID: id)
        XCTAssertEqual(try fixture.memory.analysisSource(for: id).text, result)
    }

    func testStableExpressionProfileIsIncludedInCleanupAndSavedProvenance() async throws {
        let fixture = try RefinementFixture()
        let profile = ExpressionProfileStore(container: fixture.store.container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<10 {
            try profile.record(
                injected: "今天我们继续测试Morie这个输入功能",
                edited: "今天我们继续测试 Morie 这个输入功能。",
                at: start.addingTimeInterval(Double(index) * 12 * 60 * 60)
            )
        }

        let id = try fixture.capture("今天继续测试 Morie")
        let result = try await fixture.personalizer(
            InputRefinementRunner { input in
                XCTAssertTrue(input.expressionStyle.contains("倾向保留句末标点。"))
                return "今天继续测试 Morie。"
            },
            expressionProfile: profile
        ).refine(id, enabled: true, expressionStyleEnabled: true)

        XCTAssertEqual(result, "今天继续测试 Morie。")
        XCTAssertTrue(
            try XCTUnwrap((try await fixture.saved(id)).refinement)
                .input.expressionStyle.contains("倾向保留句末标点。")
        )
    }

    func testDisabledOrBusyCleanupStillAppliesDictionaryWithoutInvokingModel() async throws {
        for enabled in [false, true] {
            let fixture = try RefinementFixture()
            _ = try fixture.addWord()
            let id = try fixture.capture("morie is my project")
            let runner = InputRefinementRunner { _ in XCTFail("Model must not start"); return "invalid" }
            let result = try await fixture.personalizer(runner).refine(id, enabled: enabled, otherModelWorkActive: enabled)
            XCTAssertEqual(result, "Morie is my project")
            XCTAssertEqual((try await fixture.saved(id)).refinement?.reason, enabled ? .modelBusy : .disabled)
        }
    }

    func testEmptyMemoryStillAllowsUsefulCleanup() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("嗯 我我想先做设置")
        let result = try await fixture.personalizer(InputRefinementRunner { input in
            XCTAssertTrue(input.context.isEmpty)
            return "我想先做设置。"
        }).refine(id, enabled: true)
        XCTAssertEqual(result, "我想先做设置。")
    }

    func testCleanupUsesAtMostFourRelevantMemoryItems() async throws {
        let fixture = try RefinementFixture()
        let names = (0..<6).map { "Topic\($0)" }
        for name in names {
            _ = try fixture.memory.create(MemoryDraft(kind: .project, name: name, notes: "关于 \(name) 的个人项目。"))
        }
        let id = try fixture.capture(names.joined(separator: " "))
        let result = try await fixture.personalizer(InputRefinementRunner { input in
            XCTAssertEqual(input.context.count, 4)
            XCTAssertTrue(Set(input.context.map(\.memory.name)).isSubset(of: Set(names)))
            return input.prepared.text
        }).refine(id, enabled: true)
        XCTAssertEqual(result, names.joined(separator: " "))
    }

    func testModelErrorsAndInvalidPayloadPreserveDictionaryTextWithoutPrivateErrorDetails() async throws {
        let fixture = try RefinementFixture()
        _ = try fixture.addWord()
        for invalidPayload in [false, true] {
            let id = try fixture.capture("morie is my project")
            let runner = InputRefinementRunner { _ in
                if invalidPayload { return "   " }
                throw NSError(domain: "PRIVATE MODEL INPUT", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE MODEL INPUT"])
            }
            let result = try await fixture.personalizer(runner).refine(id, enabled: true)
            XCTAssertEqual(result, "Morie is my project")
            XCTAssertEqual((try await fixture.saved(id)).refinement?.reason, invalidPayload ? .invalidEdits : .generationFailed)
            XCTAssertFalse((try await fixture.saved(id)).refinement?.reason?.message.contains("PRIVATE") == true)
        }
    }

    func testGeneratedContentIsSavedWithoutLocalSemanticRejection() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("原始文字")
        let generated = "Foundation Models 给出的结构化结果。"
        let result = try await fixture.personalizer(InputRefinementRunner { _ in generated }).refine(id, enabled: true)
        XCTAssertEqual(result, generated)
        XCTAssertEqual((try await fixture.saved(id)).refinement?.status, .applied)
    }

    func testSavedFinalAndInputSnapshotsSurviveSpeechRetryAndRestart() async throws {
        let fixture = try RefinementFixture()
        _ = try fixture.addWord()
        let id = try fixture.capture("morie is my project")
        _ = try await fixture.personalizer(InputRefinementRunner { _ in "Morie is my project." }).refine(id, enabled: true)
        try await fixture.store.flushPersistence(for: id)
        fixture.store.releaseCaptureOwnership(id)
        try fixture.store.saveReRecognition("different later recognition", for: id)
        let reopened = try CaptureStore(storageURL: fixture.storageURL)
        let record = try reopened.capture(id)
        XCTAssertEqual(record.finalText, "Morie is my project.")
        XCTAssertEqual(record.recognizedText, "different later recognition")
        XCTAssertEqual(record.refinement?.input.text, "morie is my project")
    }

    func testRefinementRejectsUnsavedSourceAndLatePartials() throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("saved input")
        try fixture.store.updateRecognizedText("late partial", for: id)
        XCTAssertEqual(try fixture.store.capture(id).recognizedText, "saved input")
        try fixture.store.capture(id).finalText = "unsaved input"
        XCTAssertThrowsError(try fixture.store.refinementInput(for: id, context: []))
    }

    func testRestartClearsRunningRefinementWithoutInferenceOrDelivery() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("saved input", mode: .currentApp)
        try fixture.store.beginRefinement(fixture.store.refinementInput(for: id, context: []))
        try await fixture.store.flushPersistence(for: id)
        let reopened = try CaptureStore(storageURL: fixture.storageURL)
        let capture = try reopened.capture(id)
        XCTAssertEqual(capture.refinement?.status, .interrupted)
        XCTAssertEqual(capture.finalText, "saved input")
        XCTAssertNotEqual(capture.lifecycle, .delivered)
    }

    func testRunningRefinementBlocksHistoryMutation() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("saved input")
        let model = PendingCleanup()
        let work = Task { try await fixture.personalizer(InputRefinementRunner(generate: { try await model.run($0) })).refine(id, enabled: true) }
        await waitUntilStarted(model)
        XCTAssertThrowsError(try fixture.store.saveReRecognition("new text", for: id))
        XCTAssertThrowsError(try fixture.store.deleteCapture(id))
        await model.finish("saved input")
        _ = try await work.value
    }

    func testDictionaryChangedDuringModelCannotApplyStaleCorrection() async throws {
        let fixture = try RefinementFixture()
        let dictionaryID = try fixture.addWord()
        let id = try fixture.capture("morie is my project")
        let model = PendingCleanup()
        let work = Task { try await fixture.personalizer(InputRefinementRunner(generate: { try await model.run($0) })).refine(id, enabled: true) }
        await waitUntilStarted(model)
        try fixture.dictionary.delete(dictionaryID)
        await model.finish("Morie is my project.")
        let result = try await work.value
        XCTAssertEqual(result, "morie is my project")
        XCTAssertEqual((try await fixture.saved(id)).refinement?.reason, .dictionaryChanged)
    }

    func testMemoryEditedDuringModelDoesNotApplyStaleContext() async throws {
        let fixture = try RefinementFixture()
        let memoryID = try fixture.memory.create(MemoryDraft(kind: .project, name: "Morie", notes: "I work on Morie."))
        let id = try fixture.capture("Morie is my project")
        let model = PendingCleanup()
        let work = Task { try await fixture.personalizer(InputRefinementRunner(generate: { try await model.run($0) })).refine(id, enabled: true) }
        await waitUntilStarted(model)
        try fixture.memory.archive(memoryID)
        await model.finish("Morie is my project.")
        let result = try await work.value
        XCTAssertEqual(result, "Morie is my project")
        XCTAssertEqual((try await fixture.saved(id)).refinement?.reason, .memoryChanged)
    }

    func testRefinementWaitsForModelWithoutAnArbitraryDeadline() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("saved input")
        let model = PendingCleanup()
        let runner = InputRefinementRunner(generate: { try await model.run($0) })
        let work = Task { try await fixture.personalizer(runner).refine(id, enabled: true) }
        await waitUntilStarted(model)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(runner.isBusy)
        await model.finish("Saved input.")
        let result = try await work.value
        XCTAssertEqual(result, "Saved input.")
        XCTAssertFalse(runner.isBusy)
        XCTAssertEqual((try await fixture.saved(id)).finalText, "Saved input.")
    }

    func testCallerCancellationDoesNotWaitForModelOrReturnDeliverableText() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("saved input")
        let model = PendingCleanup()
        let runner = InputRefinementRunner(generate: { try await model.run($0) })
        let work = Task { try await fixture.personalizer(runner).refine(id, enabled: true) }
        await waitUntilStarted(model)
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled input must not return a deliverable result") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(runner.isBusy)
        XCTAssertEqual((try await fixture.saved(id)).refinement?.status, .interrupted)
        await model.finish("Saved input.")
        await runner.waitForModelToFinish()
        XCTAssertEqual((try await fixture.saved(id)).finalText, "saved input")
    }

    private func request(_ text: String) -> RefinementInput {
        RefinementInput(captureID: UUID(), text: text, dictionary: [DictionarySnapshot(id: UUID(), name: "Morie", updatedAt: Date())])
    }

    private func waitUntilStarted(_ model: PendingCleanup) async {
        for _ in 0..<500 {
            if await model.isWaiting { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Cleanup did not start")
    }
}


@MainActor
private final class RefinementFixture {
    let directory: URL
    let storageURL: URL
    let store: CaptureStore
    let memory: MemoryStore
    let dictionary: DictionaryStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MorieRefinement-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appending(path: "captures.store")
        store = try CaptureStore(storageURL: storageURL)
        memory = MemoryStore(container: store.container)
        dictionary = DictionaryStore(container: store.container)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    func capture(_ text: String, mode: CaptureDeliveryMode = .captureOnly) throws -> UUID {
        let id = UUID()
        _ = try store.beginVoiceCapture(id: id, deliveryMode: mode, applicationName: "Test", bundleIdentifier: nil)
        try store.completeRecognition(text, for: id)
        return id
    }

    func addWord() throws -> UUID { try dictionary.create(DictionaryDraft(name: "Morie")) }

    struct SavedCapture {
        let recognizedText: String
        let finalText: String
        let lifecycle: CaptureLifecycle
        let refinement: CaptureRefinement?
    }

    func saved(_ id: UUID) async throws -> SavedCapture {
        try await store.flushPersistence(for: id)
        let reader = ModelContext(store.container)
        let record = try XCTUnwrap(reader.fetch(FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })).first)
        return SavedCapture(recognizedText: record.recognizedText, finalText: record.finalText, lifecycle: record.lifecycle, refinement: record.refinement)
    }

    func personalizer(
        _ runner: InputRefinementRunner,
        expressionProfile: ExpressionProfileStore? = nil
    ) -> CapturePersonalizer {
        CapturePersonalizer(
            store: store,
            memory: memory,
            dictionary: dictionary,
            expressionProfile: expressionProfile,
            runner: runner
        )
    }
}

private actor PendingCleanup {
    private var continuation: CheckedContinuation<String, Error>?
    var isWaiting: Bool { continuation != nil }
    func run(_ input: RefinementInput) async throws -> String { try await withCheckedThrowingContinuation { continuation = $0 } }
    func finish(_ text: String) { continuation?.resume(returning: text); continuation = nil }
}
