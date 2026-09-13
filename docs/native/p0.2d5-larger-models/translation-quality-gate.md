# TranslateGemma diagnostic quality gate

Status: research-only. This document records a bounded adapter improvement and
the existing human-reviewed baseline. It does not approve TranslateGemma for
validated routing, close #122, or provide a production translation decision.

## Frozen baseline

The source-only TranslateGemma greedy run used the frozen 36-case Indonesian to
Polish corpus, the exact model snapshot
`mlx-community/translategemma-4b-it-4bit` at revision
`5788ec08c047f3f2e17808101b8d9566ac930d58`, the native model chat template,
greedy decoding (`temperature = 0`, `maxNewTokens = 512`), and explicit
`id`/`pl` content metadata. The human review classified the outputs as:

| Result | Count |
| --- | ---: |
| Acceptable | 13 |
| Minor defect | 13 |
| Major error | 10 |
| Incomplete | 0 |

The ten source-only major-error fixture IDs are:

- `qwen-slang-wkwk-no-context` — wrong-group meaning was not preserved.
- `qwen-negative-nggak-no-context` — the pickup/refusal meaning became an
  invalid Polish verb.
- `qwen-negative-ga-no-context` — a changed plan became past inability.
- `qwen-kinship-bapak-tante-no-context` — father became a generic man and
  `nanti` became tomorrow.
- `qwen-joke-treat-no-context` — paying/treating became a behavioral “treat”.
- `qwen-negative-mixed-no-context` — “not lazy” became “not willing”, reversing
  the contrast.
- `heldout-pickup-conditional` — the pickup instruction became making an
  appointment.
- `heldout-slang-reluctance` — `mager` was treated as a person's name.
- `heldout-slang-personal` — the reassurance was not meaningful Polish.
- `heldout-joke-payment` — paying became counting and the emoji changed.

The full raw outputs and review reasons remain in
[`translategemma-source-greedy.json`](translategemma-source-greedy.json) and
[`translategemma-source-greedy-review.json`](translategemma-source-greedy-review.json).
Those files are evidence for human review; they are not used as an automatic
semantic score.

## Glossary-guided result

A second offline greedy run used the same pinned TranslateGemma snapshot,
36-case order, generation settings and model-native `id` to `pl` template. Its
only input change was a bounded Indonesian vocabulary note set covering common
negation, kinship, time, slang and payment terms. Exact input messages, token
IDs and raw outputs are preserved in `translategemma-glossary-greedy.json`; the
input corpus and provisional review are adjacent files.

The same review categories produced 13 acceptable, 18 minor and 5 major
results. This improves the previous 10 major errors, including repairs for
father/aunt/later, the negative lazy/tired contrast and the held-out pickup
condition. It still fails the standalone pickup refusal, both payment jokes,
wrong-group meaning and the no-need-to-return case. The run came from a dirty
worktree and is labelled diagnostic; it is not clean-source acceptance or an
independent bilingual review.

Five major semantic errors remain too many for unreviewed chat translation.
Production routing therefore stays disabled, and no model output is eligible
for sending. The glossary establishes a measurable direction for the next
clean evaluation without changing the application quality gate.

## Adapter change

`TranslateGemmaPrompt` constructs the model-specific user message with a text
content object and the explicit `id` to `pl` language codes. When a retranslation
comment is present, it is placed in a bounded, labelled prefix followed by the
target text. The adapter applies the locally provisioned tokenizer's own chat
template before generation, preserving parity with the measured reference
experiment. Input control tokens and oversized guidance are rejected before any
model work.

`TranslationQualityGate` is intentionally conservative. It blocks missing,
empty, interrupted, truncated, unchanged-source, and control-token output. For
all other output it returns `requiresHumanReview` with the reason
`semanticQualityUnverified`; it has no meaning, fluency, tone, or context
classifier. Every decision reports `mayBeSent = false`. The adapter also emits
no word alignments. Known-word display must remain disabled or use only
explicitly reviewed source/translation parts.

## Reproducible checks

Run the host-independent adapter tests from
`native-ios/QwenMLXDiagnosticAdapter`:

```sh
swift test --filter TranslateGemmaPromptTests
swift test --filter TranslationQualityGateTests
```

These tests verify template metadata, guidance/target separation, bounded
inputs, and the no-automatic-quality-pass/send policy. They do not run model
inference and cannot improve the frozen 10/36 semantic baseline by themselves.

For a real evaluation, provision the exact manifest-listed snapshot outside the
repository, run the diagnostic `translation-token-probe` or a dedicated clean
benchmark process, export all 36 outputs with source SHA, corpus hash, model
revision, prompt/template version, generation settings, and resource evidence,
then repeat the same human bilingual review. A model/resource directory was not
present in this checkout during this change, so no new inference quality number
is claimed here. The existing physical runs also remain resource and thermal
evidence only; they do not satisfy whole-app plus WebKit acceptance.
