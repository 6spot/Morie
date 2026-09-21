# Morie

Morie is an Apple-native voice input and personal context tool.

The core product is fast, reliable voice input: speak naturally, let Morie recognize and refine the expression, then deliver usable text with minimal interruption.

Morie is currently under active macOS development.

## Development baseline

- macOS first
- Swift / SwiftUI / AppKit
- current Apple platform capabilities
- Apple-native UI by default
- no external dependency without a concrete need
- no compatibility layer for obsolete development-stage designs

## Run locally

1. Open `Morie.xcodeproj` in the current supported Xcode.
2. Configure your Apple Development Team when required.
3. Build and run the `Morie` target on a supported Mac.
4. Complete Morie's native capability and permission setup.
5. Use the configured recording shortcut to test the input flow.

Detailed development, testing and deployment procedures live in the current documentation below.

## Documentation

- [Documentation index](docs/README.md)
- [Product](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Design](docs/DESIGN.md)
- [Testing](docs/TESTING.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Refinement behavior](docs/features/REFINEMENT.md)
- [Task records](docs/tasks/)
- [Agent navigation](AGENTS.md)

Historical task records and reference audits are evidence, not the current specification. Current documents under `docs/` take precedence when they conflict with historical material.
