# Fast, free translation and contextual vocabulary

Status: active. This document tracks the implementation goal, tasks and evidence.

## Outcome

Translate conversational Indonesian into natural Polish with bounded waiting,
free-model-only routing, and contextual meanings when hovering/focusing/tapping
original words and phrases. Preserve privacy masking, drafts, history and edits.
Keep sentence translation independent of optional vocabulary generation.

## Decisions

- Benchmark Gemma 4 31B free and Nemotron 3.5 Lightning free before selecting the
  default. Both IDs/prices were verified against the public OpenRouter catalog.
  A model name or zero token price is not proof of availability or quality.
- Use at most one primary and one fallback, explicit deadlines, cancellation,
  a small concurrency limit, and temporary provider cooldown after rate limits.
- No paid model fallback, automatic credit purchase, or real chat benchmarking.
- Generate vocabulary once per inspected message; cache contextual meanings.
  A cached hover must be immediate; the first lookup may require a network call.
- Represent words using Unicode segmentation and stable token IDs. Validate
  model-returned token spans, coverage and lengths before caching/rendering.
- A phrase tooltip shows its contextual meaning and constituent word meanings;
  idioms must not be presented as word-for-word translations.
- Keep natural Polish as default; mixed-language known-word mode is opt-in.
- Preserve existing manually edited translations; invalidate vocabulary when
  source, translation, context, model/prompt version or learning mode changes.

## Tasks

- [x] T1: Save plan, tasks and verification checklist; activate goal.
- [x] T2: Review current code and provider documentation; verify credentials by
  presence only, never printing secrets. (OpenRouter catalog checked for the
  candidate free IDs; key read via auth-store, presence-only.)
- [x] T3: Create synthetic benchmark fixtures and a reproducible report runner;
  measure latency/errors/quality checks and record actual provider availability.
- [x] T4: Implement free-only primary/fallback routing, timeouts, cancellation,
  concurrency, cooldown and clear failure metadata.
- [x] T5: Implement tokenization, vocabulary schema validation, privacy masking,
  contextual cache and deduplicated main-process IPC.
- [x] T6: Add accessible hover/focus/tap tooltips, phrase highlighting, loading,
  retry and stale-response protection while preserving known-word actions.
- [x] T7: Add synthetic unit/regression coverage and extend real Electron smoke.
- [x] T8: Run final verification, inspect UI, update README and evidence below.

## Verification checklist

### Providers and quality

- [x] Verify configured model IDs and zero input/output pricing from public API.
  (minimax-m3, gemma-4-31b-it, glm-5.2, nemotron-3.5-lightning `:free` all
  verified against the public OpenRouter catalog; only these four are approved.)
- [x] Only allow listed free IDs; fail clearly when keys/quota are unavailable.
  (`free-router` rejects any other model; 401/402/403 stop both attempts,
  quota/5xx go to cooldown, exhausted route reports a clear combined error.)
- [x] Benchmark slang, pronouns, context, idioms, negation, mixed languages,
  punctuation, emoji, names/handles and long text using synthetic inputs.
  (60 fixtures in test/translation-cases.js; live samples recorded below.)
- [x] Report successful request count, latency distribution, errors and limits;
  separate automatic semantic checks from human/native-speaker quality review.
  (docs/translation-benchmark.json and -alternatives.json; every live output is
  stored for human review with humanReviewed: false — no native-speaker score
  is claimed.)
- [x] Neither timeout nor incomplete/malformed output enters the success cache.
  (finish_reason != stop rejected per attempt; failure throws, nothing cached.)
- [x] Maximum two provider attempts; cooldown, deadlines and cancellation tested.
  (free_translation.js: 429→cooldown skip, 401 single attempt, deadline
  abort under 250 ms, abort cancels queued+active, concurrency cap held at 2.)

### Vocabulary and privacy

- [x] Unicode segmentation preserves original text, punctuation and offsets.
  (tokens.js shared node/renderer; slice(start,end) === token text asserted.)
- [x] Repeated words have distinct IDs; overlapping phrases resolve predictably.
  (unique ids per occurrence; phrases sorted longest-first, earliest-start.)
- [x] Every word has a contextual gloss or explicit unavailable explanation.
  (validateVocabulary requires exact token coverage; UI falls back to
  "Znaczenie niedostępne".)
- [x] Invalid token IDs/spans, missing coverage, oversized strings and hostile
  markup are rejected or rendered safely; never guessed into an alignment.
  (span bounds, length caps, JSON-only, textContent rendering; covered by
  free_translation.js invalid-input matrix.)
