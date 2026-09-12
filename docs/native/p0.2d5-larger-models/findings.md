# Larger-model comparison: macOS findings

Status: Mac comparison complete; physical-device/application validation pending.
No production candidate accepted. The phone was unavailable at the latest
`devicectl` check on 2026-09-12. No CI results are used for validation.

TranslateGemma 4B with greedy decoding is the strongest configuration in this
small provisional review, and the candidate for the next device experiment.
It still has ten major source-only errors and is not reliable enough for routing
real conversations. Larger weights and thinking did not solve the task by themselves.

## Source-only quality

These are combined meaning/usable-Polish categories, not the previous M/H gate.
Scores are an agent review, not independent bilingual validation. The corpus is
24 regression messages plus 12 new synthetic messages frozen before model output.
Counts are judgment-sensitive; small differences are not statistically established.

| Configuration | Acceptable | Minor defect | Major error | Incomplete |
| --- | ---: | ---: | ---: | ---: |
| Qwen3 4B, thinking off | 6 | 10 | 20 | 0 |
| Qwen3 4B, thinking on, initial cap 2048 | 6 | 14 | 13 | 3 |
| TranslateGemma 4B, sampled | 13 | 9 | 14 | 0 |
| TranslateGemma 4B, greedy | 13 | 13 | 10 | 0 |
| Gemma 3 4B, greedy | 8 | 12 | 16 | 0 |

The three capped Qwen source cases were rerun separately with 8192 tokens. All
finished, using 2050–3176 tokens, and all had major meaning errors. Thus the
extra budget removes incompleteness but does not rescue their translations.
Raw initial and retry outputs are separate; the table does not silently replace
the initial run. The one capped context case also finished on retry (3408 tokens)
but changed aunt into father.

Thinking fixed some events, such as keeping a Friday deadline and a Monday meeting,
but introduced or retained errors elsewhere. TranslateGemma greedy improved the
not-yet-paid/refusal distinction, while still mishandling pickup and slang.
Gemma changed a Friday deadline to Wednesday. All configurations have meaningful
failures beyond Polish spelling or omitted emphasis.

## Context

TranslateGemma greedy has five acceptable, two minor and one major output in the
eight-case context probe. Sampled TranslateGemma has four acceptable outputs;
Gemma has three; Qwen thinking-off has two; Qwen thinking-on has one before retry.
This is a substantial improvement over the previous encoder-decoder concatenation
strategy, but is not general context acceptance. TranslateGemma still changes
explicit father into a generic man and later into tomorrow. Its greedy pickup
output retains the speaker as the passenger but introduces a third-person picker.

The complete per-case reasons are in `context-review.json`, source review files,
and `retry-review.json`. Raw outputs, exact messages and rendered templates are
in the corresponding run JSON files. Context is synthetic and bounded, not a real
WhatsApp transcript. No expected meaning is included in inference input.

## Memory and latency observations

| Configuration | Peak Mac process RSS | Median generation |
| --- | ---: | ---: |
| Qwen3 source, thinking off | 2.28 GiB | 0.76 s |
| Qwen3 source, thinking on | 2.72 GiB | 22.78 s |
| TranslateGemma source, sampled | 3.29 GiB | 1.06 s |
| TranslateGemma source, greedy | 3.25 GiB | 0.84 s |
| Gemma 3 source, greedy | 3.65 GiB | 0.81 s |

These are isolated process high-water RSS values on a 32 GiB Mac, not iPhone
footprints. They include runtime overhead; models ran sequentially, but other host
workloads were not controlled. Generation medians exclude model load and are not
an acceptance performance ranking. Thinking first-token timing is the first
reasoning token, not the first translated token; use total generation for this
comparison. Retry medians were about 100 s for source cases and 112 s for the
single context case.

The measurements justify removing 1.5 GiB as a preliminary quality exclusion.
They do not justify replacing it with a fixed phone limit such as 3 or 4 GiB.
The real budget remains unmeasured: run the selected model on the actual iPhone
alongside the app/WebKit, record baseline and peak footprint, repeated warm/cold
latency, thermal state, memory pressure and lifecycle stability. Keep device
identifiers and full local Xcode artifacts outside Git. No production route should
be enabled by that diagnostic work.

## Validation and provenance

The archive contains 224 full-matrix outputs: 180 source-only, 40 contextual and
four cap retries. The initial two-row TranslateGemma smoke with missing turn-stop
configuration is excluded and retained outside Git. The corrected smoke ended
normally before the full runs. Tokenizer source-text parity with SentencePiece
was 36/36; native `id`/`pl` templates and prompt limits were verified separately.

Every full run was audited for clean source, corpus hash, ordered case coverage,
exact message construction, generated-token counts, stop reasons and final-output
extraction. The audit does not certify meaning. Synthetic corruption probes
confirmed detection of missing rows, changed prompts, false cap flags and changed
final output. Local pre-commit checks include secret checks and JSON validation.
Local Xcode validation and physical TranslateGemma execution are now recorded in
`native-probe.md` and `physical-device-summary.json`; whole-app WebKit and
sustained stability acceptance remain outstanding.

## Quality by corpus split

Each cell is acceptable / minor / major / incomplete.

| Review | Regression (24) | New synthetic (12) |
| --- | --- | --- |
| qwen3-source-off-review | 6 / 6 / 12 / 0 | 0 / 4 / 8 / 0 |
| qwen3-source-on-review | 4 / 9 / 9 / 2 | 2 / 5 / 4 / 1 |
| translategemma-source-review | 11 / 6 / 7 / 0 | 2 / 3 / 7 / 0 |
| translategemma-source-greedy-review | 10 / 8 / 6 / 0 | 3 / 5 / 4 / 0 |
| gemma3-source-review | 7 / 8 / 9 / 0 | 1 / 4 / 7 / 0 |

## Physical-device update after buffer fix

TranslateGemma 4B greedy completed two source-only runs (36 each) and all eight
contextual cases on iPhone 15 Pro Max, iOS 26.6.1. These are execution counts,
not quality passes. The artifact-verification autorelease-pool fix removed a
confirmed memory-resource failure during loading without changing model weights,
input tokens, quantization, or generation settings.

Observed model-load times: 3.87–4.86 s; median per-case times: 1.99–2.28 s.
The second run reached a sampled physical footprint of 3.218 GiB and both runs
observed thermal state serious. RSS alone substantially understates the relevant
footprint here. The prior failure reported a process high-water limit of 3376 MB;
that observed limit is not a safe budget or a universal iOS constant.

Recommendation remains research-only: TranslateGemma greedy is the strongest
observed candidate, but known semantic errors, thermal behavior and small
footprint margin prevent production acceptance. Do not substitute a fixed 1.5,
3 or 4 GiB budget for a whole-app measurement including WebKit.
