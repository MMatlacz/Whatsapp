# Physical-device validation blocker

Status: resolved; the paired iPhone is unlocked and the native app is running from Xcode.

Checked: 2026-09-07

## Evidence

- The paired device is an iPhone 15 Pro Max running iOS 26.6.1 (build 23G83).
- Developer Mode is enabled and the device is connected over USB.
- The installed toolchain is Xcode 26.6 (build 17F113), with the iOS 26.5 SDK exposed to the project.
- `xcrun devicectl device info details` now reports `ddiServicesAvailable: true`, Developer Mode enabled, paired state, and a wired transport.
- A signed physical-device build succeeded, and Xcode shows `WhatsApp Translator` installed on the phone.
- Xcode launched `WhatsAppTranslator` on the phone after it was unlocked.
- A device screenshot confirms the `Native iOS Spike` diagnostics screen renders on iOS 26.6.1.

## Impact

The original developer-disk-image/toolchain and lock-state blockers are resolved. P0.1 and P0.3/P0.4 remain open as product validation gates until their physical-device acceptance steps are completed and recorded.

## Current validation criteria

Keep the paired iPhone connected and complete the acceptance steps in `native-ios/README.md`. Record the benchmark results in `p0.1-system-model-benchmark.md` and the WebKit pairing/session evidence in the follow-up validation notes. Simulator-only smoke evidence is recorded in `p0.3-p0.4-webkit-simulator-smoke.md` and does not close the physical gates.

## Historical unblock criteria

Install an Xcode version containing device support for iOS 26.6.1, reopen the project, select a development team for signing, and rerun the physical-device build. Once the app launches, complete the acceptance steps in `native-ios/README.md` and record the benchmark results in `p0.1-system-model-benchmark.md`.
