# Local translation benchmark

- Timestamp: 2026-09-12T09:18:33Z
- Source revision: 7f24e65f2d21b9a07aed78d41d93e0ef39782556
- Model: mlx-community/gemma-3-1b-it-qat-4bit
- Model revision: 15fed4eafb456c6fcb2a1165f19ac609670ed14b
- Tokenizer revision: 15fed4eafb456c6fcb2a1165f19ac609670ed14b
- Chat-template revision: 15fed4eafb456c6fcb2a1165f19ac609670ed14b
- Quantization: 4-bit QAT
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
- Candidate: Gemma 3 1B IT QAT 4-bit
- Candidate ID: gemma-3-1b-it-qat-4bit
- Candidate provenance: researchUnpinned
- Candidate license: Gemma Terms of Use
- Published weight estimate bytes: 733000000
- Candidate memory budget bytes: 1610612736
- Peak resident memory bytes: 1124089856
- Memory measurement: getrusage(RUSAGE_SELF).ru_maxrss (process-high-water)

| Fixture | Mode | Context | Execution | Output | Duration s | Cold load | Load s | First token s | Generation s | Tokens | tok/s | Finish |
| --- | --- | ---: | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| qwen-straight-arrival-no-context | none | 0 | returned | validText | 3.610 | true | 2.354 | 0.402 | 0.114 | 8 | 69.961 | stop |
| qwen-straight-plan-no-context | none | 0 | returned | validText | 1.342 | false | 0.000 | 0.360 | 0.275 | 19 | 69.165 | stop |
| qwen-straight-thanks-no-context | none | 0 | returned | validText | 1.252 | false | 0.000 | 0.355 | 0.168 | 9 | 53.573 | stop |
| qwen-dia-late-no-context | none | 0 | returned | validText | 1.559 | false | 0.000 | 0.548 | 0.284 | 13 | 45.787 | stop |
| qwen-dia-late-context | bounded | 2 | returned | validText | 2.025 | false | 0.000 | 0.602 | 0.699 | 32 | 45.778 | stop |
| qwen-omitted-subject-finished-no-context | none | 0 | returned | validText | 1.535 | false | 0.000 | 0.543 | 0.284 | 13 | 45.726 | stop |
| qwen-omitted-subject-finished-context | bounded | 2 | returned | validText | 1.687 | false | 0.000 | 0.605 | 0.373 | 13 | 34.898 | stop |
| qwen-particle-dong-no-context | none | 0 | returned | validText | 1.453 | false | 0.000 | 0.539 | 0.173 | 8 | 46.213 | stop |
| qwen-particle-sih-no-context | none | 0 | returned | validText | 1.458 | false | 0.000 | 0.546 | 0.196 | 9 | 45.807 | stop |
| qwen-particle-nih-no-context | none | 0 | returned | validText | 1.557 | false | 0.000 | 0.561 | 0.285 | 13 | 45.630 | stop |
| qwen-particle-lah-no-context | none | 0 | returned | validText | 1.467 | false | 0.000 | 0.545 | 0.218 | 10 | 45.950 | stop |
| qwen-particle-kok-no-context | none | 0 | returned | validText | 1.407 | false | 0.000 | 0.544 | 0.151 | 7 | 46.438 | stop |
| qwen-particle-kok-context | bounded | 2 | returned | validText | 1.736 | false | 0.000 | 0.589 | 0.440 | 20 | 45.487 | stop |
| qwen-particle-masa-no-context | none | 0 | returned | validText | 1.448 | false | 0.000 | 0.543 | 0.198 | 9 | 45.416 | stop |
| qwen-slang-wkwk-no-context | none | 0 | returned | validText | 1.550 | false | 0.000 | 0.539 | 0.307 | 14 | 45.543 | stop |
| qwen-slang-mager-no-context | none | 0 | returned | validText | 1.452 | false | 0.000 | 0.544 | 0.198 | 9 | 45.402 | stop |
| qwen-slang-baper-no-context | none | 0 | returned | validText | 1.631 | false | 0.000 | 0.552 | 0.365 | 16 | 43.849 | stop |
| qwen-negative-gak-no-context | none | 0 | returned | validText | 1.584 | false | 0.000 | 0.543 | 0.325 | 15 | 46.118 | stop |
| qwen-negative-nggak-no-context | none | 0 | returned | validText | 1.383 | false | 0.000 | 0.540 | 0.131 | 6 | 45.841 | stop |
| qwen-negative-nggak-context | bounded | 2 | returned | validText | 1.608 | false | 0.000 | 0.590 | 0.306 | 14 | 45.821 | stop |
| qwen-negative-ga-no-context | none | 0 | returned | validText | 1.494 | false | 0.000 | 0.548 | 0.240 | 11 | 45.847 | stop |
| qwen-negative-ga-context | bounded | 2 | returned | validText | 1.694 | false | 0.000 | 0.591 | 0.398 | 18 | 45.171 | stop |
| qwen-kinship-bapak-tante-no-context | none | 0 | returned | validText | 1.859 | false | 0.000 | 0.549 | 0.608 | 28 | 46.059 | stop |
| qwen-kinship-bapak-tante-context | bounded | 2 | returned | validText | 1.846 | false | 0.000 | 0.640 | 0.463 | 21 | 45.328 | stop |
| qwen-code-switch-meeting-no-context | none | 0 | returned | validText | 1.657 | false | 0.000 | 0.585 | 0.371 | 17 | 45.823 | stop |
| qwen-joke-treat-no-context | none | 0 | returned | validText | 1.443 | false | 0.000 | 0.542 | 0.196 | 9 | 45.867 | stop |
| qwen-quoted-reply-no-context | none | 0 | returned | validText | 1.499 | false | 0.000 | 0.545 | 0.235 | 11 | 46.752 | stop |
| qwen-quoted-reply-context | bounded | 1 | returned | validText | 1.466 | false | 0.000 | 0.591 | 0.165 | 7 | 42.471 | stop |
| qwen-omitted-dia-station-no-context | none | 0 | returned | validText | 1.533 | false | 0.000 | 0.545 | 0.284 | 13 | 45.851 | stop |
| qwen-omitted-dia-station-context | bounded | 2 | returned | validText | 1.468 | false | 0.000 | 0.589 | 0.171 | 8 | 46.756 | stop |
| qwen-particle-combo-no-context | none | 0 | returned | validText | 1.604 | false | 0.000 | 0.545 | 0.349 | 16 | 45.904 | stop |
| qwen-negative-mixed-no-context | none | 0 | returned | validText | 1.671 | false | 0.000 | 0.550 | 0.416 | 19 | 45.728 | stop |

Execution success, output validity, translation quality, and physical-device acceptance are separate outcomes. A non-empty result is not automatically a quality pass.
