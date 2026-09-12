# Agent quality review

Provisional agent review of every unique source-only output from the primary
decoding settings. This is not independent bilingual human validation. Scores
are `M/H/G/T`: meaning, hallucination control, Polish grammar, tone/preservation.
Each axis uses 0=incorrect, 1=partial, 2=acceptable. `M=2,H=2` is the semantic
screening gate; passing those two axes alone does not approve production use.

Rows identify `semanticCaseID` in the raw JSON. Eight repeated source-only rows
have identical input/output to their paired rows and inherit the same score;
they are not counted as independent evidence. Source-only review does not demand
Rina's name or female gender when that information exists only in context. Gender
defaults and lost emphasis can reduce T without automatically failing M/H.

Primary settings: M2M100 and corrected NLLB use five beams, Qwen Python MLX uses
greedy decoding. The invalid NLLB tokenizer run is excluded. Greedy M2M100/NLLB
runs are diagnostic decoding controls, not independently certified alternatives.

| Semantic case | M2M100 beam 5 | NLLB beam 5 | Qwen Python MLX 4-bit | Main review point |
| --- | --- | --- | --- | --- |
| straight-arrival | 2/2/2/1 | 2/2/2/2 | 1/1/0/0 | Dedicated models convey arrival/home; Qwen produces malformed location phrasing. |
| straight-plan | 1/2/1/1 | 2/2/1/1 | 0/0/0/0 | M2M100 has `zjedziemy`; NLLB is understandable but unnatural; Qwen changes day/time. |
| straight-thanks | 2/2/2/1 | 1/2/2/1 | 0/0/0/0 | NLLB omits today; M2M100 retains it. |
| dia-late | 2/2/2/1 | 2/2/2/1 | 1/2/2/1 | Qwen omits later. The source alone does not identify Rina. |
| omitted-subject-finished | 1/2/1/1 | 0/1/0/0 | 0/0/1/0 | Readiness to send is not the same as already being sent. |
| particle-dong | 1/1/1/0 | 2/2/2/2 | 1/2/2/0 | M2M100 adds `Doh`; Qwen says we are waiting. |
| particle-sih | 2/2/2/1 | 2/2/2/1 | 0/0/0/0 | Dedicated models convey being startled, with reduced playful blame. |
| particle-nih | 2/2/2/1 | 2/2/2/1 | 2/2/1/1 | Qwen meaning is recoverable despite malformed `To je`. |
| particle-lah | 1/2/2/1 | 1/2/2/1 | 2/2/2/2 | `Zgoda, jutro` is an acceptable concise rendering. |
| particle-kok | 2/2/2/1 | 1/2/2/1 | 0/0/0/0 | NLLB shifts still-not-asleep to past tense. |
| particle-masa | 0/0/2/0 | 1/2/2/1 | 0/0/0/0 | NLLB asks when, not whether explanation is really needed again. |
| slang-wkwk | 0/0/2/0 | 0/0/2/0 | 0/0/0/0 | Wrong-group meaning is lost or reversed. |
| slang-mager | 0/0/2/0 | 0/0/2/0 | 0/0/0/0 | M2M100 says ugly; NLLB says thin; neither means unmotivated. |
| slang-baper | 0/0/0/0 | 0/0/2/0 | 0/0/0/0 | Do not take it personally is lost. |
| negative-gak | 2/2/2/2 | 2/2/2/2 | 2/2/1/1 | The inability to join tonight is conveyed. |
| negative-nggak | 0/0/2/0 | 0/0/2/0 | 1/1/1/0 | Invitation/prohibition is not no need to pick me up. |
| negative-ga | 2/2/2/1 | 2/2/2/1 | 0/0/1/0 | Dedicated models retain the departure question. |
| kinship-bapak-tante | 0/0/2/0 | 2/2/2/1 | 0/0/0/0 | NLLB retains father/aunt; alternatives substitute relatives. |
| code-switch-meeting | 0/0/2/0 | 0/0/2/0 | 0/0/0/0 | Both dedicated models change postponed into cancelled. |
| joke-treat | 0/0/1/0 | 0/0/1/0 | 0/0/0/0 | Paying for the meal is lost; Qwen repeats text. |
| quoted-reply | 2/2/2/1 | 2/2/2/1 | 0/1/2/0 | Dedicated models convey not being angry, with reduced reassurance. |
| omitted-dia-station | 0/0/2/0 | 1/2/2/1 | 0/0/0/0 | M2M100 changes pickup at station into taking to station; NLLB omits later. |
| particle-combo | 1/2/1/1 | 1/2/2/1 | 0/1/2/0 | M2M100 loses how; NLLB omits seriously. |
| negative-mixed | 0/0/1/0 | 0/0/2/0 | 0/0/0/0 | Ugly/fat replaces lazy, changing the negated proposition. |