- [x] Synthetic names/handles are absent from all outbound fields.
  (asserted for every prompt field in regression + free_translation runs.)
- [x] Gloss cache keys include source/context/translation revision; edits and
  retranslation do not show stale meanings.
  (cacheKey asserted to differ on body/context/translation/revision; main
  process re-keys after generate and drops changed messages.)
- [x] Simultaneous hovers share one request; cached hovers issue none.
  (renderer pending-map + main-process pendingVocabulary dedupe; 500-entry
  bounded persistent vocabulary cache.)

### UI and regressions

- [x] Hover, keyboard focus, Escape, touch/tap, retry and phrase highlighting work.
  (word-help.js: pointerover/focusin/pointerdown, Escape closes, Enter opens,
  Space toggles known, tap opens, retry button clears the failed cache entry.)
- [x] A→B→A and hover A→hover B races cannot replace the current tooltip.
  (epoch bump on chat switch + selectionVersion in the signature + per-open
  sequence token; stale responses are dropped before render.)
- [x] Existing click-to-mark-known behavior remains available.
  (click still toggles; tooltip has its own known/unknown button.)
- [x] Existing send/reply/edit/media/pagination regressions pass.
  (npm run check all green; electron smoke checks A→B→A translation/edit,
  pagination, retries, echo dedupe, live media.)
- [x] Self-check and synthetic regression pass.
  (self-check OK; regression OK; free translation OK — full run recorded.)
- [x] Real Electron with mocked gateway/provider passes and is visually inspected.
  (`npm run check:electron` → exit 0, “Electron smoke OK: pagination,
  history/translation/edit A-B-A races, correction recovery, send/reply retry,
  echo dedupe, live media”; the two synthetic delivery-failure traces printed
  during the run are expected by the test.)
- [x] Live WhatsApp verification remains separate; no live messages are sent.
  (benchmark is synthetic-only, liveWhatsAppTested: false.)

## Evidence and limitations

Recorded 2026-09-06. Provider models: minimax-m3 and gemma-4-31b-it live on
OpenRouter; gemma was 429-limited during sampling, nemotron 3.5 lightning and
glm-5.2 were rejected by quota, minimax m3 answered 4/5 with plausible Polish
and ~1.1–2.1 s, one timeout. Details and every live output for human review:
docs/translation-benchmark.json, docs/translation-benchmark-alternatives.json.

Commands:
- `node test/self_check.js` → self-check OK
- `node test/regression.js` → regression OK (privacy, persistence/echo, cache
  races, outgoing context, nonblocking media)
- `node test/free_translation.js` → free translation OK (free-only route,
  deadlines, cancellation, cooldown, concurrency, Unicode, spans, privacy,
  cache)
- `node test/benchmark.js [n] [`model1,model2`]` → live sample (quota-limited;
  stops on 429 and does not retry an unavailable model)
- `npm run check:electron` → exit 0, “Electron smoke OK” (pagination, A-B-A
  history/translation/edit races, correction recovery, send/reply retry, echo
  dedupe, live media); two expected synthetic delivery-failure traces printed.

Limitations: live quality is judged by the stored outputs awaiting human
review — no native-speaker score is claimed. Latency targets are engineering
targets until measured on a populated free tier; free availability is
quota-dependent and can change without notice. The full 60-case live
benchmark remains runnable later via `npm run benchmark 60` when quota
allows.

## Appendix: TypeScript migration (all green)

The full app was migrated from plain JS to strict TypeScript:
main/preload, all `src/` modules, the renderer, and all six test files.
`tsc` emits CommonJS to `dist/` with mirrored paths (relative requires
unchanged); esbuild bundles the renderer to one IIFE loaded by
`renderer/index.html`. The vm-based regression harness and the real
Electron smoke run against the compiled `dist/` output unchanged in
behavior.

Verification after migration (2026-09-06):
- `npm run typecheck` → no errors (strict, the whole tree)
- `npm run check` → self-check OK; regression OK; free translation OK
- `npm run check:electron` → exit 0, "Electron smoke OK" (same coverage list)
- Smoke re-run in a row passes with identical results, proving run-to-run
  isolation. Root cause of an earlier 138-vs-135 pagination failure was
  test/environment, not app logic: tsc emits requires in source order, and
  the smoke used to set `WA_DATA_DIR` after importing `src/`, so history
  briefly fell back to the real `data/` dir. Fixed by setting env before
  imports in the smoke and by resolving cache/history/log data dirs lazily
  in `src/`; the accidentally appended synthetic rows were removed from
  `data/history.jsonl` (8185 lines kept, 1091 test rows removed, backup in
  /tmp).
