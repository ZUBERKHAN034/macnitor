# Tooling & build

- Uses XcodeGen; runs xcodegen generate after adding/removing source files and never commits the generated xcodeproj, DerivedData, or .build. Confidence: 0.9
- Keeps the engine as a SwiftPM package and runs swift test within it. Confidence: 0.8
- Builds the app with xcodebuild using the app scheme and expects a warning-free build. Confidence: 0.8
- Prefers read-only system interfaces with low CPU overhead and zero telemetry; avoids spawning subprocesses (e.g. nettop) for sampling. Confidence: 0.8
- Uses GitHub Actions to build the app and upload a downloadable artifact so a change can be tested on a real Mac later; relies on CI to run the full build/test gate when the local machine lacks Xcode (only CommandLineTools). Confidence: 0.85
