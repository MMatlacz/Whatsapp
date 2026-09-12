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
