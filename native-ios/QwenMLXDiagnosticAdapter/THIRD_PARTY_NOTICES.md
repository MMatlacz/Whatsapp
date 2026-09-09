# Third-party notices for the diagnostic MLX package

This file records the direct third-party inputs added for the P0.2b diagnostic
package. It does not change the repository's own PolyForm Noncommercial license.

| Component | Pinned input | License | Purpose |
| --- | --- | --- | --- |
| MLX Swift LM | `ml-explore/mlx-swift-lm` 3.31.3 | MIT | Local MLX model loading/generation |
| Swift Transformers | `huggingface/swift-transformers` 1.3.4 | Apache-2.0 | Local tokenizer/chat-template loading |
| Qwen3 MLX artifact | `mlx-community/Qwen3-0.6B-4bit` at `73e3e38d981303bc594367cd910ea6eb48349da8` | Apache-2.0 | Diagnostic model candidate |

The Swift package dependencies are fetched from their upstream repositories;
their copyright and license files remain part of those packages. The Qwen model
weights are not committed or bundled by this change. Any later redistribution
must preserve applicable upstream notices and be reviewed separately from this
diagnostic experiment.
