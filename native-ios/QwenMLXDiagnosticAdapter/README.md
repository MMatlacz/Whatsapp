# Qwen MLX diagnostic adapter

This package is the P0.2b diagnostic runtime for issue #102. It is deliberately
separate from `native-ios/Package.swift` and from the production iOS app target.

The package evaluates `mlx-community/Qwen3-0.6B-4bit` through plain MLX Swift LM
APIs behind the existing `MultilingualLocalModel` contract. It does not enable
Qwen in the production router and it does not download model artifacts during
availability checks or translation.

## Pinned inputs

Direct package dependencies are exact:

- `mlx-swift-lm` 3.31.3
- `swift-transformers` 1.3.4

Before merge, this PR must commit the `Package.resolved` emitted by CI; that
lock file becomes the authoritative full SwiftPM resolution.

The model manifest pins:

- repository: `mlx-community/Qwen3-0.6B-4bit`
- revision: `73e3e38d981303bc594367cd910ea6eb48349da8`
- tokenizer/chat-template revision: the same immutable repository revision
- quantization: 4-bit, group size 64
- `model.safetensors`: 335,450,584 bytes
- `model.safetensors` SHA-256:
  `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`

The verifier also requires the tokenizer/configuration files used by the pinned
snapshot. Model weights are never committed to this repository.

## Explicit provisioning boundary

Provision the exact snapshot outside the inference path. One option is the
Hugging Face CLI:

```bash
cd native-ios/QwenMLXDiagnosticAdapter
mkdir -p .models

hf download mlx-community/Qwen3-0.6B-4bit \
  --revision 73e3e38d981303bc594367cd910ea6eb48349da8 \
  --local-dir .models/Qwen3-0.6B-4bit
```

Before constructing `QwenMLXDiagnosticModel`, call
`QwenMLXArtifactVerifier.verify(directory:)`. Verification checks every required
runtime file plus the exact size and SHA-256 of the weight file.

The model receives only `QwenMLXVerifiedArtifacts`. Its MLX loader uses
`LLMModelFactory.loadContainer(from:using:)`, the local-directory overload that
does not accept a downloader. If artifacts are missing after verification,
availability fails closed as `notInstalled` and translation fails as
`unavailable`.

## Inference boundary

`QwenMLXDiagnosticModel` consumes the complete `TranslationRequest` delivered by
P0.2a. It requires the explicit `sourceText` and bounds source/prompt input size.
The canonical contextual model input remains the versioned
`TranslationPrompt`: immutable instructions become the session instructions and
the untrusted JSON payload becomes the user input.

Generation uses a bounded token budget and requests Qwen's chat-template
`enable_thinking = false` context. A new `ChatSession` is created for every
translation so retained transcript/KV state cannot leak between benchmark cases
or chats. The loaded `ModelContainer` may be reused.

This package returns raw non-empty generated text. It does not decide whether a
response is a valid final answer or a good translation; issue #103 owns that
classification.

## Build and deterministic tests

The PR CI installs the Metal toolchain, resolves the locked package graph,
builds/tests the package on macOS, and compiles it for the iOS Simulator without
downloading model weights.

Manual commands from this directory:

```bash
swift package resolve

xcodebuild \
  -scheme QwenMLXDiagnosticAdapter \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcodebuild \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build test

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

These commands prove package compilation and deterministic boundary behavior.
They do not load Qwen, run Indonesian-to-Polish translation, or establish
physical-iPhone performance or quality.
