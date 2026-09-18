# Morie

Morie is an Apple-native personal capture and memory product.

## V0 direction

- **macOS first**: stabilize the desktop voice-input loop before iOS.
- **Latest Apple only**: target macOS 27+ on Apple Intelligence capable Macs.
- **Apple Native First**: Swift + system frameworks; avoid third-party runtimes and compatibility layers.
- **Private Mode only in V0**: on-device Apple intelligence + iCloud/CloudKit. No Morie cloud backend.
- **Capture first**: persist the user's intentional capture before any AI transformation.
- **Phase 0 priority**: global toggle capture → Apple Speech → focus restore → text injection.

## Current development status

Phase 0 is in progress on `main`; implementation work continues on task branches.

The first implementation includes:

- native SwiftUI menu bar shell;
- Private Mode capability gate for Apple Intelligence, Speech, locale, microphone, Speech permission, and Accessibility;
- latest Apple Speech pipeline using `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, and a single AVFoundation audio data output;
- configurable global toggle-capture shortcut, defaulting to a solo **Fn / Globe release** to start and finish; Fn chords pass through and **Escape** cancels;
- frontmost-app capture before recording;
- focus restoration and universal clipboard + synthetic paste delivery;
- a native macOS 27 Liquid Glass capture HUD with cancel, live level, and finish controls;
- local SwiftData Capture-first persistence and a native Morie management window for History, Settings, and Diagnostics;
- History recording playback, cancellable file re-recognition, explicit text copying, and Capture deletion with native confirmation;
- retained audio/text after operational interruption, with explicit user cancellation handled as discard;
- a native **Record Capture** action in History to save a voice idea without inserting it into another app;
- a native Memory section for explicitly saved vocabulary/projects, source provenance, lifecycle management and relevant-context inspection in History.

Phase 0 runtime validation, Phase 1 Capture persistence and the Phase 2 Memory foundation are in progress. The owner deferred interactive device validation until the evening of 2026-09-18 while development continues. iCloud/CloudKit sync remains deferred to final integration after Apple Developer enrollment.

## Documentation

- [Documentation index](docs/README.md)
- [Product & architecture baseline](docs/product-architecture-baseline.md)
- [Architecture](docs/architecture.md)
- [Master task plan & progress](docs/tasks.md)
- [Detailed task records](docs/tasks/README.md)
- [Development guide](docs/development.md)
- [Phase 0 validation](docs/validation.md)
- [Deployment & release guide](docs/deployment.md)
- [Agent/contributor rules](AGENTS.md)

## Run locally

1. Use macOS 27+ on an Apple Intelligence-capable Mac with Apple Intelligence enabled.
2. Open `Morie.xcodeproj` in the latest stable Xcode.
3. Select your Development Team if signing requires it.
4. Run Morie and grant Microphone, Speech Recognition, and Accessibility permissions when prompted.
5. Place the caret in another app, press and release **Fn / Globe**, speak, then press and release it again to finish. Press **Escape** to cancel. Change the binding in Settings if required.
6. To save an idea to History, choose **Open Morie → History → Record Capture**. Finish with the HUD or your shortcut; the HUD reports “已保存”.
7. To retain a term or project, open a saved Capture and choose **Save Memory…**, or use **Memory → New Memory**. Add names/aliases and notes explicitly; active matching memories appear in Capture details. Automatic extraction and input correction are subsequent work.

See [`docs/development.md`](docs/development.md) for the full development workflow and [`docs/validation.md`](docs/validation.md) for acceptance testing.

Development work is done on feature branches and merged through pull requests.
