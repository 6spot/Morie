# Apple Native First · Product & Architecture Baseline

**Version:** V0 Baseline v2  
**Date:** 2026-09-17  
**Source:** Project-owner supplied design document, transcribed into the repository for implementation reference.

> This file preserves the approved V0 design baseline in repository-searchable form. Later explicitly approved decisions take precedence where they strengthen or amend the baseline.

## Approved amendments after the source v2 document

The following owner decisions are now hard requirements:

1. **Native UI Only:** Morie UI must use Apple system UI components and the current macOS 27 Liquid Glass design language. “Looks native” is not sufficient; use the native component itself whenever it exists.
2. **No unilateral UI substitution:** if Apple system UI cannot satisfy a requirement, implementation must stop and obtain explicit project-owner approval before creating a custom substitute.
3. **External dependency approval gate:** no third-party package/runtime/model/SDK/UI framework/network service may be introduced without explicit project-owner approval after documenting the Apple-native gap and trade-offs.
4. **Type4Me is an input-foundation reference:** macOS voice input is not a greenfield rewrite. Audit and selectively reuse/adapt proven Type4Me recording-session, hotkey, target/focus, text-injection, Apple Speech, permission, packaging and correction-learning experience. Do not inherit its provider/runtime complexity.
5. **Development stage, no legacy contract (2026-09-18):** implement the current product, schema and Apple APIs directly. Do not add old-version compatibility, legacy data reconstruction, schema migrations or speculative upgrade paths. Current-version crash recovery and Capture-first data protection still apply.
6. **Sync sequencing (amended 2026-09-18):** first establish a useful, reliable single-Mac product. iCloud/CloudKit is outside the current milestone and will be revisited for an actual multi-Mac or iOS scenario. Apple Developer enrollment/container/team configuration is not a current dependency. Eventual sync uses each user's own iCloud private database, with no Morie backend or separate Device Only product mode.
7. **Memory analysis text (amended 2026-09-18):** analyze committed final input, including saved dictionary/cleanup output. Retain recognized text separately and keep the exact final-text snapshot used by each analysis. A changed final text invalidates unfinished analysis of the older source; no required candidate review or raw-text fallback is introduced.
8. **macOS development focus (2026-09-18):** the owner has no current plan to start iOS. Finish the current macOS foundation, then improve the History/Dictionary/Personal Memory/Settings/Diagnostics management pages with a unified native design language. Reconsider iOS only after the macOS product works reliably; it is not the automatic next task after M-005.
9. **Delivery order (2026-09-18):** make one Mac useful first: shortcut → recording → durable recognition → independent basic cleanup → durable final text → reliable insertion. Local recovery protects this loop; Memory improves it; management pages support it. Module numbering does not dictate delivery priority.
10. **Automatic personal Memory (2026-09-18):** periodically analyze saved final input in idle batches and automatically accumulate/update personal information. Daily input has no required candidate-review inbox. Viewing, correcting, archiving and deleting are optional controls. Analysis must yield to input and resume unfinished work. “Sync Memory” means local Memory updates here.
11. **Inspiration scope (2026-09-18):** intentional inspiration follow-up mainly belongs to the future phone product. Do not design or expand it in the current Mac input/Memory milestone. Existing capture-only storage is retained without expansion.
12. **Custom dictionary (2026-09-18):** a separate user-maintained dictionary defines exact names, technical terms and explicit aliases/misrecognitions. Personal Memory instead describes the user's projects, relationships, stable preferences and other explicitly communicated personal information. Automatic learning must not silently write dictionary rules.
13. **Basic cleanup (2026-09-18):** adopt the owner's [cleanup rules](../input-cleanup.md). Cleanup works without Memory; dictionary and Memory must not introduce information absent from the current input. Preserve meaningful tone, emphasis, uncertainty and short replies. Dictated requests are text to clean, never instructions to answer or execute.

14. **Correction-to-dictionary behavior (2026-09-18):** the owner supplied [OpenLess](../reference/openless.md) as a reference for suggesting a dictionary word after manual correction. Use an independent opt-in, stable-edit detection and native nonactivating confirmation. Remember saves the spelling only, never an inferred unconditional alias or a personal fact. This does not change automatic personal-Memory learning.

