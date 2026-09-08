# Qwen3 MLX Swift smoke experiment (#93)

Recorded: 2026-09-08. Scope: disposable macOS command-line validation, not an
on-device translation benchmark.

## Result and decision

**PASS: model retrieval/loading and a short, non-empty generation on Apple
Silicon CI. DROP: the disposable harness and its temporary CI integration.**

The English probe produced a thinking fragment, not a completed `OK` answer.
That satisfies the harness's non-empty-generation contract; it does not prove
instruction following, Indonesian -> Polish quality, or suitability for the app.
The decision removes the experiment, not Qwen from future model consideration.
App integration and physical-iPhone validation remain in #4 and the
[P0.2 validation checklist](p0.2-qwen3-local-model.md).

## Evidence and provenance

- [PR #92](https://github.com/MMatlacz/Whatsapp/pull/92) delivered the isolated
  harness and closed the code-level regression-test issue #94.
- Final pre-merge head: `fac796cf7bd3e0f95de7fb969f23f46212d57aeb`.
- [Native iOS CI run 34260577134](https://github.com/MMatlacz/Whatsapp/actions/runs/34260577134)
  passed. Its [Apple job 102177488839](https://github.com/MMatlacz/Whatsapp/actions/runs/34260577134/job/102177488839)
  is the source of the versions, output, and timings below. The inference step
  ran on 2026-09-08 at 18:10:06-18:10:19 UTC.
- The log reports **8 Swift Testing tests in 1 suite passed**. The preceding
  XCTest compatibility line says 0 tests; that is not the Swift Testing result.
- The same run passed lint, Linux core tests, the iOS Simulator build, Metal
  installation, and the Xcode harness build/test. Final-head
  [Secret checks](https://github.com/MMatlacz/Whatsapp/actions/runs/34260577147)
  and [PR hygiene](https://github.com/MMatlacz/Whatsapp/actions/runs/34260577030)
  also passed before merge.
- The squash commit on `apple` is `5a619a6f227453ceb3bba5a20c8bdd1e32a4cdbc`.
  [Post-merge run 34261952770](https://github.com/MMatlacz/Whatsapp/actions/runs/34261952770)
  also passed, including [Apple job 102182122410](https://github.com/MMatlacz/Whatsapp/actions/runs/34261952770/job/102182122410)
  and its real inference smoke step. The numeric observations below are from
  the pre-merge run only, not a combination of the two runs.

### Recorded environment

| Item | Value in the pre-merge job log |
| --- | --- |
| Runner image | `xcode-27-arm64`, version `20260901.0153.1` |
| OS | macOS 26.5.2, build `25F84` |
| Xcode | 27.0, build `27A5252f` |
| Harness destination | `platform=macOS,arch=arm64` |
| Configuration | Release, `ENABLE_TESTABILITY=YES` |
| MLX Swift LM | 3.31.3 |
| MLX Swift | 0.31.6 |
| swift-huggingface | 0.10.1 |
| swift-transformers | 1.3.4 |
| Model identifier | `mlx-community/Qwen3-0.6B-4bit` |

These are recorded versions, not current-version recommendations. The
[historical package manifest](https://github.com/MMatlacz/Whatsapp/blob/5a619a6f227453ceb3bba5a20c8bdd1e32a4cdbc/native-ios/MLXHarness/Package.swift)
pins MLX Swift LM to 3.31.3 but allows ranges for other direct dependencies.
No `Package.resolved` was committed in the harness, and the model snapshot
commit/checksum was not recorded. Future reruns may resolve different artifacts;
this report does not claim bit-for-bit reproducibility.

## Invocation and observed output

The workflow used the default model above, no system prompt, and:

```bash
./.xcodebuild/Build/Products/Release/QwenMLXHarness \
  --prompt "Reply only with OK." \
  --max-tokens 16 \
  --temperature 0
```

The captured generated text was the following fragment, with log timestamps
removed and stdout separated from the interleaved stderr diagnostics:

```text
<think>
Okay, the user wants me to reply only with "OK". Let
```

The request did not disable thinking. The stream ended without a completed
answer under the 16-token cap. The harness did not record a finish reason or
an emitted-token count, so neither is inferred from this excerpt.

The remote Hugging Face model loader completed, the harness streamed non-empty
text, and the step succeeded. The workflow did not restore a model cache.
The loader's combined retrieval/loading duration and the completed generation
loop duration, as printed by the harness, were:

| Observation | Elapsed seconds |
| --- | ---: |
| Model loader | 10.405701041 |
| Generation loop | 2.027815875 |

These are single-run macOS observations, not download-only time, cold/warm
benchmark statistics, time to first token, tokens/second, or iPhone latency.
Download bytes, peak memory, thermal state, battery use, and offline operation
were not measured. No translation fixture or real WhatsApp message was used.

The [historical validation code](https://github.com/MMatlacz/Whatsapp/blob/5a619a6f227453ceb3bba5a20c8bdd1e32a4cdbc/native-ios/MLXHarness/Sources/QwenMLXHarness/HarnessValidation.swift)
rejects empty/whitespace-only streams and invalid temperatures. The
[entry point](https://github.com/MMatlacz/Whatsapp/blob/5a619a6f227453ceb3bba5a20c8bdd1e32a4cdbc/native-ios/MLXHarness/Sources/QwenMLXHarness/main.swift)
streams chunks unchanged, records the two durations, and fails with exit status
2 on errors. Non-empty thinking output passes this deliberately narrow check.

## Cleanup

This completion change removes all five tracked files under
`native-ios/MLXHarness`, including its isolated dependencies and tests. It also
removes only the three experiment-specific workflow steps: Metal component
installation, harness build/test, and model inference. Normal `lint`,
`test-core`, and `build-apple` jobs, their prerequisites, the iOS Simulator build,
and the independent `Secret checks` and `PR hygiene` workflows are preserved.

No production Swift source, package dependency, Xcode target, model adapter, or
router behavior changes. Model weights, generated build products, and full CI
logs are not added to the repository. This report retains only synthetic output
and experiment metadata; it does not claim to purge external runner caches.

After cleanup, normal CI no longer downloads or runs this model. Historical
source remains available through the merged commit; removal does not rewrite
Git history or delete the original branch.

## Re-running the archived experiment

Use a separate worktree on an Apple Silicon Mac with a compatible Xcode/Metal
toolchain; do not restore the disposable package into the production target.
The model loader may download weights, so the first run requires network access.
The exact source and original workflow are preserved at the merged revision:

```bash
git worktree add --detach ../whatsapp-mlx-smoke-93 \
  5a619a6f227453ceb3bba5a20c8bdd1e32a4cdbc
cd ../whatsapp-mlx-smoke-93/native-ios/MLXHarness

xcodebuild -downloadComponent MetalToolchain
xcrun -sdk macosx metal --version
xcodebuild \
  -scheme QwenMLXHarness \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/.xcodebuild" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ENABLE_TESTABILITY=YES \
  build test

./.xcodebuild/Build/Products/Release/QwenMLXHarness \
  --prompt "Reply only with OK." \
  --max-tokens 16 \
  --temperature 0
```

These noninteractive macro/plugin-validation flags belong to the archived
experiment only; they are not added to the production app's build settings.
A later translation-quality experiment must separately control thinking,
record model/dependency revisions, run the shared contextual fixtures, and
validate on the intended physical iPhone before enabling a production route.
