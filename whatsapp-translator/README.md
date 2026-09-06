# WhatsApp Translator

Desktop app: open a WhatsApp group, then translate each message to Polish with
its original below. Each translation uses previous and related messages as
context. Translations cached locally, retranslatable with a comment, editable by
hand. Known words stay untranslated (global list).
Outgoing messages are sent as typed — no auto-translation. Export sentence
pairs + unfamiliar-word list for language learning.

## Run

```bash
npm install
npm start
```

Scan the QR with WhatsApp → Linked devices. Session persists in `data/session`.

On first pairing, Baileys asks WhatsApp for full history. The sync can make
startup slow; messages are stored locally in `data/history.jsonl` and loaded
on later launches for contextual translation. Keep the app open until history
sync finishes. The app advertises WEB_BROWSER/Chrome because WhatsApp currently
rejects Baileys' Darwin Desktop sub-platform before showing a QR (Baileys #2677).

Bridge: **Baileys** (socket-based). The original whatsapp-web.js bridge was
switched after WhatsApp Web build 2.3000.1043270046 broke it upstream
(wwebjs issues #201845/#201838).

## Free-only routing (primary + one fallback)

Only explicitly free OpenRouter models are used, with at most one primary and
one fallback attempt. The default pair is:

1. `minimax/minimax-m3:free` — primary
2. `google/gemma-4-31b-it:free` — fallback

Routing is bounded: explicit per-attempt and total deadlines, cancellation on
chat switch, a small concurrency limit, and a temporary cooldown after
rate-limit/5xx errors. Free tier is quota-dependent: when the primary is
rate-limited or cooling down, the fallback is tried; when neither is
available, translation fails with a clear message instead of silently falling
back to a paid model. No paid-model fallback, no auto-router, no credit
purchase. Provider attempts are logged with model, status and timing.

The approved free-model list (see `src/free-router.ts`) is
`minimax/minimax-m3:free`, `google/gemma-4-31b-it:free`,
`z-ai/glm-5.2:free` and `nvidia/nemotron-3.5-lightning:free`; any other ID is
rejected. Benchmark against synthetic fixtures with `npm run benchmark`
(small live sample by default; results land in `../docs/translation-benchmark.json`).

Optional env: `OPENROUTER_API_KEY`. When absent, the key is read from Pi's
local `~/.pi/agent/auth.json` or `provider-keys.json` store (values stay local
to the Electron process). `WA_LEARNING_MODE=1` turns on opt-in learning mode:
known words are left untranslated in the Polish sentence.

## Vocabulary and hover meanings

Hover (or Tab-focus, or tap) a word in the original message to see its
contextual Polish meaning. Multi-word idioms are highlighted as a phrase and
show the whole-phrase meaning plus the literal meaning of each word. Meanings
are generated in one background request per inspected message and cached; a
cached hover is instant, and simultaneous hovers share one in-flight request.
Clicking a word still toggles it as a known word; Space/Enter toggle the
tooltip and known-word action from the keyboard.

Word tokens come from Unicode-aware segmentation with stable IDs; every token
is explained or explicitly unavailable, model-returned phrase spans are
validated, and names/handles are masked and reported as `nazwa własna`.
The cache key includes the source text, context, translation revision and
learning mode, so edited or retranslated messages never show stale meanings.

## Validation

Run `rtk npm run check` from `whatsapp-translator/`.
The self-check and regression suite use temporary cache/history/log storage
and mock provider fetches. Regression checks cover Unicode privacy across all
prompt fields, free-only routing (deadlines, cancellation, cooldown,
concurrency, incomplete-output rejection), vocabulary token/span validation,
cache-key revisioning, socket send/reply persistence, echo deduplication,
cache races, outgoing context, and media loading.
Run `rtk npm run check:electron` for the real Electron main process, preload, and
renderer with a mocked gateway and translator. It uses synthetic messages and
temporary storage. It checks A→B→A history/translation/edit races, 135-message
pagination and scroll preservation, inline reply/correction recovery, send
retries, echo deduplication, and asynchronous live images. An expected synthetic
delivery-error trace is printed while testing failed sends and replies.

These checks do not connect to live WhatsApp or translation providers. Live
pairing, delivery acknowledgments, media downloads, and translation quality
require separate verification.

For changes to chat or translation flows, additionally verify:
- Delayed history and translation results cannot enter another selected chat.
- Successful sends appear locally; failed sends preserve the draft.
- Reply and correction input work inside Electron.
- Privacy masking covers Unicode names and every provider-bound prompt field.
- Long messages are translated completely or explicitly reported as incomplete.
- Stale hover results cannot replace the current tooltip after a chat switch.

### TypeScript build

The whole app (main, preload, `src/`, renderer) and all tests are TypeScript
(strict). `tsc` emits CommonJS to `dist/` (paths mirror `src/` so requires are
unchanged); `esbuild` bundles the renderer into a single IIFE
`dist/renderer/bundle.js`, which `renderer/index.html` loads as one script.

- `npm run build` — type-checked compile + renderer bundle (also runs before
  every check script)
- `npm run typecheck` — strict `tsc` over the whole tree
- `npm run check` — compiled unit suites in `dist/test/`
- `npm run benchmark [count] [model-ids]` — live free-provider benchmark
  against synthetic fixtures in `test/translation-cases.ts`
- `npm run check:electron` — real Electron smoke from `dist/test/`

Tests set `WA_DATA_DIR` to a temp directory **before** importing `src/`
modules; cache/history/log paths are resolved lazily so isolation holds even
if import order changes.
Use synthetic messages and mocked providers for regression checks.

## Data

- `data/cache.json` — translations + global known-word list + contextual
  vocabulary cache (bounded to 500 entries)
- `data/translation-log.jsonl` — append-only translation/retranslation requests,
  provider attempts, masked model prompts and request payloads, timings, fallback
  decisions, cache events, and errors
- `data/history.jsonl` — locally persisted WhatsApp group messages and history sync
- `data/session/` — WhatsApp session
- `data/export/learning-YYYY-MM-DD.json` — sentences + unfamiliar-word list

Translation logs record message IDs, hashes, lengths, providers, statuses, and
timings. Each attempt also records the masked prompt and provider request shape
so the model input can be audited locally; names and handles are masked before
provider calls and in these prompt records. Set `WA_TRANSLATION_LOG_CONTENT=1`
before starting the app if you also want the unmasked local input/output text
included in the ordinary input/output records.