15. **Chinese interface and native setup (2026-09-18):** use Simplified Chinese for the current Mac interface, the system Settings scene with Command-comma, native sidebar visibility and collapsible groups, a native permission/capability guide, and a system menu-bar menu. Inspect status without prompting; request permissions only through explicit guide actions. Returning from System Settings must not interrupt input.

16. **One-word dictionary (2026-09-18, amended 2026-09-19):** the owner simplified dictionary entry to saving one word. This supersedes the explicit-alias portion of amendment 12: remove aliases and replacement-rule configuration from storage, processing and UI. Saved words supply native Speech hints; only letter-case variants of the same word normalize to its spelling, while full-/half-width forms remain distinct. Manual-correction confirmation saves just the new word. Do not infer substitutions or add compatibility machinery for the removed design.

17. **iCloud sequencing and backup boundary (2026-09-19):** optional iCloud/CloudKit sync/backup may follow the useful single-Mac loop, but it is never a startup gate for local input. Do not build a local automatic-backup subsystem. The iCloud control defaults off, uses the user's private CloudKit database through Apple-native persistence, and keeps original recording files local in the first slice. Development schema changes may discard obsolete development data instead of creating upgrade backups or compatibility migrations.

18. **Current-keyboard-focus delivery (2026-09-19):** M-014 supersedes every source-body reference to Frontmost App capture / Focus Restore as the ordinary input contract. Do not pin a delivery app/window at recording start. When final text is ready, resolve the external current keyboard focus/frontmost application, stage the final text on the clipboard, dispatch one synthetic `Cmd+V`, and restore prior safe clipboard content only when `changeCount` proves no newer clipboard write occurred. Never reactivate the record-start app for ordinary current-app input.

19. **Confirmed correction mappings (2026-09-19):** M-027 supersedes the “spelling only / never any alias” wording in amendments 14 and 16. The visible Dictionary remains canonical-word only and has no alias/replacement-rule configuration. After a bounded verified post-insertion edit and explicit user confirmation, Morie may additionally persist an internal observed-ASR → canonical-word mapping and apply that exact mapping deterministically before optional cleanup. No unconfirmed/broad replacement rule is learned.

20. **Native Speech backend selection (2026-09-19):** prefer Apple's `SpeechTranscriber` when the requested locale/device supports it; keep `DictationTranscriber` only as the Apple-native runtime fallback implemented by Morie when newer backend preparation is unavailable. Do not add cloud/third-party ASR speculatively.

The source document below is historical product direction. These amendments supersede its phase order, immediate iCloud requirement, record-start Focus Restore, spelling-only correction wording, mandatory confirmation and inspiration scope.

See also:

- [`../ui-design.md`](../ui-design.md)
- [`../reference/type4me.md`](../reference/type4me.md)
- [`../../AGENTS.md`](../../AGENTS.md)

---

# 1. 文档目的

本文档用于统一产品定位、V0 范围、Latest Apple Only / Apple Native First 技术策略、macOS-first 开发顺序、Private Mode 边界，以及 Type4Me 的复用范围。

它不是功能愿望清单，而是第一阶段开发的约束基线。

## 一句话定义

一个会记住你的语音输入工具：通过日常语音表达与主动灵感捕捉，逐渐建立属于用户自己的 Personal Memory，并用这些记忆持续提升未来的识别、理解和表达。

# 2. 已确定的关键决策

