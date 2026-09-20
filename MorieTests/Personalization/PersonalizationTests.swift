import Foundation
import SwiftData
import XCTest

@MainActor
final class PersonalizationTests: XCTestCase {
    func testRefinementModelControllerDoesNotReadKeychainUntilExternalRefinementNeedsIt() {
        var credentialReads = 0
        let controller = RefinementModelController(
            load: {
                RefinementModelConfiguration(
                    mode: .cloud,
                    cloudBaseURL: "https://example.com/v1",
                    cloudModelName: "test-model",
                    cloudAPIKey: "must-not-be-loaded"
                )
            },
            credentialReader: {
                credentialReads += 1
                return "runtime-secret"
            }
        )

        XCTAssertEqual(credentialReads, 0)
        XCTAssertEqual(controller.configuration.cloudAPIKey, "")

        let frozen = controller.configuration
        XCTAssertEqual(credentialReads, 0)

        let first = controller.runtimeConfiguration(for: frozen)
        XCTAssertEqual(credentialReads, 1)
        XCTAssertEqual(first.cloudAPIKey, "runtime-secret")

        let second = controller.runtimeConfiguration(for: frozen)
        XCTAssertEqual(credentialReads, 1)
        XCTAssertEqual(second.cloudAPIKey, "runtime-secret")
    }

    func testLocalRefinementNeverReadsExternalCredential() {
        var credentialReads = 0
        let controller = RefinementModelController(
            load: {
                RefinementModelConfiguration(
                    mode: .local,
                    cloudBaseURL: "https://example.com/v1",
                    cloudModelName: "test-model",
                    cloudAPIKey: ""
                )
            },
            credentialReader: {
                credentialReads += 1
                return "unused"
            }
        )

        let frozen = controller.configuration
        XCTAssertEqual(controller.runtimeConfiguration(for: frozen).mode, .local)
        XCTAssertEqual(credentialReads, 0)
    }

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

    func testCleanupValidationKeepsShortCorrectionsButRejectsUngroundedNewSentences() throws {
        let input = RefinementInput(captureID: UUID(), text: "我觉得可能周四吧")
        XCTAssertEqual(try ValidatedRefinement.accepting("周四。", for: input).text, "周四。")
        XCTAssertThrowsError(
            try ValidatedRefinement.accepting("这是模型给出的完整新表达。", for: input)
        )
        XCTAssertThrowsError(try ValidatedRefinement.accepting("   ", for: input))
        XCTAssertThrowsError(try ValidatedRefinement.accepting("无效\0文本", for: input))
    }

    func testCleanupValidationRejectsDictionaryPrimedHallucinatedSentence() throws {
        let input = RefinementInput(
            captureID: UUID(),
            text: "这几个分段我也没测试，这是我自己手动分的段嗯。"
        )

        XCTAssertThrowsError(
            try ValidatedRefinement.accepting(
                "这几个分段我也没测试，这是我自己手动分的段。\n\nGitHub 里有 issues。",
                for: input
            )
        )
        XCTAssertEqual(
            try ValidatedRefinement.accepting(
                "这几个分段我也没测试，这是我自己手动分的段。",
                for: input
            ).text,
            "这几个分段我也没测试，这是我自己手动分的段。"
        )
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
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 最高优先级：只整理原文"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("润色不是重写，更不是扩写"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("spellingCandidates"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("只能用于修正对应词"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("personalContext"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("不能把记忆里的事实"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("semanticParagraphs"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("explicitList"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("不按固定字数机械切段"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("9:00 整理为 9点"))
        XCTAssertFalse(InputRefiner.instructionsText.contains("GitHub"))
        XCTAssertFalse(InputRefiner.instructionsText.contains("Issues"))
        XCTAssertFalse(InputRefiner.instructionsText.contains("Gethab"))
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
            corrections: [
                DictionaryCorrectionSnapshot(
                    id: UUID(),
                    original: "Athers",
                    replacement: "Issues",
                    updatedAt: updatedAt
                )
            ],
            expressionStyle: ["倾向保留句末标点。"]
        )