Semantic gates: M2M100 **9/24**, corrected NLLB **10/24**, Qwen Python MLX
**3/24**. These small-corpus, judgment-sensitive counts are not a significant
ranking between M2M100 and NLLB. The substantive mistranslations are sufficient
to reject every configuration for acceptance testing.

## Context probes

The eight contextual outputs are reviewed separately. Encoder-decoder inputs
concatenate context and target, so these assess that input strategy, not a
trained context-aware target-only adapter. All raw outputs are retained.

`C=0` means no demonstrated useful benefit (including target omission); `C=1`
means a partial disambiguation despite a failed overall translation; `C=2` would
require successful useful contextual resolution. No run reaches C=2 here.

| Case | M2M100 C / finding | NLLB C / finding | Qwen Python MLX C / finding |
| --- | --- | --- | --- |
| dia-late | 0: target omitted; context translated | 0: target omitted; context translated | 0: same partial answer as source-only |
| omitted-subject-finished | 0: target omitted | 0: only a context reply | 0: planned/sending replaces finished/needs sending |
| particle-kok | 0: context replaces target question | 0: only a context sentence | 0: malformed target |
| negative-nggak | 1: first-person interpretation, but invitation replaces pickup | 0: translates offer, not refusal | 0: unrelated home statement |
| negative-ga | 0: extra context with distorted polarity | 0: context question returned with time instead of target-only answer | 0: invents cold days |
| kinship-bapak-tante | 0: target omitted | 0: target omitted | 0: leaves kinship words untranslated despite explicit context |
| quoted-reply | 0: repeated joke text, target omitted | 0: translates quoted context, not not-angry target | 0: repeated no, no, no |
| omitted-dia-station | 1: female reference, but pickup becomes invitation | 0: target omitted | 1: female reference, but wrong verb and malformed Polish |

Target-only usable translations: **0/8 for each of the three context strategies**.
Partial C does not override the meaning/contract failures. Apparent gains in a
pronoun cannot justify returning a wrong event or another message.

## Official Qwen higher-precision control

Official BF16 checkpoint, Transformers 5.3.0, CPU float32 arithmetic, greedy
decoding, identical minimal instruction to the Python MLX source-only control.
All 32 rows completed. The eight duplicates match; the following 24 unique rows
score **2/24** on M/H. This is no quality rescue and is not evidence that 4-bit
quantization is better: small-corpus counts and different runtimes do not support
that inference.

| Case | M/H/G/T | Finding |
| --- | --- | --- |
| straight-arrival | 0/0/2/0 | You are there at home replaces I have arrived. |
| straight-plan | 0/0/0/0 | Tomorrow/one becomes yesterday/nineteen. |
| straight-thanks | 2/2/2/2 | Correct thanks for help today. |
| dia-late | 1/2/2/1 | Later is omitted. |
| omitted-subject-finished | 0/0/2/0 | Already finished becomes not yet. |
| particle-dong | 1/2/0/0 | Malformed let us wait rather than please wait. |
| particle-sih | 0/0/0/0 | Malformed Polish; meaning not recoverable reliably. |
| particle-nih | 0/2/0/0 | Returns English instead of Polish. |
| particle-lah | 1/1/0/0 | Tomorrow remains but the rest is malformed. |
| particle-kok | 0/0/0/0 | Not a meaningful sleep question. |
| particle-masa | 1/1/0/0 | Explain again remains, but tense/question is wrong. |
| slang-wkwk | 0/0/0/0 | Wrong group is lost. |
| slang-mager | 0/0/0/0 | Unmotivated meaning is lost. |
| slang-baper | 1/1/1/0 | Leaves baper untranslated and changes joking to playing. |
| negative-gak | 2/2/1/1 | Cannot join this evening is recoverable. |
| negative-nggak | 0/0/0/0 | Wrong participant and malformed pickup verb. |
| negative-ga | 0/0/2/0 | Asks whether you want to leave, losing the no-longer premise. |
| kinship-bapak-tante | 0/0/0/0 | Kinship roles and Polish are wrong. |
| code-switch-meeting | 0/0/0/0 | Meaning lost despite partly Polish words. |
| joke-treat | 0/0/1/0 | Late again and paying for a meal are lost. |
| quoted-reply | 0/0/2/0 | Not angry becomes not satisfied. |
| omitted-dia-station | 0/0/1/0 | Pick up becomes write. |
| particle-combo | 0/0/1/0 | Seriously/how possible is not preserved. |
| negative-mixed | 0/0/0/0 | Lazy versus tired contrast is lost. |