| 决策项 | 当前选择 | 说明 |
| --- | --- | --- |
| 平台顺序 | macOS 优先 | 先跑通桌面语音输入、Capture 与 Memory 闭环，再进入 iOS。 |
| 客户端技术 | Swift 原生 | macOS / iOS 均使用 Swift 与 Apple Framework；共享逻辑通过 Swift Package 复用。 |
| V0 后端 | Private Mode | Apple Native + iCloud；不建设我们的 Cloud，不提供 Device Only。 |
| 长期存储 | iCloud / CloudKit | 用户自己的 Apple Account 负责跨 Mac / iPhone 的持久化与同步。 |
| AI / ASR | Latest Apple Native | 直接采用当前最新 Speech / FoundationModels / NaturalLanguage 能力，不为旧 API 保留 fallback。 |
| 第三方依赖 | 默认不引入 | Apple 原生无法满足且收益明确、可量化时才进入讨论；当前批准规则进一步要求 owner 明确批准。 |
| Type4Me | Reference Implementation | 抽取成熟输入基础设施，不继承 Provider、Runtime 与旧系统兼容复杂度。 |
| 未来云端 | Rust Server 等 | Private 闭环验证后再建设；Apple 客户端继续保持 Swift 原生。 |

# 3. 产品核心闭环

语音输入与灵感捕捉不是两个产品，而是同一个 Capture 系统的两种使用方式：一种需要把结果交付到当前 App，另一种只需要保存。两者最终都进入同一套 Personal Memory。

```text
Capture
  ↓
Understand
  ↓
Remember
  ↓
Personalize
  ↓
Express Better
  ↓
Capture...
```

## 3.1 两种 Capture 模式

| 模式 | 目标 | 典型入口 |
| --- | --- | --- |
| `currentApp` | 语音识别后注入当前输入框，同时保存 Capture | macOS 全局快捷键 |
| `captureOnly` | 只记录灵感/想法，不向其他 App 输出 | App 内语音或文字记录；未来 iPhone Action Button |

## 3.2 明确的隐私边界

- 不监听用户正常键盘输入。
- 不把系统设计成全局 Keylogger。
- 只有用户主动通过我们的语音输入或 App 内记录产生的内容进入 Capture。
- V0 用户内容不进入我们的服务器。
- Private Mode 有明确能力门槛：若 Apple Intelligence / Foundation Models / Speech / Locale / 模型资产等必要能力不可用，则 Private Mode 不可进入。
- V0 尚无 Cloud，因此设备能力不足时直接不支持；未来 Cloud 上线后可选择 Cloud Mode。

# 4. V0：macOS First

第一阶段只做 macOS，并把最关键的价值链一次跑通。iOS 不与 macOS 并行开发，避免在核心体验尚未验证前引入移动端生命周期、Action Button、AppIntent 等额外变量。

```text
第一次按下快捷键
  ↓
开始录音
  ↓
第二次按下完成（Esc 取消）
  ↓
Apple Speech
  ↓
Final Transcript
  ↓
Capture Durable Save
  ↓
Personal Context 修正 / 轻度整理
  ↓
更新 Final Text 并持久化
  ↓
恢复目标 App / 输入框
  ↓
文本注入
  ↓
记录 Delivery Result
  ↓
Memory 更新
  ↓
下一次输入更准确
```

> Phase 0 先验证“输入基础设施”；Capture Durable Save 从 Phase 1 正式落地。

## 4.1 macOS V0 必须具备

- Menu Bar App 与全局快捷键。
- 可靠的录音 Session：开始、结束、取消、中断、超时与恢复。
- 最新 Apple Speech 能力：Partial / Final transcript、所需模型资产与 Locale 可用性检查。
- Frontmost App / Focus Restore / Accessibility / Text Injection。
- Capture Store 与基础 History。
- App Context：App、Bundle ID、Window Title 等最小上下文。
- 基础 Vocabulary / Project / Memory。
- Memory 反哺下一次专有名词修正与表达整理。
- iCloud / CloudKit 同步。

## 4.2 V0 不做

- 自建 Cloud、账户体系、云端 Memory 服务。
- iOS 客户端。
- Windows / Linux / Android。
- Web 端、团队空间、社交能力。
- MCP / Public API / Relay。
- 复杂 Knowledge Graph / Agent / 自动任务。
- 十几个 ASR Provider 或 LLM Provider。

# 5. Apple Native First 技术原则

## 原则

优先调用已经存在于系统中的能力，而不是把 Runtime、模型、字典和服务端组件打进 App。目标不是“技术栈丰富”，而是小体积、低延迟、低维护成本和深度系统集成。