        let prompt = try InputRefiner.promptText(for: input)
        XCTAssertTrue(prompt.contains(#""formattingHint":"compact""#))
        XCTAssertTrue(prompt.contains(#""spellingCandidates":["GitHub"]"#))
        XCTAssertFalse(prompt.contains("confirmedCorrections"))
        XCTAssertFalse(prompt.contains("Athers"))
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

    func testFormattingHintKeepsShortSingleTopicInputCompact() {
        XCTAssertEqual(
            InputRefiner.formattingHint(for: "这个按钮放左边，这个按钮后面的时间保留。"),
            "compact"
        )
    }

    func testFormattingHintDetectsExplicitEnumeration() {
        XCTAssertEqual(
            InputRefiner.formattingHint(for: "今天三件事，第一修登录问题，第二看 issue，第三打包测试。"),
            "explicitList"
        )
    }

    func testFormattingHintDetectsLongMultiTopicVoiceInput() {
        let text = "目前我们在其他地方已经完成了一部分，你可以看一下最新代码，然后确认现在还有哪些需要改进。尤其我觉得现在需要加一个录音提示音，开始和结束最好都有声音，不然只有动画用户感知比较弱。然后这是我刚才语音口述的，我感觉现在的分段还是不太理想，想确认这一整段有没有必要整理后拆段，还是主要是我的描述比较散。"
        XCTAssertEqual(InputRefiner.formattingHint(for: text), "semanticParagraphs")
    }
    func testFormattingHintDetectsNaturalSpokenEnumerationWithoutOrdinals() {
        XCTAssertEqual(
            InputRefiner.formattingHint(
                for: "现在有三个问题，一个是首次提示音有点破，另一个是胶囊的玻璃效果不明显，还有一个是思考动画会重复。"
            ),
            "explicitList"
        )
        XCTAssertEqual(
            InputRefiner.formattingHint(
                for: "我有两个改动，一个是提示音需要再轻一点，另一个是胶囊需要恢复原生玻璃效果。"
            ),
            "explicitList"
        )
    }

    func testFormattingHintDetectsShortButClearSemanticShift() {
        let text = "我们上次参考了另外两个项目，我觉得现在提示词写得比之前都好，这是真的。但是有一个问题，它漏了一点：有规律的内容还是没有按结构排版。"
        XCTAssertEqual(InputRefiner.formattingHint(for: text), "semanticParagraphs")
    }

    func testFormattingHintDoesNotSplitOrdinaryShortContrast() {
        XCTAssertEqual(
            InputRefiner.formattingHint(for: "这个按钮颜色可以，但是大小不用改。"),
            "compact"
        )
    }

    func testFormattingInstructionsRequireStructuredLayoutWhenHinted() {
        XCTAssertTrue(InputRefiner.instructionsText.contains("# 排版（必须执行）"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("必须把每一项独立成行"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("1. / 2. / 3."))
        XCTAssertTrue(InputRefiner.instructionsText.contains("必须在主题 / 事件 / 请求 / 立场转换"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("不能因为保守而被压回一个自然段"))
    }
    func testConfirmedCorrectionPreparesTextBeforeOptionalModelCleanup() throws {
        let correction = DictionaryCorrectionSnapshot(
            id: UUID(),
            original: "Athers",
            replacement: "Issues",
            updatedAt: Date()
        )
        let input = RefinementInput(
            captureID: UUID(),
            text: "GitHub 里的 Athers 可以关闭了",
            corrections: [correction]
        )

        XCTAssertEqual(input.prepared.text, "GitHub 里的 Issues 可以关闭了")
        XCTAssertEqual(input.prepared.edits.first?.correctionRuleID, correction.id)
    }

    func testDictionaryNormalizesSavedSpellingBeforeCleanupWithoutMemory() throws {
        let input = request("嗯 今天不要发布 morie 2.0")
        XCTAssertEqual(input.prepared.text, "嗯 今天不要发布 Morie 2.0")
        let result = try ValidatedRefinement.accepting("嗯，今天不要发布 Morie 2.0。", for: input)
        XCTAssertEqual(result.edits.first?.dictionaryEntryID, input.dictionary.first?.id)
        XCTAssertEqual(result.text, "嗯，今天不要发布 Morie 2.0。")
    }

    func testPersonalMemoryIsPromptContextAndCannotInjectUnspokenContent() throws {
        let memory = MemorySnapshot(id: UUID(), kind: .fact, status: .active, name: "职业", notes: "我是开发者。", origin: .automatic, updatedAt: Date())
        let input = RefinementInput(captureID: UUID(), text: "开始吧", context: [MemoryContextMatch(memory: memory, matchedTerm: "职业")])

        XCTAssertThrowsError(try ValidatedRefinement.accepting("我是开发者，开始吧。", for: input)) { error in
            XCTAssertEqual(error as? RefinementReason, .invalidEdits)
        }
        XCTAssertTrue(InputRefiner.instructionsText.contains("personalContext"))
        XCTAssertTrue(InputRefiner.instructionsText.contains("不能把记忆里的事实"))
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
        let saved = try await fixture.saved(id)
        let refinement = try XCTUnwrap(saved.refinement)
        XCTAssertTrue(refinement.input.expressionStyle.contains("倾向保留句末标点。"))
    }

    func testDisabledOrBusyCleanupStillAppliesDictionaryWithoutInvokingModel() async throws {
        for enabled in [false, true] {
            let fixture = try RefinementFixture()
            _ = try fixture.addWord()
            let id = try fixture.capture("morie is my project")
            let runner = InputRefinementRunner { _ in XCTFail("Model must not start"); return "invalid" }
            let result = try await fixture.personalizer(runner).refine(id, enabled: enabled, otherModelWorkActive: enabled)
            XCTAssertEqual(result, "Morie is my project")
            let saved = try await fixture.saved(id)
            XCTAssertEqual(saved.refinement?.reason, enabled ? .modelBusy : .disabled)
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
            let saved = try await fixture.saved(id)
            XCTAssertEqual(saved.refinement?.reason, invalidPayload ? .invalidEdits : .generationFailed)
            XCTAssertFalse(saved.refinement?.reason?.message.contains("PRIVATE") == true)
        }
    }

    func testUngroundedGeneratedContentIsRejectedAndOriginalIsKept() async throws {
        let fixture = try RefinementFixture()
        let id = try fixture.capture("原始文字")
        let generated = "Foundation Models 给出的结构化结果。"
        let result = try await fixture.personalizer(InputRefinementRunner { _ in generated }).refine(id, enabled: true)

        XCTAssertEqual(result, "原始文字")
        let saved = try await fixture.saved(id)
        XCTAssertEqual(saved.finalText, "原始文字")
        XCTAssertEqual(saved.refinement?.status, .failed)
        XCTAssertEqual(saved.refinement?.reason, .invalidEdits)
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
        let saved = try await fixture.saved(id)
        XCTAssertEqual(saved.refinement?.reason, .dictionaryChanged)
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
        let saved = try await fixture.saved(id)
        XCTAssertEqual(saved.refinement?.reason, .memoryChanged)
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
        let saved = try await fixture.saved(id)
        XCTAssertEqual(saved.finalText, "Saved input.")
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
        let interrupted = try await fixture.saved(id)
        XCTAssertEqual(interrupted.refinement?.status, .interrupted)
        await model.finish("Saved input.")
        await runner.waitForModelToFinish()
        let settled = try await fixture.saved(id)
        XCTAssertEqual(settled.finalText, "saved input")
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
