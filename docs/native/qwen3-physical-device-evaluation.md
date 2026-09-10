# Qwen3 physical-device evaluation

Status: **continue-evaluation**. The signed diagnostic harness built for the
named iPhone, but installation was blocked before the app could provision the
model or execute inference. No physical-device performance or quality claim is
made from this attempt.

Run date: 2026-09-10 (Europe/Warsaw)
Source checkout: `codex/implement-qwen-112-114`
Source revision: `9a40b1265e873699b6681b3658b0d7c77f32ba1e`
`origin/apple` base: `ef314a310173240a016331f78dcb88d9c09c5c06`

## Named device and toolchain

| Field | Observation |
| --- | --- |
| Device name | `Duży telefon` |
| Device model | iPhone 15 Pro Max (`iPhone16,2`, hardware `D84AP`) |
| Device OS | iOS 26.6.1, build `23G83` |
| Connection | Paired, wired; developer mode enabled; developer disk-image services available |
| Xcode | 26.6, build `17F113` |
| iOS SDK | `iPhoneOS26.5.sdk` |
| Bundle identifier | `com.mmatlacz.QwenDeviceBenchmarkHarness` |

The device metadata came from `xcrun devicectl device info details` immediately
before the installation attempt. The device identifier is intentionally not
stored in this report.

## Candidate and provisioning boundary

The exact local snapshot was already downloaded outside Git and passed the
host-side verifier before this attempt:

- repository: `mlx-community/Qwen3-0.6B-4bit`;
- model/tokenizer/chat-template revision:
  `73e3e38d981303bc594367cd910ea6eb48349da8`;
- quantization: 4-bit, group size 64;
- `model.safetensors`: 335,450,584 bytes;
- SHA-256:
  `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`;
- runtime: MLX Swift LM 3.31.3 (MLX Swift 0.31.6), Swift Transformers 1.3.4.

The verified snapshot was at `/private/tmp/qwen-model-112-114`; it is not a
repository artifact. Device provisioning did **not** occur because the app
could not be installed. No inference-time downloader was added or invoked.

## Build/install evidence

The dedicated project built successfully for the physical destination with a
signed Debug configuration. Xcode generated the development profile for the
diagnostic bundle and reported `** BUILD SUCCEEDED **`.

The subsequent `xcrun devicectl device install app` operation failed before
installation with:

```text
This device has reached the maximum number of installed apps using a free developer profile:
8AQ98242AE.com.mmatlacz.WhatsAppTranslator
8AQ98242AE.com.matlacz.refillo
8AQ98242AE.com.refillo.app
```

A read-only app inventory confirmed those three installed bundle identifiers;
the Qwen harness was not installed. No existing app was removed or replaced.

## Gate results

| Gate | Result | Evidence/meaning |
| --- | --- | --- |
| Physical device/toolchain discovery | **pass** | Named iPhone 15 Pro Max, iOS 26.6.1, Xcode 26.6/SDK 26.5; paired and developer services available |
| Signed harness build | **pass** | `QwenDeviceBenchmarkHarness.xcodeproj`, physical `iphoneos` destination |
| Device installation | **blocked** | Free developer profile has reached its three-app limit |
| On-device artifact provisioning | **not run** | Requires an installed harness; host copy remains outside Git |
| Cold/warm functional inference | **not run** | No app process started on the device |
| Cancellation | **not run** | No in-flight device generation existed |
| Offline-after-provisioning | **not run** | Provisioning never occurred |
| Peak resident memory | **unknown** | No Instruments/device process measurement exists |
| Thermal observation | **unknown** | No benchmark pass exists |
| Battery before/after pass | **unknown** | No benchmark pass exists |
| Human quality review | **not run** | No physical-run outputs exist; CI review remains negative for this candidate |

## Decision and next action

The candidate decision for this run is **continue-evaluation**, because the
installation gate—not model loading or source compilation—stopped the physical
experiment. Issue [#114](https://github.com/MMatlacz/Whatsapp/issues/114) must
remain open. To continue, either free one app slot on the device with an
explicit operator action or use a paid development team/profile, then rerun the
installation and follow the sequence in
[`p0.2-physical-device-evaluation-plan.md`](p0.2-physical-device-evaluation-plan.md).

Do not uninstall or replace an existing app automatically. Once installed, the
harness must still import and verify the snapshot, run the same 32-record
Indonesian -> Polish functional corpus as CI (including bounded-context pairs),
exercise cancellation and offline-after-provisioning, capture peak memory with
a named Instruments/device source, record thermal/battery observations, and
attach per-fixture human quality scores before any accept or reject decision.

The functional CI result and its negative translation-quality review are kept
separate in
[`qwen3-functional-ci-quality-review.md`](qwen3-functional-ci-quality-review.md).