| 领域 | 方案 | 目标 |
| --- | --- | --- |
| 音频 | AVFoundation | 不自带音频 Runtime |
| 语音识别 | 当前最新 Speech APIs | 直接使用最新系统能力，不维护旧 Speech API fallback |
| 本地智能 | FoundationModels / SystemLanguageModel | Private Mode 必要能力；不可用则 Private Mode 不启动 |
| NLP | NaturalLanguage / NLTokenizer | 避免为了分词引入 C++ / 字典包 |
| 同步 | CloudKit / iCloud | Private Mode 必备；承担 Mac 与未来 iPhone 的长期数据同步 |
| UI | SwiftUI + 必要 AppKit | 使用 Apple 原生体验；当前进一步明确为 macOS 27 Native UI Only + Liquid Glass |
| macOS 输入 | Accessibility / NSPasteboard / AppKit | 当前 App 定位、Focus、注入与 fallback |
| 本地存储 | SwiftData / SQLite 视需求 | 只引入有明确必要性的持久化技术 |

## 5.1 Latest Apple Only

V0 不以“覆盖尽可能多的 Mac”为目标，而是面向当前最新 Apple 平台与支持 Apple Intelligence 的设备开发。

不为旧系统、旧 Speech API 或不具备 Apple Intelligence 的硬件增加兼容层。

工程约束：不为了扩大设备覆盖率，引入替代 Apple 最新原生能力的第三方 Runtime、模型、ASR 引擎或兼容层。

当前平台基线：

- macOS 27+
- Apple Intelligence capable Mac
- 最新稳定 Swift / Xcode
- FoundationModels 与最新 Speech APIs

未来 iOS 也沿用同一原则，以当时最新 Apple 平台能力为基线。

## 5.2 Capability Layer

Capability Layer 不是兼容旧系统的 fallback Router，而是 Private Mode 的启动门槛检查。

App 启动时先确认本地所需能力全部可用，再进入主界面。

启动检查至少包括：

- macOS 版本；
- Apple Intelligence 状态；
- `SystemLanguageModel` availability；
- 支持的 Locale；
- Foundation Models 模型状态；
- Speech 能力与所需模型资产；
- iCloud / CloudKit 可用状态。

Private Mode 规则：

- 必要能力全部满足 → 正常启动；
- 任一关键能力不满足 → Private Mode 不可用；
- V0 直接提示当前设备不支持；
- 未来 Cloud Mode 上线后再提供 Cloud 入口。

## 5.3 外部依赖准入规则

原始 v2 的评估问题：

1. Apple 原生能力是否真的无法满足？
2. 它带来的准确率/性能/稳定性提升是否可以量化？
3. 是否增加 App 体积、启动时间、内存占用或签名/打包复杂度？
4. 是否引入额外 Runtime、动态库、模型文件或网络服务？
5. 未来 Apple API 演进后是否容易删除？

当前批准规则进一步明确：**回答完这些问题仍不能自行引入；必须取得项目 owner 明确批准。**

## 5.4 体积优化的真正来源

```text
小体积
≠ 把 Swift 换成 Rust

小体积
= 不自带大模型
+ 不自带 Python
+ 不自带 ONNX Runtime
+ 不自带无必要的 C/C++ Bridge
+ 不捆绑大词典/多 Provider SDK
+ 最大化使用 Apple System Frameworks
```

## 5.5 Performance Budget

“Apple Native First”必须可测量。V0 建立性能基线与回归门槛，任何新增功能都需要评估它对体积、启动、内存、延迟和能耗的影响。

建议持续记录：

- App Binary Size
- Cold Launch Time
- Idle RSS
- Recording RSS
- ASR Final 延迟
- Final → Deliver 延迟
- CPU / Energy Impact
- Capture Loss Rate

V0 可先建立 baseline，不必一开始写死目标数字。

# 6. 客户端技术架构：纯 Swift

第一阶段只考虑 Apple 用户，客户端不需要 Rust Core、Flutter、Electron 或其他跨平台层。

macOS 与未来 iOS 都使用 Swift；共享业务逻辑通过 Swift Package 复用，平台特有能力留在各自 App Shell。

