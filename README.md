# Morie

Morie is an Apple-native voice-input product that learns useful personal context from everyday communication.

## Current direction

- **One Mac first:** finish reliable input, a custom dictionary, independent AI cleanup and automatic personal Memory before cross-device work.
- **Latest Apple only:** macOS 27+ on Apple Intelligence-capable Macs, using Swift and Apple system frameworks/components.
- **Capture first:** save intentional input before AI processing; save final text before insertion and Memory analysis.
- **Expression first:** preserve meaning and tone. Cleanup never answers, summarizes or adds information to what the user said.
- **Dictionary and Memory are separate:** the dictionary specifies words and spellings; personal Memory learns projects, relationships, preferences, facts and decisions.
- **Private Mode:** local Apple intelligence with no Morie backend. iCloud/CloudKit belongs to a later cross-device milestone and uses each user's own private database. It is outside the current milestone; iOS and mobile inspiration follow-up are unscheduled.
- **Development stage:** implement the current design directly, with no legacy schemas, migration layers or compatibility shims.

## Current development status

[M-009](docs/tasks/M-009-macos-input-memory.md) integrates the single-Mac loop:

`record → durable recognition → dictionary + optional AI cleanup → durable final text → insertion → idle personal-Memory learning`

The app includes native toggle capture, Apple Speech, focus restoration, clipboard/paste delivery, source-audio recovery and a system management window for **历史记录 / 字典 / 个人记忆 / 诊断**, plus a shared native **设置** window. Each dictionary entry saves one word, supplying native Speech hints and consistent case/width spelling independently of AI cleanup. Basic cleanup works with an empty Memory store.

Personal Memory analyzes saved final input during idle time, retains exact source snapshots and retries unfinished work. New voice input takes priority. Memories appear automatically; users can inspect, correct, archive or delete them without processing a confirmation inbox.

An independent, default-off setting offers to remember a word after the user corrects recently inserted Morie text. A native nonactivating prompt saves the correct spelling only after **加入字典**; an automatic global replacement alias is never created. See the [OpenLess behavior reference](docs/reference/openless.md).

Isolated logic tests and compilation cover the implementation. Real-model quality/latency, cross-app correction prompts, microphone/recovery interactions, keyboard/VoiceOver and system-material acceptance remain open. The owner deferred interactive validation until the evening of 2026-09-18; it has not been waived. M-002/M-003/M-004/M-005/M-008/M-009/M-010/M-011 remain `IN PROGRESS` for their outstanding acceptance items.

[M-010](docs/tasks/M-010-macos-native-setup.md) adds Simplified Chinese as the primary interface language, a native menu-bar menu, Command-comma Settings, native sidebar visibility/group folding, and a device/permission setup window. First use opens the guide; permission prompts require explicit actions. Returning from System Settings only refreshes status and never interrupts capture.

[M-011](docs/tasks/M-011-simple-dictionary.md) simplifies the dictionary to one **词语** field. Add a name or term and save; no aliases or replacement rules are configured. Correction suggestions use the same word-only storage.

## Run locally

1. Use macOS 27+ on an Apple Intelligence-capable Mac and open `Morie.xcodeproj` in the current Xcode.
2. Configure signing if Xcode requests it and run Morie. In **使用引导与权限**, review device capabilities and authorize **麦克风 / 语音识别 / 辅助功能**. Click **开始使用** after every requirement passes; Morie then prepares Speech assets and enables recording.
3. Place the caret in another app, press and release **Fn / 地球仪**, speak, then release Fn again to finish. **Esc** cancels. **⌘,** opens native **设置**, where alternate recording shortcuts are available.
4. Open **字典 → 添加词语**, enter a name or term in **词语**, then click **添加**. Use **编辑词语** to change it later.
5. **设置 → 自动润色语音输入** defaults to on. The [cleanup contract](docs/input-cleanup.md) preserves intent, meaningful emphasis and uncertainty while removing speech redundancy and organizing clear structure.
6. Inspect **历史记录 → 最终文字 / 识别与润色** for saved output, original input and processing context. **原始录音** offers native playback and explicit re-recognition.
7. **个人记忆** fills automatically from completed current-app input. History shows learning status and the final-text snapshot; management actions remain optional.
8. To try correction learning, enable **设置 → 修改输入后建议加入字典**. Correct a word in recently inserted text and pause. Supported fields can show **加入字典 / 暂不添加** without interrupting typing.
9. Use the system sidebar toolbar/View command to show or hide navigation, and the **资料库 / 应用** disclosure controls to fold groups. The native menu-bar menu provides **打开 Morie / 设置… / 使用引导与权限… / 退出 Morie**.

The existing **历史记录 → 开始录音** action remains available for saved-only recordings; its inspiration/follow-up experience is not being expanded in this milestone.

## Documentation

- [Documentation index](docs/README.md)
- [Product and architecture baseline](docs/product-architecture-baseline.md)
- [Architecture](docs/architecture.md)
- [Task overview](docs/tasks.md)
- [Development guide](docs/development.md)
- [Validation matrix](docs/validation.md)
- [Deployment guide](docs/deployment.md)
- [Contributor rules](AGENTS.md)

Development uses feature branches and pull requests.
