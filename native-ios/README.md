# Native iOS spike

This directory contains the native SwiftUI implementation slices for the Apple-native WhatsApp Translator direction.

## Current scope

- native SwiftUI iPhone app target
- Apple `FoundationModels` linked through `SystemLanguageModel.default`
- native WebKit linked through `WebPage`
- diagnostics for model availability, context size, advertised Indonesian/Polish support, and WebKit initialization
- P0.1 benchmark harness for contextual Indonesian -> Polish translation experiments

This intentionally does **not** load WhatsApp Web yet. WhatsApp loading and transport persistence are separate architecture spikes.

## Requirements

- Xcode 27 SDK
- iOS 26.0+ deployment target
- a physical Apple-Intelligence-capable iPhone for Foundation Models acceptance tests

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
5. a link to the P0.1 SystemLanguageModel benchmark.

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
5. `WebPage` initializes successfully.

Do not treat simulator-only success as completion of the physical-device acceptance criterion.

## Issue #3 / P0.1 acceptance check

Before closing issue #3, verify on a physical device that:

1. the P0.1 benchmark completes or records categorized runtime failures;
2. unsupported-language/runtime errors are distinguished from poor translation quality;
3. benchmark output and manual quality notes are committed under `docs/native/`;
4. the decision is explicit: primary, partially viable with fallback, or rejected.
