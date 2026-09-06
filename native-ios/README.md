# Native iOS spike

This directory contains the native SwiftUI implementation slices for the Apple-native WhatsApp Translator direction.

## Current scope

- native SwiftUI iPhone app target
- Apple `FoundationModels` linked through `SystemLanguageModel.default`
- native WebKit linked through `WebPage`
- diagnostics for model availability, context size, advertised Indonesian/Polish support, WebKit initialization, and explicit WhatsApp login state
- P0.1 benchmark harness for contextual Indonesian -> Polish translation experiments

This intentionally does **not** load WhatsApp Web yet. Until P0.3 loads it, diagnostics report the WhatsApp login state as `not evaluated (P0.3)`. WhatsApp loading and transport persistence are separate architecture spikes.

## Requirements

- Xcode 27 SDK
- iOS 26.0+ deployment target
- a physical Apple-Intelligence-capable iPhone for Foundation Models acceptance tests

## Continuous integration

`.github/workflows/native-ios-ci.yml` runs for native iOS pull requests targeting `apple`, relevant pushes to `apple`, and manual dispatches.

CI currently:

- runs on GitHub's `xcode-27` hosted runner;
- records the macOS, Xcode, and installed SDK versions;
- inspects `native-ios/WhatsAppTranslator.xcodeproj`;
- builds the `WhatsAppTranslator` target against the iOS Simulator SDK with code signing disabled.

CI is the default validation path for work that does not depend on physical iPhone hardware. It does **not** satisfy acceptance criteria that explicitly require a physical device. In particular, CI does not prove:

- Apple Intelligence / `SystemLanguageModel` availability or inference behavior on an iPhone;
- real on-device translation quality, latency, memory, thermal, or battery behavior;
- WhatsApp Web authentication behavior on iPhone WebKit;
- linked-device session persistence or reconnect behavior after an iPhone app restart.

Those hardware-dependent checks remain open in their dedicated roadmap issues and can be completed later without blocking CI-validatable implementation work.

## Open

Open:

```bash
open native-ios/WhatsAppTranslator.xcodeproj
```

Select a development team for code signing before installing on a physical device.

## Diagnostics

The launch screen shows:

1. OS and bundle diagnostics;
2. Foundation Models availability and context size;
3. advertised `id_ID` and `pl_PL` support through `supportsLocale(_:)`;
4. WebKit `WebPage` initialization state;
5. explicit WhatsApp login state, reported as not evaluated until P0.3;
6. a link to the P0.1 SystemLanguageModel benchmark.

## P0.1 benchmark

Use **P0.1 SystemLanguageModel benchmark** to run synthetic translation cases covering:

- Indonesian -> English;
- English -> Polish;
- Indonesian -> Polish;
- contextual Indonesian -> Polish with 0, 3, 8, and 16 context messages;
- particles and slang such as `dong`, `sih`, `nih`, `lah`, `kok`, `masa`, `wkwk`, `mager`, `baper`, and `gak/nggak/ga` variants;
- omitted subjects, family terms, jokes, code-switching, and quoted replies.

The benchmark screen exports Markdown that should be pasted into `docs/native/p0.1-system-model-benchmark.md` after running on a physical device.

## Issue #2 acceptance check

Before closing issue #2, verify on a physical device that:

1. the app builds and launches;
2. the diagnostics screen renders OS and bundle data;
3. Foundation Models availability and context size are displayed;
4. Indonesian and Polish locale-support checks execute;
5. `WebPage` initializes successfully;
6. the WhatsApp login-state diagnostic renders as `not evaluated (P0.3)` until the separate WhatsApp Web spike is implemented.

Do not treat simulator-only success as completion of the physical-device acceptance criterion.

## Issue #3 / P0.1 acceptance check

Before closing issue #3, verify on a physical device that:

1. the P0.1 benchmark completes or records categorized runtime failures;
2. unsupported-language/runtime errors are distinguished from poor translation quality;
3. benchmark output and manual quality notes are committed under `docs/native/`;
4. the decision is explicit: primary, partially viable with fallback, or rejected.
