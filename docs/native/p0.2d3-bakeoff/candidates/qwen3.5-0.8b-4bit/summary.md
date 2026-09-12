# Local translation benchmark

- Timestamp: 2026-09-12T09:18:33Z
- Source revision: 7f24e65f2d21b9a07aed78d41d93e0ef39782556
- Model: mlx-community/Qwen3.5-0.8B-MLX-4bit
- Model revision: 5d894f8cc4ef3e6c88537bf3746ed262f549da6a
- Tokenizer revision: 5d894f8cc4ef3e6c88537bf3746ed262f549da6a
- Chat-template revision: 5d894f8cc4ef3e6c88537bf3746ed262f549da6a
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
- Candidate: Qwen3.5 0.8B 4-bit
- Candidate ID: qwen3.5-0.8b-4bit
- Candidate provenance: researchUnpinned
- Candidate license: Apache-2.0
- Published weight estimate bytes: 625000000
- Candidate memory budget bytes: 1610612736
- Peak resident memory bytes: 1619116032
- Memory measurement: getrusage(RUSAGE_SELF).ru_maxrss (process-high-water)

| Fixture | Mode | Context | Execution | Output | Duration s | Cold load | Load s | First token s | Generation s | Tokens | tok/s | Finish |
| --- | --- | ---: | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| qwen-straight-arrival-no-context | none | 0 | returned | validText | 2.071 | true | 1.126 | 0.798 | 0.117 | 7 | 59.985 | stop |
| qwen-straight-plan-no-context | none | 0 | returned | validText | 1.430 | false | 0.000 | 0.784 | 0.630 | 37 | 58.736 | stop |
| qwen-straight-thanks-no-context | none | 0 | returned | validText | 1.008 | false | 0.000 | 0.771 | 0.217 | 13 | 59.875 | stop |
| qwen-dia-late-no-context | none | 0 | returned | validText | 1.069 | false | 0.000 | 0.780 | 0.272 | 16 | 58.760 | stop |
| qwen-dia-late-context | bounded | 2 | returned | validText | 1.233 | false | 0.000 | 0.843 | 0.375 | 22 | 58.628 | stop |
| qwen-omitted-subject-finished-no-context | none | 0 | returned | validText | 0.983 | false | 0.000 | 0.767 | 0.201 | 12 | 59.674 | stop |
| qwen-omitted-subject-finished-context | bounded | 2 | returned | validText | 1.093 | false | 0.000 | 0.836 | 0.239 | 14 | 58.457 | stop |
| qwen-particle-dong-no-context | none | 0 | returned | validText | 1.286 | false | 0.000 | 0.775 | 0.493 | 29 | 58.860 | stop |
| qwen-particle-sih-no-context | none | 0 | returned | validText | 0.846 | false | 0.000 | 0.781 | 0.051 | 3 | 59.303 | stop |
| qwen-particle-nih-no-context | none | 0 | returned | validText | 1.325 | false | 0.000 | 0.780 | 0.527 | 31 | 58.865 | stop |
| qwen-particle-lah-no-context | none | 0 | returned | validText | 1.056 | false | 0.000 | 0.778 | 0.259 | 15 | 57.997 | stop |
| qwen-particle-kok-no-context | none | 0 | returned | validText | 1.010 | false | 0.000 | 0.791 | 0.205 | 12 | 58.595 | stop |
| qwen-particle-kok-context | bounded | 2 | returned | validText | 0.981 | false | 0.000 | 0.844 | 0.117 | 7 | 60.045 | stop |
| qwen-particle-masa-no-context | none | 0 | returned | validText | 0.962 | false | 0.000 | 0.773 | 0.172 | 10 | 58.237 | stop |
| qwen-slang-wkwk-no-context | none | 0 | returned | validText | 0.934 | false | 0.000 | 0.781 | 0.137 | 8 | 58.579 | stop |
| qwen-slang-mager-no-context | none | 0 | returned | validText | 1.029 | false | 0.000 | 0.775 | 0.234 | 14 | 59.951 | stop |
| qwen-slang-baper-no-context | none | 0 | returned | validText | 1.050 | false | 0.000 | 0.781 | 0.248 | 15 | 60.388 | stop |
| qwen-negative-gak-no-context | none | 0 | returned | validText | 0.937 | false | 0.000 | 0.785 | 0.136 | 8 | 58.941 | stop |
| qwen-negative-nggak-no-context | none | 0 | returned | validText | 0.913 | false | 0.000 | 0.774 | 0.117 | 7 | 59.848 | stop |
| qwen-negative-nggak-context | bounded | 2 | returned | validText | 0.959 | false | 0.000 | 0.786 | 0.151 | 9 | 59.696 | stop |
| qwen-negative-ga-no-context | none | 0 | returned | validText | 1.034 | false | 0.000 | 0.780 | 0.233 | 14 | 60.054 | stop |
| qwen-negative-ga-context | bounded | 2 | returned | validText | 2.128 | false | 0.000 | 0.848 | 1.263 | 74 | 58.578 | stop |
| qwen-kinship-bapak-tante-no-context | none | 0 | returned | validText | 0.994 | false | 0.000 | 0.775 | 0.202 | 12 | 59.534 | stop |
| qwen-kinship-bapak-tante-context | bounded | 2 | returned | validText | 1.187 | false | 0.000 | 0.843 | 0.327 | 19 | 58.053 | stop |
| qwen-code-switch-meeting-no-context | none | 0 | returned | validText | 1.040 | false | 0.000 | 0.786 | 0.235 | 14 | 59.630 | stop |
| qwen-joke-treat-no-context | none | 0 | returned | validText | 1.035 | false | 0.000 | 0.778 | 0.237 | 13 | 54.945 | stop |
| qwen-quoted-reply-no-context | none | 0 | returned | validText | 1.012 | false | 0.000 | 0.789 | 0.205 | 12 | 58.561 | stop |
| qwen-quoted-reply-context | bounded | 1 | returned | validText | 1.247 | false | 0.000 | 0.848 | 0.385 | 22 | 57.183 | stop |
| qwen-omitted-dia-station-no-context | none | 0 | returned | validText | 0.949 | false | 0.000 | 0.778 | 0.151 | 9 | 59.583 | stop |
| qwen-omitted-dia-station-context | bounded | 2 | returned | validText | 1.265 | false | 0.000 | 0.847 | 0.397 | 23 | 57.944 | stop |
| qwen-particle-combo-no-context | none | 0 | returned | validText | 0.928 | false | 0.000 | 0.757 | 0.157 | 9 | 57.438 | stop |
| qwen-negative-mixed-no-context | none | 0 | returned | validText | 1.033 | false | 0.000 | 0.769 | 0.250 | 14 | 56.102 | stop |

Execution success, output validity, translation quality, and physical-device acceptance are separate outcomes. A non-empty result is not automatically a quality pass.
