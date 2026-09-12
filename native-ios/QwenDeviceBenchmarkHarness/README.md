# Qwen physical-device benchmark harness

This directory is the diagnostic iOS app for issue #111. It exists only to run
the isolated Qwen MLX benchmark on an iPhone for the physical-device follow-up
in #114. Functional CI validation is tracked separately in #112.
It is not part of the production `WhatsAppTranslator` target and it does not
enable Qwen in the production translation router.

## Build boundary

Open the dedicated project:

```bash
open native-ios/QwenDeviceBenchmarkHarness.xcodeproj
```

Select the `QwenDeviceBenchmarkHarness` target, choose the physical iPhone, and
use the repository owner's development team for signing. CI builds this project
for the iOS Simulator with code signing disabled, but Simulator compilation is
not physical-device evidence.

On a free Apple development profile, a device may reject a newly signed app
after three profile-backed apps are installed. Do not remove or replace an
existing app automatically. Free one slot explicitly on the device (or select
a paid development team/profile) and retry the install; record the blocker if
the slot cannot be freed. See the [physical-device run record](../../docs/native/qwen3-physical-device-evaluation.md)
for the latest observed failure.

## Model provisioning

Provision the exact pinned snapshot outside inference:

- repository: `mlx-community/Qwen3-0.6B-4bit`
- revision: `73e3e38d981303bc594367cd910ea6eb48349da8`
- quantization: 4-bit, group size 64
- `model.safetensors`: 335,450,584 bytes
- SHA-256: `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`

Transfer the complete model folder to the iPhone through an explicit local-file
workflow such as Finder/AirDrop/Files. In the harness, use **Import Qwen model
folder** and choose that folder. The app copies the folder into its own
Application Support container, excludes that local copy from backup, and runs
`QwenMLXArtifactVerifier` before creating a benchmark session. Missing files,
unexpected weight size, or a checksum mismatch fail closed. The inference path
contains no model downloader or remote model identifier.

Model weights remain local to the device/app container and must never be added
to Git.

## Benchmark controls

- **Run Qwen functional benchmark** runs the same fixed 32-record Indonesian ->
  Polish corpus used by functional CI, including context-free and bounded
  context comparisons, through the #108 measurement contract. The older
  `runSharedP01` API remains available for generic P0.1 diagnostics but is not
  the physical-device acceptance run.
- **Cancel in-flight benchmark** cancels the active task. A cancellation request
  is considered passed only when the exported result contains a categorized
  cancelled execution.
- **Reset model for cold run** drops the retained model instance so the next run
  must load the model container again. Without a reset, subsequent runs may
  reuse the loaded `ModelContainer`, while every fixture still creates a fresh
  `ChatSession`.
- **Offline-after-provisioning** is an operator observation. For #114, provision
  first, disable network access, relaunch/run a representative case, then mark
  the observation pass or fail before exporting. The harness does not infer
  offline success merely because artifacts are present.

The source revision field should contain the exact Git revision installed on the
phone. Runtime evidence also records the hardware machine identifier, iOS
version/build observation, Xcode/SDK metadata embedded by the build, thermal
state, and battery level/charging state. A completed run exports the latter two
as `before=...; after=...` observations.

For a scripted physical run, pass `--qwen-device-model-dir model`,
`--qwen-device-output physical-run.json`, and
`--qwen-device-source-revision <sha>`. Add
`--qwen-device-cancel-after-seconds <seconds>` to exercise cancellation and add
`--qwen-device-offline-verified` only after the operator has disabled network
access and observed a representative case succeed. After recording with
Xcode/Instruments, pass the measured byte count and its exact source back into
the harness with `--qwen-device-peak-memory-bytes <bytes>` and
`--qwen-device-memory-measurement-source <name>`. If either value is omitted,
the report keeps the metric explicitly unknown.

## Export

After a run the harness writes a deterministic export under its Documents
container containing:

- `report.json`
- `summary.md`
- `results/<fixture-id>.json`

The UI can copy the Markdown or JSON to the pasteboard and share all export
files through the system share sheet. Only source-controlled synthetic fixture
content is included; do not run or export real WhatsApp messages, cookies,
session state, pairing material, or account data.

## #114 evidence boundary

This harness deliberately reports physical-device evidence as `notRun` in the
Simulator and `unknown` on a real device. It does not upgrade itself to an
acceptance result. Issue #114 must still:

1. reconfirm the current device/toolchain compatibility gate;
2. run the full physical-iPhone benchmark and cancellation/offline checks;
3. capture peak resident memory with a named measurement source;
4. record thermal/battery observations;
5. human-review translations using the predeclared #108 rubric; and
6. commit the final `accept`, `reject`, or `continue-evaluation` decision.
