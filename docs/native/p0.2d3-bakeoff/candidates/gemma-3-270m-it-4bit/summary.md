# Local translation benchmark

- Timestamp: 2026-09-12T09:18:33Z
- Source revision: 7f24e65f2d21b9a07aed78d41d93e0ef39782556
- Model: mlx-community/gemma-3-270m-it-4bit
- Model revision: ff1143e3a10547c9f2129e94ca37059b096b23f4
- Tokenizer revision: ff1143e3a10547c9f2129e94ca37059b096b23f4
- Chat-template revision: ff1143e3a10547c9f2129e94ca37059b096b23f4
- Quantization: 4-bit
- Runtime: mlx-swift-lm 3.31.3 (1c05248bb0899e2a7a4962b84d319cf12f4e12aa)
- MLX Swift: 0.31.6 (0bb916c67f4b9e5c682cbe02a42c701c93ab5021)
- Swift Transformers: 1.3.4 (c21fdcde390313a6d98d8e33a346f2c3486c3ab0)
- Execution environment: macos-arm64-local
- Corpus: functional
- Max generated tokens: 96
- Temperature: 0.7
- Top-p: 0.8
- Top-k: 20
- Thinking enabled: false
- Per-case timeout seconds: 120
- Evaluation contract: p0.2d1-v1
- Physical-device evidence: notRun
- Candidate: Gemma 3 270M IT 4-bit
- Candidate ID: gemma-3-270m-it-4bit
- Candidate provenance: researchUnpinned
- Candidate license: Gemma Terms of Use
- Published weight estimate bytes: 151000000
- Candidate memory budget bytes: 1610612736
- Peak resident memory bytes: 1753645056
- Memory measurement: getrusage(RUSAGE_SELF).ru_maxrss (process-high-water)

| Fixture | Mode | Context | Execution | Output | Duration s | Cold load | Load s | First token s | Generation s | Tokens | tok/s | Finish |
| --- | --- | ---: | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| qwen-straight-arrival-no-context | none | 0 | returned | validText | 4.033 | true | 1.812 | 0.280 | 1.241 | 96 | 77.370 | cancelled |
| qwen-straight-plan-no-context | none | 0 | returned | validText | 2.230 | false | 0.000 | 0.262 | 1.263 | 96 | 76.037 | cancelled |
| qwen-straight-thanks-no-context | none | 0 | returned | validText | 1.710 | false | 0.000 | 0.181 | 0.810 | 96 | 118.525 | cancelled |
| qwen-dia-late-no-context | none | 0 | returned | validText | 1.649 | false | 0.000 | 0.179 | 0.768 | 96 | 125.046 | cancelled |
| qwen-dia-late-context | bounded | 2 | returned | validText | 2.178 | false | 0.000 | 0.193 | 1.285 | 96 | 74.686 | cancelled |
| qwen-omitted-subject-finished-no-context | none | 0 | returned | validText | 2.384 | false | 0.000 | 0.263 | 1.416 | 96 | 67.781 | cancelled |
| qwen-omitted-subject-finished-context | bounded | 2 | returned | validText | 1.618 | false | 0.000 | 0.354 | 0.551 | 38 | 68.959 | stop |
| qwen-particle-dong-no-context | none | 0 | returned | validText | 1.731 | false | 0.000 | 0.276 | 0.748 | 55 | 73.552 | stop |
| qwen-particle-sih-no-context | none | 0 | returned | validText | 2.316 | false | 0.000 | 0.274 | 1.318 | 96 | 72.864 | cancelled |
| qwen-particle-nih-no-context | none | 0 | returned | validText | 2.282 | false | 0.000 | 0.275 | 1.282 | 90 | 70.202 | stop |
| qwen-particle-lah-no-context | none | 0 | returned | validText | 2.374 | false | 0.000 | 0.325 | 1.333 | 96 | 72.005 | cancelled |
| qwen-particle-kok-no-context | none | 0 | returned | validText | 2.219 | false | 0.000 | 0.263 | 1.254 | 96 | 76.579 | cancelled |
| qwen-particle-kok-context | bounded | 2 | returned | validText | 1.467 | false | 0.000 | 0.279 | 0.489 | 37 | 75.618 | stop |
| qwen-particle-masa-no-context | none | 0 | returned | validText | 2.310 | false | 0.000 | 0.269 | 1.299 | 96 | 73.890 | cancelled |
| qwen-slang-wkwk-no-context | none | 0 | returned | validText | 2.289 | false | 0.000 | 0.265 | 1.253 | 96 | 76.627 | cancelled |
| qwen-slang-mager-no-context | none | 0 | returned | validText | 1.884 | false | 0.000 | 0.261 | 0.915 | 62 | 67.733 | stop |
| qwen-slang-baper-no-context | none | 0 | returned | validText | 2.226 | false | 0.000 | 0.264 | 1.260 | 96 | 76.191 | cancelled |
| qwen-negative-gak-no-context | none | 0 | returned | validText | 2.240 | false | 0.000 | 0.262 | 1.276 | 96 | 75.215 | cancelled |
| qwen-negative-nggak-no-context | none | 0 | returned | validText | 1.423 | false | 0.000 | 0.171 | 0.542 | 65 | 119.888 | stop |
| qwen-negative-nggak-context | bounded | 2 | returned | validText | 1.658 | false | 0.000 | 0.188 | 0.772 | 96 | 124.274 | cancelled |
| qwen-negative-ga-no-context | none | 0 | returned | validText | 1.591 | false | 0.000 | 0.174 | 0.722 | 96 | 133.005 | cancelled |
| qwen-negative-ga-context | bounded | 2 | returned | validText | 2.261 | false | 0.000 | 0.289 | 1.265 | 96 | 75.878 | cancelled |
| qwen-kinship-bapak-tante-no-context | none | 0 | returned | validText | 2.213 | false | 0.000 | 0.260 | 1.252 | 96 | 76.679 | cancelled |
| qwen-kinship-bapak-tante-context | bounded | 2 | returned | validText | 1.504 | false | 0.000 | 0.303 | 0.492 | 37 | 75.200 | stop |
| qwen-code-switch-meeting-no-context | none | 0 | returned | validText | 1.744 | false | 0.000 | 0.280 | 0.749 | 57 | 76.097 | stop |
| qwen-joke-treat-no-context | none | 0 | returned | validText | 2.097 | false | 0.000 | 0.259 | 1.121 | 84 | 74.904 | stop |
| qwen-quoted-reply-no-context | none | 0 | returned | validText | 2.217 | false | 0.000 | 0.255 | 1.264 | 96 | 75.975 | cancelled |
| qwen-quoted-reply-context | bounded | 1 | returned | validText | 2.274 | false | 0.000 | 0.287 | 1.261 | 96 | 76.112 | cancelled |
| qwen-omitted-dia-station-no-context | none | 0 | returned | validText | 1.874 | false | 0.000 | 0.268 | 0.900 | 68 | 75.547 | stop |
| qwen-omitted-dia-station-context | bounded | 2 | returned | validText | 2.252 | false | 0.000 | 0.285 | 1.263 | 96 | 75.998 | cancelled |
| qwen-particle-combo-no-context | none | 0 | returned | validText | 2.225 | false | 0.000 | 0.255 | 1.256 | 96 | 76.428 | cancelled |
| qwen-negative-mixed-no-context | none | 0 | returned | validText | 2.265 | false | 0.000 | 0.267 | 1.276 | 96 | 75.235 | cancelled |

Execution success, output validity, translation quality, and physical-device acceptance are separate outcomes. A non-empty result is not automatically a quality pass.
