# Morie

Morie is an Apple-native personal capture and memory product.

## V0 direction

- **macOS first**: stabilize the desktop voice-input loop before iOS.
- **Latest Apple only**: target macOS 27+ on Apple Intelligence capable Macs.
- **Apple Native First**: Swift + system frameworks; avoid third-party runtimes and compatibility layers.
- **Private Mode only in V0**: on-device Apple intelligence + iCloud/CloudKit. No Morie cloud backend.
- **Capture first**: persist the user's intentional capture before any AI transformation.
- **Phase 0 priority**: global push-to-talk → Apple Speech → focus restore → text injection.

## Current development status

Phase 0 is in progress on `phase0/input-foundation`.

The first implementation includes:

- native SwiftUI menu bar shell;
- Private Mode capability gate for Apple Intelligence, Speech, locale, microphone, Speech permission, and Accessibility;
- latest Apple Speech pipeline using `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, and `CaptureInputSequenceProvider`;
- global hold-to-talk shortcut: **Control + Space**;
- frontmost-app capture before recording;
- focus restoration and Accessibility selected-text injection;
- clipboard paste fallback when direct Accessibility insertion is unavailable.

Phase 0 still requires a real macOS 27 build/run and compatibility validation across the target application matrix before it is considered complete.

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
5. Place the caret in another app, hold **Control + Space**, speak, then release the shortcut.

See [`docs/development.md`](docs/development.md) for the full development workflow and [`docs/validation.md`](docs/validation.md) for acceptance testing.

Development work is done on feature branches and merged through pull requests.