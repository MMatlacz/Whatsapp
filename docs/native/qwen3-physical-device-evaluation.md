# Qwen3 physical-device evaluation

Status: **reject** for the evaluated candidate. The named physical iPhone ran
the complete 32-record corpus, but the candidate exceeds the memory budget and
fails the translation quality hard gates. Offline-after-provisioning was not
exercised, so this report makes no offline-pass claim.

Run date: 2026-09-10 (Europe/Warsaw)
Issue: [#114](https://github.com/MMatlacz/Whatsapp/issues/114)  
Source revision installed on the phone: `7f24e65`

The remainder of this document begins with the completed run. The historical
pre-cleanup installation blocker is retained below as context.

## Completed physical run

### Device and toolchain

| Field | Observation |
| --- | --- |
| Device | iPhone 15 Pro Max (`iPhone16,2`) |
| Device OS | iOS 26.6.1, build `23G83` |
| Connection | Paired, wired; developer services available |
| Xcode | 26.6, build `17F113` |
| iOS SDK | `iPhoneOS26.5.sdk` |
| Bundle identifier | `com.mmatlacz.QwenDeviceBenchmarkHarness` |

No device UUID or installed-app inventory is included in this report.

### Candidate and provisioning

The exact local snapshot was verified on the host and copied into the harness
app's private `Documents/model` directory before the run:

- repository: `mlx-community/Qwen3-0.6B-4bit`;
- model/tokenizer/chat-template revision:
  `73e3e38d981303bc594367cd910ea6eb48349da8`;
- quantization: 4-bit, group size 64;
- `model.safetensors`: 335,450,584 bytes;
- SHA-256:
  `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`;
- runtime: MLX Swift LM 3.31.3 (MLX Swift 0.31.6), Swift Transformers 1.3.4.

The harness verifier accepted the device copy before inference. No downloader,
remote model identifier, WhatsApp message, cookie, pairing material, or account
data was used.

### Gate and performance results

| Gate | Result | Evidence |
| --- | --- | --- |
| Physical device/toolchain | **pass** | Named iPhone 15 Pro Max; iOS 26.6.1/23G83; Xcode 26.6/17F113; SDK 26.5 |
| Signed harness build/install | **pass** | Dedicated project built for `iphoneos` and installed with the development profile |
| Artifact verification | **pass** | Exact snapshot, size, and SHA-256 above; local copy verified on device |
| Functional corpus | **pass** | 32/32 records returned non-empty text; raw `report.json`, `summary.md`, `results/*.json`, and `cancellation.json` were exported by the harness |
| Cold model load | **pass** | 1.077 s maximum observed, budget 8 s |
| Warm first token | **pass** | 0.466 s maximum observed, budget 1.5 s |
| Warm generation | **fail** | 6.799 s maximum (`qwen-particle-kok-no-context`), budget 4 s; the same record hit the 512-token limit |
| Warm throughput | **pass** | 60.734 tokens/s minimum, budget 10 tokens/s |
| Peak resident memory | **fail** | 3,096,216,904 bytes (2.88 GiB) from Xcode Instruments `Activity Monitor` `activity-monitor-process-live.memory-physical-footprint`; budget 1,610,612,736 bytes (1.5 GiB) |
| Thermal observation | **pass** | `before=fair; after=fair`; neither state was serious or critical |
| Battery observation | **recorded** | `before=level=80%; state=charging; after=level=80%; state=charging` |
| Cancellation | **pass** | 0.1-second probe produced `termination=cancelled` after 0.107 s |
| Offline-after-provisioning | **not run** | Network access was not disabled and therefore no offline-pass claim is made |

The memory value was measured in a separate Activity Monitor trace of the same
installed harness/model configuration. The final report accepts that measured
value through `--qwen-device-peak-memory-bytes` and records the exact source
through `--qwen-device-memory-measurement-source`; omitted measurements remain
explicitly unknown.

The raw synthetic export from the physical run is preserved in
[`docs/native/qwen3-physical-evidence/7f24e65/`](qwen3-physical-evidence/7f24e65/).
That export is explicitly marked as the pre-evidence-plumbing baseline; the
offline gate and a fresh report from the committed evidence-plumbing revision
still need to be captured before closing #114.

### Manual rubric review

The review uses the committed `p0.2d1-v1` rubric. Scores are
`0=incorrect, 1=partially acceptable, 2=acceptable`; `—` means the criterion
does not apply to that fixture. Columns are `m` meaning, `p` pronouns/omitted
subjects, `f` family relationships, `s` slang/tone, `g` Polish grammar, `h`
hallucinations, and `q` quoted/reference handling. This is a reproducible
manual review of the exported synthetic outputs; an independent human sign-off
is still appropriate before any future accept decision.

| Fixture | m | p | f | s | g | h | q | Note |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `qwen-straight-arrival-no-context` | 0 | — | — | 0 | 0 | 0 | — | Wrong mixed-language output invents “class”. |
| `qwen-straight-plan-no-context` | 0 | — | — | 1 | 0 | 2 | — | Mostly Indonesian; proposal is not natural Polish. |
| `qwen-straight-thanks-no-context` | 0 | — | — | 0 | 0 | 2 | — | Fragmented mixed-language thanks. |
| `qwen-dia-late-no-context` | 0 | 0 | — | 0 | 0 | 2 | — | Omits the speaker and the coming event. |
| `qwen-dia-late-context` | 0 | 0 | — | 0 | 0 | 2 | — | Context does not resolve the feminine referent. |
| `qwen-omitted-subject-finished-no-context` | 1 | 1 | — | 0 | 0 | 2 | — | Meaning is preserved only by leaving source text untranslated. |
| `qwen-omitted-subject-finished-context` | 1 | 1 | — | 0 | 0 | 2 | — | Same untranslated output with context. |
| `qwen-particle-dong-no-context` | 0 | — | — | 0 | 0 | 0 | — | Unrelated phrase. |
| `qwen-particle-sih-no-context` | 0 | — | — | 0 | 0 | 2 | — | Indonesian remains and word form is corrupted. |
| `qwen-particle-nih-no-context` | 0 | — | — | 0 | 0 | 1 | — | “wąsuję” changes the intended action. |
| `qwen-particle-lah-no-context` | 1 | — | — | 1 | 0 | 2 | — | Source particle is retained but not translated. |
| `qwen-particle-kok-no-context` | 0 | — | — | 0 | 0 | 0 | — | Repetitive “Ktoś” hallucination; 512-token limit. |
| `qwen-particle-kok-context` | 0 | — | — | 0 | 0 | 1 | — | Context does not recover the question. |
| `qwen-particle-masa-no-context` | 1 | — | — | 1 | 0 | 2 | — | Source text is copied rather than translated. |
| `qwen-slang-wkwk-no-context` | 0 | — | — | 0 | 0 | 2 | — | “Wrong group” is omitted. |
| `qwen-slang-mager-no-context` | 0 | — | — | 0 | 0 | 0 | — | Unintelligible output. |
| `qwen-slang-baper-no-context` | 0 | — | — | 0 | 0 | 0 | — | Invents “Jona” and omits the warning. |
| `qwen-negative-gak-no-context` | 1 | — | — | 0 | 0 | 1 | — | Partial refusal; “tonight” becomes “these days”. |
| `qwen-negative-nggak-no-context` | 1 | — | — | 1 | 0 | 2 | — | Meaning remains in Indonesian, not Polish. |
| `qwen-negative-nggak-context` | 1 | — | — | 1 | 0 | 2 | — | Context is ignored; source text copied. |
| `qwen-negative-ga-no-context` | 1 | — | — | 0 | 0 | 2 | — | Question content is retained but not translated. |
| `qwen-negative-ga-context` | 1 | — | — | 0 | 0 | 2 | — | Context does not change the untranslated output. |
| `qwen-kinship-bapak-tante-no-context` | 1 | — | 1 | 0 | 0 | 2 | — | Kinship roles survive only because source text is copied. |
| `qwen-kinship-bapak-tante-context` | 1 | — | 1 | 0 | 0 | 2 | — | Context does not produce Polish. |
| `qwen-code-switch-meeting-no-context` | 0 | — | — | 0 | 0 | 0 | — | Meeting/postponement meaning is replaced by unrelated text. |
| `qwen-joke-treat-no-context` | 1 | — | — | 1 | 0 | 2 | — | Humor/emoji survive, but output remains Indonesian. |
| `qwen-quoted-reply-no-context` | 1 | — | — | 0 | 0 | 2 | 1 | Reply is copied; no Polish translation. |
| `qwen-quoted-reply-context` | 1 | — | — | 0 | 0 | 2 | 1 | Reference shape survives, translation is absent. |
| `qwen-omitted-dia-station-no-context` | 1 | 0 | — | 0 | 0 | 2 | — | Omitted referent is not resolved. |
| `qwen-omitted-dia-station-context` | 1 | 0 | — | 0 | 0 | 2 | — | Bounded context is ignored. |
| `qwen-particle-combo-no-context` | 1 | — | — | 1 | 0 | 2 | — | Particles survive only in copied Indonesian. |
| `qwen-negative-mixed-no-context` | 1 | — | — | 1 | 0 | 2 | — | Contrast survives but output is mixed Indonesian. |

Meaning scored 2 on **0/32** fixtures, so the hard meaning gate fails. The
hallucination hard gate also fails on the invented or materially altered
outputs. The recorded quality result is therefore **reject**, independent of
the memory-budget failure.

### Decision

The candidate decision is **reject**. The decisive evidence is the
3,096,216,904-byte peak physical footprint against the 1.5 GiB budget and the
hard-gate quality failures across the complete corpus. The missing offline
observation is an additional acceptance gap, not a basis for upgrading this
candidate. This does not claim production router integration or close #4.

The harness remains useful for a future candidate: provision a replacement
model/configuration, disable network access after provisioning, rerun the same
corpus, capture named memory evidence, and repeat the per-fixture review.

## Historical first attempt (before app-slot cleanup)

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

### Historical decision and next action

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
