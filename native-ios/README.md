# Native iOS spike

This directory contains the first native SwiftUI implementation slice for roadmap issue #2.

## Current scope

- native SwiftUI iPhone app target
- Apple `FoundationModels` linked through `SystemLanguageModel.default`
- native WebKit linked through `WebPage`
- diagnostics for model availability, context size, advertised Indonesian/Polish support, and WebKit initialization

This intentionally does **not** load WhatsApp Web or run translation prompts yet. Those are separate architecture spikes tracked by issues #3 and #5.

## Requirements

- Xcode 27 SDK
- iOS 26.0+ deployment target
- a physical Apple-Intelligence-capable iPhone for the Foundation Models acceptance test

## Open

Open:

`native-ios/WhatsAppTranslator.xcodeproj`

Select a development team for code signing before installing on a physical device.

## Issue #2 acceptance check

Before closing issue #2, verify on a physical device that:

1. the app builds and launches;
2. the diagnostics screen renders OS and bundle data;
3. Foundation Models availability and context size are displayed;
4. Indonesian and Polish locale-support checks execute;
5. `WebPage` initializes successfully.

Do not treat simulator-only success as completion of the physical-device acceptance criterion.
