# Temporary Qwen MLX Swift harness

Disposable macOS command-line harness for validating MLX Swift inference with:

`mlx-community/Qwen3-0.6B-4bit`

It is intentionally a separate Swift package so the production iOS app and the
host-independent `native-ios/Package.swift` tests do not acquire MLX dependencies.

## Build and test

MLX needs Xcode to package its Metal resources correctly. From this directory:

```bash
cd native-ios/MLXHarness

xcodebuild \
  -scheme QwenMLXHarness \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcodebuild \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ENABLE_TESTABILITY=YES \
  build test
```

`-skipMacroValidation` is required for the MLX Hugging Face package macro when
building noninteractively. Do not use the resulting `swift build` executable for
runtime inference; it may compile but omit the MLX Metal resource bundle.

The test target covers CLI temperature parsing and streamed-response validation
without loading a model or downloading weights. Temperature is a finite,
nonnegative `Float`, matching MLX's generation parameters.

`ENABLE_TESTABILITY=YES` allows the test target to import the internal validation
helpers in this disposable Release build; it does not change production app settings.

## Run

The first run downloads the model from Hugging Face and caches it locally.

```bash
./.xcodebuild/Build/Products/Release/QwenMLXHarness \
  --prompt "Translate Indonesian to English: Aku sudah sampai rumah." \
  --max-tokens 128 \
  --temperature 0
```

A positional prompt also works:

```bash
./.xcodebuild/Build/Products/Release/QwenMLXHarness \
  "Reply with exactly: MLX Swift is working."
```

Optional flags:

```text
--model <repo>         Hugging Face model ID
--prompt <text>        Prompt
--system <text>        System instruction
--max-tokens <count>   Maximum generated tokens
--temperature <value>  Sampling temperature
--help, -h             Help
```

A successful generation must emit at least one non-whitespace character. Empty
or whitespace-only output exits with status 2 and a diagnostic on standard error.
Chunks are still streamed unchanged; validation does not retain the response.
This smoke test verifies text generation, not translation quality or an exact reply.

## Remove

Delete `native-ios/MLXHarness` and remove the temporary MLX CI step from
`.github/workflows/native-ios-ci.yml`.