```text
Apple Workspace
│
├── Packages/
│   ├── PersonalCore
│   │   ├── Capture
│   │   ├── Memory
│   │   ├── Project
│   │   ├── Person
│   │   ├── Vocabulary
│   │   └── Context
│   │
│   ├── AppleIntelligence
│   │   ├── FoundationModels
│   │   ├── NaturalLanguage
│   │   └── Personalization
│   │
│   ├── Persistence
│   │   ├── LocalStore
│   │   └── CloudKit
│   │
│   └── SharedUI
│
├── macOSApp/
│   ├── GlobalHotkey
│   ├── Audio / Speech
│   ├── Accessibility
│   ├── AppContext
│   ├── FocusRestore
│   ├── TextInjection
│   └── MenuBar
│
└── iOSApp/                # 后续阶段
    ├── MobileCapture
    ├── AppIntent
    ├── ActionButton
    └── MobileShell
```

> 目录图表达职责边界，不要求第一天就创建所有 Package。避免为了“架构漂亮”提前拆模块。

## 6.1 哪些可以共用

| 模块 | 策略 |
| --- | --- |
| Capture / Memory / Project / Person / Vocabulary 数据模型 | 共用 |
| Memory Engine / Context Retrieval / Personalization | 共用 |
| FoundationModels / NaturalLanguage 封装 | 大部分共用 |
| CloudKit Repository / 同步语义 | 大部分共用 |
| 通用 SwiftUI 组件 | 大部分共用，但必须使用系统 UI 语义 |
| Speech 抽象与 transcript pipeline | 大部分共用，Audio Session 细节分平台 |
| Accessibility / Text Injection / Global Hotkey | macOS 专属 |
| Action Button / AppIntent / Mobile Shell | iOS 专属 |

# 7. 核心数据模型：Capture First

数据模型不要围绕 Voice 设计，而要围绕 Capture 设计。Voice 只是 Capture 的一种来源，这样未来加入手动文字、Share Sheet 或其他主动入口时不用重做核心模型。

```text
Capture
├── id
├── createdAt
├── type: voice | text
├── content
│   ├── raw
│   ├── recognized
│   └── final
├── source
│   ├── appName
│   ├── bundleId
│   ├── windowTitle
│   └── optionalContext
├── delivery
│   ├── currentApp
│   └── captureOnly
├── context
│   ├── project
│   ├── topic
│   ├── people
│   └── entities
└── memoryState
    ├── journal
    ├── candidate
    └── memory
```

## 可靠性原则

**Capture 必须先可靠保存，再做 AI 整理。任何模型调用、分类或 Memory 提取失败，都不能导致原始 Capture 丢失。**

# 8. Memory 模型

V0 不做复杂知识图谱。先验证“日常表达能否自然沉淀为有用的 Personal Context，并反哺未来表达”。

```text
Capture
  ↓
Journal
  ↓
Memory Candidate
  ↓
Memory
  ↓
Relevant Context
  ↓
下一次语音输入
```

## 8.1 第一阶段 Memory 类型

| 类型 | 示例 |
| --- | --- |
| Project | Loom、Multica |
| Person | 同事、客户、联系人及其上下文 |
| Vocabulary | Mika、GitNexus、ME-203 等专有词 |
| Topic | ASR、Memory、架构 |
| Decision | 某个方案被确认、关闭或替换 |
| Preference | 用户偏好的表达方式或工作习惯 |
| Fact | 项目的稳定事实 |
| Open Thread | 尚未完成、后续需要继续讨论的事项 |
| Writing Style | 句长、语气、常用表达、不同场景风格 |

## 8.2 Memory 的来源与有效性

Memory 不能只是静态 `type + content`。

每条长期 Memory 必须知道：

- 它来自哪些 Capture；
- 当前是否仍有效；
- 是否被后续信息替代。

最小字段建议：

- `sourceCaptureIds`
- `confidence`
- `userConfirmed`
- `createdAt`
- `updatedAt`
- `status(active / superseded / archived)`
- `supersedes`

## 8.3 Memory 的价值判断

