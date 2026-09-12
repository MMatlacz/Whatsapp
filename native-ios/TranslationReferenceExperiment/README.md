# Local translation reference experiment

Diagnostic macOS research only. This package is separate from the native app and
does not enable production routing. Model acquisition is an explicit `provision`
command; `run` checks every artifact's SHA-256 and uses local files with Hub offline
mode enabled. Store the environment and model directory outside the repository.

Use Python 3.12 with `torch==2.10.0`, `transformers==5.3.0`,
`mlx-lm==0.31.1`, and `sentencepiece==0.2.2`. The report records the installed
runtime versions; it does not assume that Python MLX and Swift MLX are identical.

```sh
python reference.py provision --model m2m100 --models /absolute/external/models
python reference.py run --model m2m100 --models /absolute/external/models \
  --corpus ../../docs/native/p0.2d3-bakeoff/candidates/qwen3.5-0.8b-4bit/report.json \
  --output /absolute/output/m2m100-source-only.json
```

Run from this directory. Supported IDs are `m2m100`, `nllb`, `qwen`, and
`qwen-mlx`; the source pins their immutable revisions. Each run uses one process.
Defaults are CPU float32 for Transformers and the snapshot's 4-bit precision for
Python MLX. `--device mps` selects Transformers bfloat16. Device and dtype are
recorded; macOS RSS is not an iPhone footprint or acceptance measurement.

## Predeclared comparison

1. Run the exact Qwen3.5 4-bit snapshot through Python MLX and official Qwen3.5
   higher-precision weights through Transformers, initially on simple fixtures.
   Both use the same minimal user prompt, native chat template, thinking disabled,
   greedy decoding, and 128-token output cap. Preserve the rendered prompt. This
   tests reference behavior, not numerical parity with the earlier sampled Swift
   structured-prompt run. Further matching controls are required if results differ.
2. Run M2M100 and NLLB on all 32 archived synthetic fixtures with `source-only`.
   The corpus contains 24 unique messages and eight context pairs: duplicate
   source-only rows are controls, not 32 independent meanings. No reference output
   or English meaning hint is fed into inference.
3. Use `--profile context` separately. Qwen gets bounded context with a target-only
   instruction. Encoder-decoder models get the context sentences followed by the
   target, with the whole output retained. This exploratory document translation
   is not a target-only chat adapter. Do not claim a context-contract pass by
   silently extracting or discarding translated sentences.
4. Review meaning, hallucination, Polish fluency, preservation, and context benefit
   separately using the existing 0–2 rubric. Context-free outputs must not be
   penalized for information absent from their input. Record uncertainties rather
   than inventing a speaker's gender. Candidate approval requires all hard gates;
   benchmark execution alone does not approve a model.

After the greedy baseline, `--beams 5` is a separate encoder-decoder decoding
control. Report its results separately rather than replacing the greedy exports.
All reference timings may include concurrent host workloads and are diagnostic,
not a performance ranking.

Transformers 5.3.0's `AutoTokenizer` resolved this pinned NLLB snapshot to a generic
`TokenizersBackend`, whose source-language suffix was `<unk>`. The harness uses
`NllbTokenizer` explicitly and fails unless the encoded input begins with the
correct source-language token. Both language IDs and a tokenized probe are saved.
The initial NLLB run from `5ecb111` is invalid and must be excluded from quality
comparisons; its raw export is retained only as tokenizer-failure evidence.

NLLB weights are CC-BY-NC-4.0 and described as research-only by their model card.
They are a noncommercial research reference, not an approved commercial app
dependency or distillation teacher. M2M100 is MIT and Qwen Apache-2.0. No model
weights are redistributed here. Review output/redistribution rights separately
before using these experiments for training or a paid product.

The output records source SHA, dirty state, script/corpus hashes, full artifact
manifest, actual input, raw output, and token IDs where available. Start acceptance
runs from a clean source commit. Historical dirty-tree runs remain diagnostics.
