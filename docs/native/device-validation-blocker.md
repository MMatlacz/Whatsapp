# Physical-device validation blocker

Status: blocked pending a compatible Xcode installation.

Checked: 2026-09-07

## Evidence

- The paired device is an iPhone 15 Pro Max running iOS 26.6.1 (build 23G83).
- Developer Mode is enabled and the device is connected over USB.
- The installed toolchain is Xcode 26.6 (build 17F113).
- That Xcode installation exposes only the iOS 26.5 SDK.
- `xcrun devicectl` reports `connected (no DDI)` and `The developer disk image could not be mounted on this device`.
- A generic iOS build succeeds, but a build targeted at the physical device times out before compilation because the developer disk image cannot be mounted.

## Impact

The P0.1 Foundation Models benchmark and P0.3/P0.4 WhatsApp Web pairing/session checks cannot be treated as run until the phone can launch the app from Xcode. This is an environment/toolchain blocker, not a product go/no-go decision for Foundation Models or WebKit.

## Unblock criteria

Install an Xcode version containing device support for iOS 26.6.1, reopen the project, select a development team for signing, and rerun the physical-device build. Once the app launches, complete the acceptance steps in `native-ios/README.md` and record the benchmark results in `p0.1-system-model-benchmark.md`.