不能把所有 Capture 直接永久化为 Knowledge。真正需要优化的是长期信噪比。

```text
100 条 Capture
  ↓
100 条 Journal
  ↓
少量 Memory Candidates
  ↓
更少的长期 Memory
```

目标：越用越懂用户，而不是越用越杂乱。

# 9. Personalization：Memory 必须反哺表达

“存下来”不是产品价值终点。真正的闭环，是历史记忆参与下一次语音输入。

```text
当前 App / Window
      +
Raw Transcript
      +
Recent Context
      ↓
Relevant Memory Retrieval
      ↓
Project / Vocabulary / People / Style
      ↓
Correction / Rewrite
      ↓
Final Text
```

## 目标体验

- 第一天：好用的语音输入。
- 第七天：开始认识用户的专有词。
- 第三十天：开始理解用户的项目、人物与表达方式。

# 10. Type4Me 的角色：参考成熟工程，不继承历史复杂度

Type4Me 对 Morie 最有价值的是“输入基础设施已经踩过的坑”，而不是其不断扩张的 Provider / Runtime 产品形态。

建议在 Morie 独立仓库中按模块迁移或重写，而不是直接 Fork 后大规模删代码。

## 10.1 优先参考 / 迁移

- Audio Capture 与 Recording Session 状态机。
- Global Hotkey。
- Frontmost App Detection。
- Accessibility、Focus Restore、Text Injection、Clipboard fallback。
- Apple ASR、Partial / Final Transcript。
- Hotword / Vocabulary、用户纠错学习。
- IntelliSense 与 ReviseCore 中对个性化输入真正有价值的逻辑。
- Swift Concurrency、权限、签名、打包与异常恢复经验。

当前进一步明确：Phase 0 开发前/开发中必须审计这些 Type4Me 路径，不能把它当成从零工程。

## 10.2 默认不继承

- 大量 Cloud ASR Provider。
- 大量 LLM Provider 与 Provider 设置 UI。
- SenseVoice / sherpa-onnx。
- Qwen3 ASR Server / Python / MLX Runtime。
- Silero VAD（Apple 能力满足时）。
- CppJieba（NaturalLanguage 能满足时）。
- Codex CLI、Pricing Registry、旧 Subscription / Build Variant。

# 11. 开发阶段

| 阶段 | 主题 | 验收结果 | 主要范围 |
| --- | --- | --- | --- |
| Phase 0 | Input Foundation | 按下 → 说话 → 再次按下 → 文本在主流目标 App 中稳定进入当前输入位置 | Type4Me reference audit / Audio / Session / Hotkey / latest Speech / Focus / Injection / Capability Gate / Compatibility Matrix / native macOS 27 UI |
| Phase 1 | Capture | 所有主动表达可可靠沉淀 | Capture Model / Store / App Context / History / iCloud |
| Phase 2 | Memory | 系统开始稳定认识用户的专有词、项目与当前相关上下文 | Vocabulary / Project / Relevant Context Retrieval；Person / Decision / Style 先保留数据模型，不要求一次做完 |
| Phase 3 | Personalization | 历史 Context 明显改善当前表达 | Context-aware Correction / Style / Rewrite / Learning |
| Phase 4 | iOS | 把 iPhone 变成极快的 Capture 入口 | Action Button / AppIntent / Voice & Text Capture / iCloud |
| Later Cloud | 云端增强 | 本地产品验证后再提供增强服务 | Rust Server / Cloud Memory / API / MCP |

## 11.1 当前真正要做的第一件事

### 唯一优先级

先在 macOS 把“语音输入基础设施”跑稳：低延迟、可靠录音、准确 transcript、Focus 恢复、跨常见 App 文本注入。

没有这一层，后面的 Memory 再聪明也没有意义。

## 11.2 Text Injection Compatibility Matrix

Text Injection 是 macOS V0 的核心兼容性风险之一。Phase 0 必须建立真实 App 兼容矩阵，而不是只验证单个输入框。

首批建议覆盖：

- Safari
- Chrome
- 微信
- Slack
- Telegram
- Mail
- Notes
- Xcode
- VS Code / Cursor
- Terminal
- Pages
- Microsoft Word

