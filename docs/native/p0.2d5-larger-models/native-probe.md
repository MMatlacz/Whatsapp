# Native TranslateGemma token replay

Diagnostic only. The library checks local artifact hashes and replays the exact
input token IDs in an archived Python report. It bypasses native prompt/tokenizer
construction, so it cannot prove tokenizer parity or a production translation path.
The explicit stop IDs are 1 and 106; generation is greedy with a 512-token cap.
The application invokes it only in a Debug build with an explicit launch flag.

The `translation-token-probe` executable built successfully through Xcode. An
initial dirty-source Mac smoke completed two rows with normal stop reasons and
peak process RSS 4,601,348,096 bytes. This remains diagnostic evidence; it is not
a physical-device memory budget or exact-head acceptance run.

Local adapter tests: 31 passed, zero failed, including three new invalid-input
and artifact-integrity checks. The Debug application also built for the simulator.
These facts do not establish simulator inference or physical-iPhone execution.

## Reproduction

From `native-ios/QwenMLXDiagnosticAdapter`:

```sh
xcodebuild -scheme translation-token-probe -destination 'platform=macOS' \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /private/tmp/whatsapp-larger-model-xcode \
  CODE_SIGNING_ALLOWED=NO build
```

The executable takes four positional arguments: local model directory, archived
input report JSON, output JSON, and the actual source SHA. Its default two-row
smoke does not certify full-corpus native quality.

For the Debug app, provision only the manifest-listed model files and the selected
archived input report into its own Documents directory:

```text
TranslationProbe/model/<manifest-listed files>
TranslationProbe/input.json
```

Launch with `--translation-token-probe <actual-source-SHA>`. It runs up to 36
records and writes `TranslationProbe/output.json`; caught errors go to
`TranslationProbe/failure.json`. Do not mistake an old output file for a fresh run:
export it before another run and verify source SHA and input hash. No files should
be provisioned into another app's container and no model files belong in Git.

For actual acceptance, capture an app baseline and repeated cold/warm runs on the
physical iPhone, including app/WebKit workload, thermal state, memory pressure and
lifecycle stability. The probe's RSS high-water and chunk-level thermal observations
alone do not cover all those requirements. Source/template differences between
Python and Swift must remain explicit in any final recommendation.

## Recorded local results

The clean source `520ae7fa79423178a1122a799fae62f36b85699a` builds for macOS,
the iOS simulator and generic unsigned iOS. The clean Mac replay completed two
rows; see `swift-token-smoke-macos.json`. In the actual app on the simulator, MLX
aborted with SIGABRT in Metal device initialization before producing any row.
The normal app was relaunched successfully and its diagnostics screen inspected.
See `native-local-validation.json` and the sanitized runtime-failure report.
Physical iPhone measurements remain outstanding under issue #122.

## Physical memory diagnosis and bounded-buffer fix

On 2026-09-12 the iPhone 15 Pro Max (iOS 26.6.1) reproduced the
load failure. LLDB reported `EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark
memory limit exceeded) (limit=3376 MB)` while MLX read model weights. This is
an observed process limit, not a universal iOS budget. The earlier sampled
2.10 GiB footprint was not the exact high-water mark.

Commit `532f6090b10cb40f96935e7134bbd82b16eea717` drains an autorelease pool
after each 4 MiB artifact-hashing read. This preserves every hash/size check.
The unchanged model and input then loaded in 3.867 seconds on the phone and
produced six archived translations before the host connection was lost.
Pre-load peak RSS fell from 1,081,180,160 to 78,069,760 bytes; the six rows
reported peak RSS 1,311,260,672 bytes. This supports temporary verification
buffer retention as a material contributor to the earlier load failure.
RSS is not the iOS physical-footprint metric. The attempted inference trace
contained no footprint samples before disconnection.

See `physical-device-pool-partial.json`. Its status intentionally remains
`running`: the final 36-case outcome and repeat stability are not yet known.
All 31 adapter tests, focused SwiftLint and local pre-commit checks passed;
the exact new commit range also passed Gitleaks. CI was not used.

A separate iPhone 15 Pro Max simulator (iOS 26.5) reproduced the libc++
null-string assertion with the earlier diagnostic build. This is distinct
from the physical-device resource exception.

## Reconnected device: complete runs

The preserved first run completed all 36 cases after connection loss. A second
profiled run also completed 36/36, and the contextual run completed 8/8. These
counts describe execution, not translation correctness. Reports are archived in
`physical-device-pool-completed.json`, `physical-device-pool-repeat.json` and
`physical-device-context.json`.

Source-only median case times were 1.993 and 2.280 seconds; model load times
were 3.867 and 4.857 seconds. Both runs observed thermal state serious. The
second run's 106 Instruments samples reached 3,455,028,136 bytes (3.218 GiB)
physical footprint, despite lower RSS. This supersedes any inference that
1.22 GiB RSS represents the whole iOS memory budget. The first phone run has
31/36 exact output matches with the Python Mac run at identical input tokens.

The buffer fix enables loading but does not establish safe operation alongside
representative WhatsApp/WebKit activity, lifecycle events or sustained pressure.
No production acceptance or fixed safe memory budget is claimed.

## Loaded WebKit page concurrency

A further 36-case run completed while the user reported WebKit load state
`finished`, session UI `unknown-ui`, after the measured restart. Model load
was 4.079 s and median case duration 2.047 s. The main-app physical footprint
peaked at 3,456,535,440 bytes (3.219 GiB) across 118 samples; thermal state
reached serious. This is close to the preceding main-app-only measurement,
but the trace excludes separate WebContent/GPU/network-process footprints.
The user confirmation does not establish authenticated chat activity or exact
navigation timing. No whole-app safe budget or sustained stability acceptance
is inferred. See `physical-device-webkit-summary.json` and its raw output.
