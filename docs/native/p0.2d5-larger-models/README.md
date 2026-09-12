# Larger local translation models

Status: experiment in progress. No candidate accepted or production route enabled.

The 1.5 GiB historical screening target is not an exclusion criterion here.
Quality is screened on macOS first; actual phone memory, latency, thermal state
and stability must then be measured alongside the application. macOS RSS and
simulator results are not physical-device acceptance.

## Predeclared comparison

- Source corpus: 24 unique regression inputs plus 12 newly authored synthetic
  inputs, frozen before seeing any 4B outputs. The new inputs are not independent
  human-authored or bilingual-validated data. Report these splits separately.
- Context corpus: eight regression targets with their existing bounded context.
  Compare against the corresponding source-only outputs, allowing gender defaults
  when source-only inputs omit that information.
- Qwen3 4B: thinking off and on, both with temperature 0.6, top-p 0.95, top-k 20,
  seed 42. Matching sampling isolates the thinking switch. The official card
  recommends these settings for thinking and discourages greedy decoding.
  Non-thinking's recommended 0.7/0.8 is a separate possible control.
- Non-thinking cap: 512 generated tokens. Thinking cap: 2048 initially; any capped
  run is an incomplete-generation result, with a separate 8192-token retry needed
  before attributing that case to translation ability. Do not silently replace runs.
- Gemma and TranslateGemma: no thinking switch; use their native templates.
  TranslateGemma receives structured `id`/`pl` language codes. Its context profile
  is explicitly experimental labelled context inside the source text, not a proven
  context adapter. Preserve its whole output; do not cherry-pick sentences.
- Keep raw text, model-generated reasoning, final translation, tokens, stop reason,
  exact rendered input, input messages, seeds, revisions and hashes. Only the text
  after Qwen's closing reasoning marker is the final translation. Missing closing
  markers and token caps are separate failures, not successful answers.
- Score major semantic changes, small omissions, fluency and tone separately.
  No expected meanings or review hints enter prompts. Agent scoring remains
  provisional; do not call it independent bilingual validation.
- Run inference sequentially, one model process at a time. Use local Xcode checks;
  do not use CI for validation.

## Model access and terms

Public metadata and revisions are in `candidate-discovery.json`. Official cards:

- https://huggingface.co/Qwen/Qwen3-4B
- https://huggingface.co/google/translategemma-4b-it
- https://huggingface.co/google/gemma-3-4b-it

Qwen3 is Apache-2.0. Gemma and TranslateGemma use the Gemma Terms of Use:
https://ai.google.dev/gemma/terms (read 2026-09-12, page dated 2026-04-01).
These permit use subject to restrictions; redistribution requires the agreement,
use restrictions, notices and modification notices. Local research does not
approve bundling weights in this repository or commercial distribution.
Google claims no rights in generated outputs, but distillation may constitute a
Model Derivative under these terms. Weights stay outside Git.

The QAT MLX Gemma card at revision
`3d9ef289111449933c22761961f16a5df237ce2a` names an unrelated InternVL model and
Qwen license although its configuration is Gemma3. This is a metadata discrepancy,
not proof of corrupt weights. Do not treat that license metadata as authoritative.
The ordinary MLX 4-bit card also names the pretrained rather than instruction
base model; resolve lineage before relying on it as an IT comparison.

Official TranslateGemma documents 55 languages and 2K input tokens. Its native
template must actually accept `id` and `pl`; generic multilingual marketing alone
does not establish this pair's quality. Qwen and Gemma cards state 100+ and 140+
languages respectively; direct Indonesian-to-Polish quality remains to be tested.

## Harness

`native-ios/TranslationReferenceExperiment/larger_models.py` uses the existing
external Python environment (MLX 0.32.2, mlx-lm 0.31.1). All model artifacts are
hash-checked before loading and Hub/Transformers offline modes are enabled.
`chub search mlx` returned no relevant MLX entry, so API signatures and generation
stop semantics were checked against the installed version's source/docstrings.
Initial smoke runs from a dirty tree are diagnostic only. Full acceptance evidence
must identify a clean source commit.
