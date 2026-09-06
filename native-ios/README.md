# Native iOS spike

This directory contains the native SwiftUI implementation slices for the Apple-native WhatsApp Translator direction.

## Current scope

- native SwiftUI iPhone app target
- Apple `FoundationModels` linked through `SystemLanguageModel.default`
- native WebKit integration
- diagnostics for model availability, context size, advertised Indonesian/Polish support, and WebKit state
- P0.1 benchmark harness for contextual Indonesian -> Polish translation experiments
- P0.3/P0.4 off-screen WhatsApp Web session probe using a dedicated persistent WebKit profile
- defensive phone-number-linking bridge, transient pairing-code probe, session-state heuristic, and dedicated-profile disconnect action
- deterministic Swift-side bridge parsing and session-contract tests
- host-independent bounded-context and benchmark-fixture logic shared with the iOS app

WhatsApp Web is **not** loaded automatically. The diagnostics session controller loads `https://web.whatsapp.com` only after an explicit user action.

## Requirements

- Xcode 27 SDK
- iOS 26.0+ deployment target
- a physical Apple-Intelligence-capable iPhone for Foundation Models acceptance tests

## Continuous integration

`.github/workflows/native-ios-ci.yml` runs for native iOS pull requests targeting `apple`, relevant pushes to `apple`, and manual dispatches.

CI is intentionally split by actual platform requirements rather than by the platform of the production app.

### Ubuntu validation

The inexpensive host-independent jobs run first on `ubuntu-latest`:

- `lint` runs SwiftLint against the native Swift sources;
- `test-core` runs `swift test --package-path native-ios` on Linux;
- the package tests exercise both the WhatsApp bridge contract and translation/context logic using the same Swift source files that are compiled into the iOS app.

The Xcode job depends on both Ubuntu jobs, so lint or deterministic-test failures stop before consuming Apple runner time.

`Secret checks` and `PR hygiene` are separate repository workflows and remain on Ubuntu with their existing required check names and behavior.

### Apple validation

The `build-apple` job is reserved for work that actually requires Xcode and Apple SDKs. It:

- records the macOS, Xcode, and installed SDK versions;
- inspects `native-ios/WhatsAppTranslator.xcodeproj`;
- builds the `WhatsAppTranslator` target against the iOS Simulator SDK with code signing disabled.

SwiftUI, WebKit, Foundation Models integration, iOS lifecycle code, and other genuine Apple-SDK behavior stay on the Apple side. CI must not introduce fake Linux implementations merely to increase Linux coverage.

CI is the default validation path for work that does not depend on physical iPhone hardware. It does **not** satisfy acceptance criteria that explicitly require a physical device. In particular, neither Linux tests nor Simulator builds prove:

- Apple Intelligence / `SystemLanguageModel` availability or inference behavior on an iPhone;
- real on-device translation quality, latency, memory, thermal, or battery behavior;
- WhatsApp Web authentication behavior on iPhone WebKit;
- linked-device session persistence or reconnect behavior after an iPhone app restart;
- missed-message synchronization after time offline.

Those hardware-dependent checks remain open in their dedicated roadmap issues and can be completed later without blocking CI-validatable implementation work.

## Host-independent Swift package

`native-ios/Package.swift` exposes small host-independent targets backed by the exact production Swift source files compiled into the app:

- `WhatsAppBridgeCore` uses `WhatsAppTranslator/WhatsAppBridgeSupport.swift`;
- `TranslationCore` uses `WhatsAppTranslator/TranslationCore.swift`.

This keeps transport/session interpretation separate from translation/context logic while allowing both to be tested cheaply on Linux.

Run all current host-independent tests locally with:

```bash
swift test --package-path native-ios
```

## Open

```bash
open native-ios/WhatsAppTranslator.xcodeproj
```

Select a development team for code signing before installing on a physical device.

## Diagnostics

The app currently exposes:

1. OS and bundle diagnostics;
2. Foundation Models availability and context size;
3. advertised `id_ID` and `pl_PL` support through `supportsLocale(_:)`;
4. WebKit initialization state;
5. a P0.1 SystemLanguageModel benchmark;
6. a WhatsApp Web session probe with dedicated-profile, browser-primitive, pairing/session, and disconnect diagnostics.

## WhatsApp Web profile and session controls

The WhatsApp Web probe uses one stable, dedicated `WKWebsiteDataStore` identifier rather than the app-wide default store. The off-screen `WKWebView` uses that profile and a desktop Safari user agent.

The session controller can:

- load WhatsApp Web only on explicit action;
- evaluate JavaScript availability and `indexedDB`, `WebSocket`, `crypto.subtle`, and service-worker support;
- defensively search the visible authentication UI for the phone-number-linking entry point;
- read an eight-character pairing-code candidate when the page exposes one;
- classify the visible page as authentication UI, authenticated UI, or unknown using non-authoritative heuristics;
- release its `WKWebView` and remove the dedicated profile when **Disconnect WhatsApp** is used.

The bridge intentionally avoids depending on WhatsApp internal JavaScript objects. DOM selectors are treated as experimental and may need adjustment after physical-device testing. Pairing codes are memory-only and are cleared on new-session/disconnect paths. Page contents, cookies, and authentication material are not copied into app persistence or logs.

## Deterministic bridge tests

`WhatsAppBridgeSupport.swift` contains the Swift-side contract that interprets JavaScript results and transient session state. Its tests cover:

- pairing-code normalization and malformed-code rejection;
- explicit whitelisting of phone-link and session-state statuses;
- browser-primitive decoding from JavaScript-compatible values;
- malformed and unexpected payload handling;
- new-session and disconnect reset values;
- bounded/truncated diagnostics;
- stability of the dedicated WebKit profile identifier.

The tests use only synthetic payloads. They do not connect to WhatsApp, use credentials, inspect cookies, or validate a linked-device session.

## Translation/context tests

`TranslationCore.swift` contains deterministic logic that does not depend on SwiftUI, WebKit, Foundation Models, or another Apple-only framework. Current Linux coverage verifies:

- bounded recent-context selection;
- non-positive and oversized context windows;
- the benchmark matrix for 0, 3, 8, and 16 context messages;
- that contextual prompts use the most recent messages rather than unlimited history.

The iOS P0.1 benchmark consumes these same fixtures directly, so CI is not testing a separate mock implementation.

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
5. WebKit initializes successfully.

Do not treat simulator-only success as completion of the physical-device acceptance criterion.

## Issue #3 / P0.1 acceptance check

Before closing issue #3, verify on a physical device that:

1. the P0.1 benchmark completes or records categorized runtime failures;
2. unsupported-language/runtime errors are distinguished from poor translation quality;
3. benchmark output and manual quality notes are committed under `docs/native/`;
4. the decision is explicit: primary, partially viable with fallback, or rejected.

## Issue #5 / P0.3 acceptance check

Before closing issue #5, verify on a physical iPhone that:

1. WhatsApp Web reaches a usable authentication state;
2. required browser primitives work in the real page runtime;
3. the desktop-user-agent and off-screen WebKit approach remains usable;
4. blockers and the WebKit transport go/no-go decision are documented.

## Issue #6 / P0.4 acceptance check

Before closing issue #6, verify with a burner account on a physical iPhone that:

1. phone-number linking succeeds through the real WhatsApp linked-device flow;
2. the linked session survives force-quit and relaunch;
3. the session reconnects and synchronizes after time offline;
4. **Disconnect WhatsApp** removes the linked session/profile cleanly;
5. any DOM selector changes needed for the pairing flow are documented and fixed in a focused follow-up issue.
