# Qwen MLX diagnostic adapter

This package is the isolated local-model diagnostic runtime used by P0.2. It is deliberately separate from `native-ios/Package.swift` and from the production iOS app target.

The package evaluates `mlx-community/Qwen3-0.6B-4bit` through plain MLX Swift LM APIs behind the existing `MultilingualLocalModel` contract. It does not enable Qwen in the production router and it does not download model artifacts during availability checks or translation.

## Pinned inputs

Direct package dependencies are exact:

- `mlx-swift-lm` 3.31.3
- `swift-transformers` 1.3.4

`Package.resolved` is the authoritative full SwiftPM resolution.

The model manifest pins:

- repository: `mlx-community/Qwen3-0.6B-4bit`
- revision: `73e3e38d981303bc594367cd910ea6eb48349da8`
- tokenizer/chat-template revision: the same immutable repository revision
- quantization: 4-bit, group size 64
- `model.safetensors`: 335,450,584 bytes
- `model.safetensors` SHA-256: `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`

The verifier also requires the tokenizer/configuration files used by the pinned snapshot. Model weights are never committed to this repository.

## Explicit provisioning boundary

Provision the exact snapshot outside the inference path. One option is the Hugging Face CLI:

```bash
cd native-ios/QwenMLXDiagnosticAdapter
mkdir -p .models

hf download mlx-community/Qwen3-0.6B-4bit \
  --revision 73e3e38d981303bc594367cd910ea6eb48349da8 \
  --local-dir .models/Qwen3-0.6B-4bit
```

Before constructing `QwenMLXDiagnosticModel`, call `QwenMLXArtifactVerifier.verify(directory:)`. Verification checks every required runtime file plus the exact size and SHA-256 of the weight file.

The model receives only `QwenMLXVerifiedArtifacts`. Its MLX loader uses `LLMModelFactory.loadContainer(from:using:)`, the local-directory overload that does not accept a downloader. If artifacts are missing after verification, availability fails closed as `notInstalled` and translation fails as `unavailable`.

## Inference boundary

`QwenMLXDiagnosticModel` consumes the complete `TranslationRequest` delivered by P0.2a. It requires the explicit `sourceText` and bounds source/prompt input size. The canonical contextual model input remains the versioned `TranslationPrompt`: immutable instructions become the session instructions and the untrusted JSON payload becomes the user input.

Generation uses a bounded token budget and requests Qwen's chat-template `enable_thinking = false` context. A new `ChatSession` is created for every translation so retained transcript/KV state cannot leak between benchmark cases or chats. The loaded `ModelContainer` may be reused.

The normal `MultilingualLocalModel.translate(_:)` contract still rejects empty final text. The diagnostic benchmark uses a separate internal raw-generation boundary so empty output can be exported and classified instead of being silently collapsed into a generic permanent failure.

## P0.2c shared benchmark runner

Issue #103 added the `qwen-mlx-benchmark` executable and deterministic export schema. The runner reuses the original unencoded P0.1 fixtures directly from `TranslationCore`, including context windows 0, 3, 8, and 16. Encoded prompt experiments are intentionally excluded from the shared comparison corpus.

Run it only after provisioning the verified local model snapshot:

```bash
swift run qwen-mlx-benchmark \
  --model-dir .models/Qwen3-0.6B-4bit \
  --output-dir ../../docs/native/qwen3-benchmark-run \
  --source-revision "$(git rev-parse HEAD)"
```

The output directory contains:

- `report.json` — run-level provenance plus all result records;
- `summary.md` — a compact human-review table;
- `results/<fixture-id>.json` — one deterministic record per fixture.

Each result records fixture identity, language pair, context size, prompt version, execution termination, output-validity classification, raw output, available runtime metrics, explicit unknown measurements, and errors. Runtime execution, output validity, translation quality, and physical-device acceptance remain separate outcomes. A non-empty answer is never automatically treated as a quality pass.

## P0.2d1 physical-device measurement contract

Issue #108 verifies the pinned MLX Swift LM API shape rather than guessing it. `ChatSession.streamDetails` emits `GenerateCompletionInfo`, which supplies prompt-token count, generated-token count, prompt/first-token time, generation time, tokens/second, and a stop reason. The diagnostic generator now records those values directly.

The benchmark also measures whether the reusable `ModelContainer` load was cold and its monotonic load duration. Warm cases reuse the container but continue to create a fresh `ChatSession` per fixture.

The report schema includes the predeclared `p0.2d1-v1` performance/quality contract and a `physicalDeviceEvidence` object. Runs that are not executed on a physical iPhone must leave that evidence state as `notRun`; Simulator/macOS CI must never upgrade it.

The predeclared selection criteria and exact evidence-capture sequence live in `docs/native/p0.2-physical-device-evaluation-plan.md`. Actual physical-iPhone observations, human quality scoring, and the accept/reject/continue-evaluation decision remain issue #109.

This runner is diagnostic only. It does not select Qwen for production, enable fallback routing, or satisfy the physical-iPhone acceptance work by itself.

## Build and deterministic tests

CI installs the Metal toolchain, resolves the locked package graph, builds/tests the package on macOS, builds the benchmark executable, exercises its `--help` path without model weights, and compiles the adapter for the iOS Simulator without downloading model weights.

Manual commands from this directory:

```bash
swift package resolve
swift test
swift build --product qwen-mlx-benchmark
swift run qwen-mlx-benchmark --help

xcodebuild \
  -scheme QwenMLXDiagnosticAdapter \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .xcodebuild-ios \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  build
```

These commands prove package compilation and deterministic boundary behavior. They do not load Qwen, run Indonesian-to-Polish translation, or establish physical-iPhone performance or quality.
