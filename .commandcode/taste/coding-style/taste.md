# Coding style & conventions

- Everything committed is in English: code, comments, docs, and commit messages. Confidence: 0.9
- All user-facing strings go through String(localized:)/SwiftUI Text and are added to the localization catalog in every supported language. Confidence: 0.9
- Prefers a pop-up menu over a segmented control for settings choices. Confidence: 0.85
- Settings panes use Form(.grouped), keep the shared window size, and never read per-cycle values in the pane body. Confidence: 0.85
- Prefers hiding or explaining a disabled control over dimming it. Confidence: 0.9
- Reads behavior-affecting settings at use time (click time) rather than baking them at construction, to avoid unnecessary rebuilds. Confidence: 0.8
- Preserves existing behavior by default on upgrades, verified against a real pre-existing preference domain rather than unit tests alone. Confidence: 0.85
- Keeps item width stable and render inputs unchanged: no per-cycle work and never hand AppKit an unchanged image. Confidence: 0.8
- Designs so the user is never stranded: every control has a recoverable fallback and an on-screen explanation of how to get back. Confidence: 0.8
- Changelog follows Keep a Changelog format; a version bump requires release notes. Confidence: 0.8