每个 App 至少验证：

- 目标输入定位；
- Focus Restore；
- AX 写入或 Clipboard fallback；
- 中英文混排；
- 多行文本；
- 连续输入；
- 撤销行为。

# 12. iOS 的位置：后做，但从数据层保持兼容

iOS 不在 V0 开发范围内，但核心模型和 Package 设计不能把 iOS 锁死。

等 macOS 闭环成立后，iPhone 的第一职责是 Instant Capture，而不是复制 macOS 的全部知识管理 UI。

```text
iPhone（后续）
Action Button / AppIntent / App
          ↓
Voice / Text Capture
          ↓
立即保存
          ↓
iCloud
          ↓
与 macOS 共享 Capture / Memory 数据
```

目标：**想到 → 说 / 写 → 已保存**。

# 13. 未来 Cloud：Rust，但不是现在的依赖

当 Private 版本验证完成后，可以增加 Cloud 模式。

服务端使用 Rust，Apple 客户端继续保持 Swift Native。客户端与服务端共享 API Contract 和数据语义，不共享 Runtime，也不为了未来 Cloud 提前把 Rust 引入客户端。

```text
Apple Client                 Future Cloud
Swift Native                 Rust
    │                          │
    ├── Private → iCloud       ├── API
    │                          ├── Memory Service
    └── Cloud → HTTPS/... ──── ├── Retrieval
                               ├── AI Orchestration
                               └── MCP / API
```

# 14. 架构原则清单

| 原则 | 含义 |
| --- | --- |
| macOS First | 先跑通 macOS，再做 iOS。 |
| Apple Native First | 直接使用当前最新 Apple 系统能力；不为旧平台引入替代 Runtime 或兼容层。 |
| Native UI Only | UI 必须使用 Apple 系统组件和当前原生 Liquid Glass；不能擅自创建替代组件。 |
| Capture First | 任何智能处理之前先可靠保存原始 Capture。 |
| Expression First | Memory 和 AI 不能拖慢基本语音输入。 |
| Private by Design | Private Mode = Apple Native + iCloud；数据不进入我们的服务器，不提供 Device Only。 |
| Memory Must Help | 长期 Memory 必须反哺识别、纠错、理解和表达。 |
| No AI Voice | 最终文本越来越像用户本人，而不是通用 AI 文风。 |
| Context Over Model | 长期价值是 Personal Context，不绑定某一个模型。 |
| Minimal Dependencies | 外部依赖需要明确、可量化、不可替代的收益，并且必须获得 owner 明确批准。 |
| Progressive Intelligence | 第一天可用，使用时间越长越懂用户。 |
| Latest Apple Only | 面向当前最新 macOS 与 Apple Intelligence capable Mac；不以旧设备覆盖率为设计目标。 |
| Proven Input Reuse | Type4Me 已验证的输入基础设施优先审计/迁移，不从零重造。 |

# 15. V0 成功标准

第一版不以功能数量作为成功标准，只验证三个问题：

1. 它能不能成为一个足够稳定、足够快、足够自然的 macOS 日常语音输入工具？
2. 用户会不会自然地通过语音输入与主动捕捉沉淀真实 Personal Context？
3. 这些 Context 能不能让使用一段时间后的识别和表达体验明显优于第一天？

如果三个答案都是 YES，产品核心成立。

随后再进入 iOS 与 Cloud 扩展，而不是在 V0 阶段提前扩大平台和基础设施范围。

# 16. 当前技术公式

```text
Type4Me Input Foundation（参考 / 抽取）
+
Swift Native Apple Client
+
macOS 27 Native UI / Liquid Glass
+
Latest Apple Speech
+
Apple Foundation Models
+
NaturalLanguage
+
Personal Memory Engine
+
iCloud / CloudKit
+
Capability Gate
```

第一阶段：macOS 27+ / Apple Intelligence Required  
第二阶段：iOS（同一 Private 数据体系）  
未来可选：Rust Cloud

---

**End of V0 Baseline v2 — repository transcription with approved amendments**
