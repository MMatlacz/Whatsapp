# Kilo auto free integration design board

Status: implemented proposal; Kilo's loopback server transport is active, while
fallback priority remains configurable.

## Evidence

- [Kilo auto free test](../sources/api/kilo-auto-free.md) — the CLI route works
  with context and selected `stepfun/step-3.7-flash`.
- [Current translator module](../output/modules/translator.md) — the app already
  has a contextual provider chain, name/handle masking, retries, and local audit
  records.
- [OpenRouter free evidence](../sources/api/openrouter-free.md) — an existing
  official free-model fallback remains available.

## Proposed boundary

Keep the translator's provider contract unchanged:

```text
tryKiloAutoFree(maskedTarget, maskedPrompt) -> translatedText
```

The adapter owns transport details and returns only model text. The chain keeps
context construction, placeholder restoration, no-op/retranslation checks, and
fallback accounting in `translator.js`.

Configuration boundary:

- `KILO_API_KEY` is read from the process environment or a dedicated local
  provider store; never commit it, copy it to `data/`, or write it to logs.
- Do not source `~/.config/zsh/secrets.zsh` from Electron. Shell files can execute
  arbitrary commands and are not a stable application configuration interface.
- The adapter receives an explicit base URL/config object. Do not invent a Kilo
  endpoint until the API documentation or a successful authenticated probe
  confirms it.

## Transport options

| Option | Evidence | Shape | Risk / open question |
|---|---|---|---|
| Kilo loopback HTTP server | Implemented and live-tested | `POST /session`, then `POST /session/{id}/message` with `kilo-auto/free` | Requires `kilo serve --pure` on loopback; server owns the key |
| Kilo CLI subprocess | Verified by the live test but not used by the app | `kilo run --pure --model kilo/kilo-auto/free --format json ...` | Node child invocation is not reliable; retained as a diagnostic path |
| OpenRouter `openrouter/free` | Verified separately | Existing OpenRouter fetch adapter | Different router/model pool; not Kilo and may select a weaker free model |

The app uses the loopback HTTP transport; the CLI remains diagnostic only.

## Candidate chain placement

The candidate insertion point is after the existing contextual LLM providers and
before keyless translation fallbacks:

```text
OpenCode Zen -> Kilo auto free -> OpenRouter :free -> Google -> MyMemory -> LibreTranslate
```

This is a placement proposal, not an adjudicated choice. The human should decide
whether Kilo precedes OpenRouter or replaces it.

## Request and response logging

For every Kilo attempt, append the same local audit events already used by the
translator:

- provider: `kilo-auto-free`
- engine: `kilo`
- requested model: `kilo/kilo-auto/free`
- routed model: response metadata when supplied (for example
  `stepfun/step-3.7-flash`)
- endpoint/transport, attempt index, duration, status, and redacted error
- masked prompt and request payload; never the API key

The existing `model_prompt`/`model_request` records are the target logging shape.

## Acceptance tests for implementation

1. A synthetic contextual Indonesian test resolves a vocative like `Eda` and an
   omitted subject/object; no WhatsApp text is needed for the provider smoke test.
2. The adapter sends the full masked rolling prompt, not only the target sentence.
3. A missing key skips Kilo cleanly and continues the chain.
4. 401/403, 429, 5xx, malformed JSON, and timeout errors are logged without
   exposing authorization headers.
5. A successful response records both requested and routed model when available.
6. Existing name/handle masking, cache replacement, no-op rejection, and fallback
   behavior remain unchanged.
7. Unit tests mock the transport; one opt-in live test uses synthetic text only.

## Human decisions still needed

- Whether Kilo should remain before OpenRouter in the contextual fallback chain.
- Whether the separate `kilo serve --pure` process should be supervised by the
  app launcher rather than started manually.
- Whether a ~27-second free route is acceptable for interactive retranslation.
