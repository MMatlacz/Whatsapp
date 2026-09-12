# Local translation benchmark

- Timestamp: 2026-09-10T19:24:00Z
- Source revision: 7f24e65
- Model: mlx-community/Qwen3-0.6B-4bit
- Model revision: 73e3e38d981303bc594367cd910ea6eb48349da8
- Tokenizer revision: 73e3e38d981303bc594367cd910ea6eb48349da8
- Chat-template revision: 73e3e38d981303bc594367cd910ea6eb48349da8
- Quantization: 4-bit, group_size=64
- Runtime: mlx-swift-lm 3.31.3 (1c05248bb0899e2a7a4962b84d319cf12f4e12aa)
- MLX Swift: 0.31.6 (0bb916c67f4b9e5c682cbe02a42c701c93ab5021)
- Swift Transformers: 1.3.4 (c21fdcde390313a6d98d8e33a346f2c3486c3ab0)
- Execution environment: ios-device
- Corpus: qwen-functional
- Max generated tokens: 512
- Temperature: 0.0
- Top-p: 1.0
- Top-k: 0
- Thinking enabled: false
- Per-case timeout seconds: 120
- Evaluation contract: p0.2d1-v1
- Physical-device evidence: unknown

| Fixture | Mode | Context | Execution | Output | Duration s | Cold load | Load s | First token s | Generation s | Tokens | tok/s | Finish |
| --- | --- | ---: | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| qwen-straight-arrival-no-context | none | 0 | returned | validText | 1.679 | true | 1.077 | 0.399 | 0.179 | 14 | 78.092 | stop |
| qwen-straight-plan-no-context | none | 0 | returned | validText | 0.608 | false | 0.000 | 0.385 | 0.213 | 17 | 79.870 | stop |
| qwen-straight-thanks-no-context | none | 0 | returned | validText | 0.597 | false | 0.000 | 0.386 | 0.201 | 15 | 74.609 | stop |
| qwen-dia-late-no-context | none | 0 | returned | validText | 0.531 | false | 0.000 | 0.378 | 0.143 | 10 | 70.134 | stop |
| qwen-dia-late-context | bounded | 2 | returned | validText | 0.608 | false | 0.000 | 0.452 | 0.146 | 11 | 75.544 | stop |
| qwen-omitted-subject-finished-no-context | none | 0 | returned | validText | 0.570 | false | 0.000 | 0.387 | 0.174 | 13 | 74.927 | stop |
| qwen-omitted-subject-finished-context | bounded | 2 | returned | validText | 0.581 | false | 0.000 | 0.419 | 0.153 | 11 | 71.846 | stop |
| qwen-particle-dong-no-context | none | 0 | returned | validText | 0.562 | false | 0.000 | 0.389 | 0.164 | 12 | 73.364 | stop |
| qwen-particle-sih-no-context | none | 0 | returned | validText | 0.577 | false | 0.000 | 0.390 | 0.177 | 13 | 73.320 | stop |
| qwen-particle-nih-no-context | none | 0 | returned | validText | 0.584 | false | 0.000 | 0.389 | 0.185 | 14 | 75.517 | stop |
| qwen-particle-lah-no-context | none | 0 | returned | validText | 0.539 | false | 0.000 | 0.390 | 0.140 | 10 | 71.260 | stop |
| qwen-particle-kok-no-context | none | 0 | returned | validText | 7.200 | false | 0.000 | 0.391 | 6.799 | 512 | 75.306 | cancelled |
| qwen-particle-kok-context | bounded | 2 | returned | validText | 0.653 | false | 0.000 | 0.431 | 0.210 | 14 | 66.696 | stop |
| qwen-particle-masa-no-context | none | 0 | returned | validText | 0.577 | false | 0.000 | 0.396 | 0.170 | 12 | 70.689 | stop |
| qwen-slang-wkwk-no-context | none | 0 | returned | validText | 0.619 | false | 0.000 | 0.389 | 0.220 | 16 | 72.743 | stop |
| qwen-slang-mager-no-context | none | 0 | returned | validText | 0.577 | false | 0.000 | 0.396 | 0.170 | 12 | 70.470 | stop |
| qwen-slang-baper-no-context | none | 0 | returned | validText | 0.593 | false | 0.000 | 0.394 | 0.189 | 13 | 68.750 | stop |
| qwen-negative-gak-no-context | none | 0 | returned | validText | 0.689 | false | 0.000 | 0.396 | 0.283 | 19 | 67.198 | stop |
| qwen-negative-nggak-no-context | none | 0 | returned | validText | 0.579 | false | 0.000 | 0.397 | 0.171 | 12 | 70.265 | stop |
| qwen-negative-nggak-context | bounded | 2 | returned | validText | 0.604 | false | 0.000 | 0.432 | 0.162 | 11 | 67.933 | stop |
| qwen-negative-ga-no-context | none | 0 | returned | validText | 0.577 | false | 0.000 | 0.397 | 0.170 | 12 | 70.583 | stop |
| qwen-negative-ga-context | bounded | 2 | returned | validText | 0.637 | false | 0.000 | 0.465 | 0.161 | 11 | 68.253 | stop |
| qwen-kinship-bapak-tante-no-context | none | 0 | returned | validText | 0.584 | false | 0.000 | 0.398 | 0.176 | 12 | 68.293 | stop |
| qwen-kinship-bapak-tante-context | bounded | 2 | returned | validText | 0.668 | false | 0.000 | 0.459 | 0.198 | 12 | 60.734 | stop |
| qwen-code-switch-meeting-no-context | none | 0 | returned | validText | 0.780 | false | 0.000 | 0.431 | 0.338 | 23 | 67.957 | stop |
| qwen-joke-treat-no-context | none | 0 | returned | validText | 0.678 | false | 0.000 | 0.398 | 0.268 | 17 | 63.337 | stop |
| qwen-quoted-reply-no-context | none | 0 | returned | validText | 0.609 | false | 0.000 | 0.399 | 0.197 | 13 | 65.825 | stop |
| qwen-quoted-reply-context | bounded | 1 | returned | validText | 0.649 | false | 0.000 | 0.436 | 0.203 | 13 | 63.899 | stop |
| qwen-omitted-dia-station-no-context | none | 0 | returned | validText | 0.637 | false | 0.000 | 0.399 | 0.226 | 15 | 66.476 | stop |
| qwen-omitted-dia-station-context | bounded | 2 | returned | validText | 0.704 | false | 0.000 | 0.466 | 0.227 | 15 | 65.934 | stop |
| qwen-particle-combo-no-context | none | 0 | returned | validText | 0.619 | false | 0.000 | 0.395 | 0.213 | 13 | 61.114 | stop |
| qwen-negative-mixed-no-context | none | 0 | returned | validText | 0.664 | false | 0.000 | 0.397 | 0.257 | 17 | 66.146 | stop |

Execution success, output validity, translation quality, and physical-device acceptance are separate outcomes. A non-empty result is not automatically a quality pass.
