# Code Review Findings

Living review log for the WhatsApp Translator project.

Last updated: 2026-09-06

## Review scope

Current review focuses on:

- correctness and race conditions
- privacy and local data handling
- Electron security boundaries
- WhatsApp/Baileys integration
- LLM context quality and prompt construction
- maintainability and packaging

Use this document as the canonical review log. New findings should be added here, and resolved items should be moved to **Resolved findings** with the fixing commit/PR when known.

## Open findings

### F-001 — High — Conversation context loses speaker identity

**Area:** translation quality / contextual reasoning  
**Files:** `whatsapp-translator/main.ts`, `whatsapp-translator/src/translator.ts`

`contextFor()` supplies the last several message bodies to the translator but does not preserve who said each message. Sender names are collected separately for privacy masking only.

This weakens the exact capability the product is trying to improve with an LLM: resolving omitted Indonesian subjects, pronouns, teasing, slang, relationship references, and multi-speaker ambiguity.

**Recommended fix**

Represent context as structured speaker turns with stable per-chat pseudonyms, for example:

```text
Person1: iya nanti
Person2: gak tau dia
Person1: udah dari kemarin
```

Do not expose real participant names to the provider. Keep pseudonym assignment stable within each conversation/context window.

**Status:** Open

---

### F-002 — High — Electron renderer boundary is not fully hardened

**Area:** application security  
**Files:** `whatsapp-translator/main.ts`, `whatsapp-translator/preload.ts`, `whatsapp-translator/renderer/index.html`

The application correctly uses `contextIsolation: true` and `nodeIntegration: false`, but the BrowserWindow is not sandboxed. There is also no Content Security Policy and no explicit denial of unexpected navigation/new-window creation.

The preload API is powerful: it can read chats, send/reply to messages, invoke translations, modify cached translations, and export data. A renderer compromise therefore has a high impact.

**Recommended fix**

- enable `sandbox: true`
- add a restrictive CSP to the renderer
- deny or strictly allow-list navigation
- deny unexpected `window.open` calls with `setWindowOpenHandler`
- keep the preload surface minimal and validate IPC arguments in the main process

**Status:** Open

---

### F-003 — High — Sensitive application data is stored relative to the app/source tree

**Area:** privacy / packaging / reliability  
**Files:** `whatsapp-translator/src/gateway.ts`, `whatsapp-translator/src/cache.ts`, `whatsapp-translator/src/history.ts`, `whatsapp-translator/src/translation-log.ts`, `whatsapp-translator/src/export.ts`

WhatsApp linked-device credentials, history, caches, and logs are stored under project-relative `data/` paths. This is unsuitable for a packaged application and makes protection, migration, backup behavior, and permissions harder to control.

There is also an inconsistency: cache/history/log honor `WA_DATA_DIR`, while `export.ts` writes to its own hard-coded `data/export` path.

**Recommended fix**

Have the Electron main process resolve one application data root using `app.getPath('userData')` and inject/pass that location to all persistence modules. Keep tests able to override it.

Consider OS-protected storage for linked-device credentials where practical.

**Status:** Open

---

### F-004 — High — Full masked LLM prompts are logged in plaintext by default

**Area:** privacy / observability  
**File:** `whatsapp-translator/src/translation-log.ts`

Ordinary input/output logging is hash-only by default, but `modelPrompt()` always writes the complete prompt to `translation-log.jsonl`.

Known participant names and handles are masked, but the log can still contain target messages and multiple contextual messages including addresses, phone numbers, personal details, URLs, and other sensitive content.

This duplicates sensitive conversation content outside the history store and increases exposure.

**Recommended fix**

Make full prompt logging opt-in. Default logging should retain metadata such as hashes, lengths, model, latency, status, fallback decisions, and request IDs without plaintext prompt content.

**Status:** Open

---

### F-005 — Medium/High — History JSONL grows indefinitely and can duplicate synced records

**Area:** persistence / scalability  
**File:** `whatsapp-translator/src/history.ts`

History is append-only JSONL. In-memory state performs effective upserts, but persisted full-history syncs can append records already present on disk. The file therefore grows indefinitely and can contain duplicate versions of the same message.

This also makes indexed pagination, updates, retention, and compaction harder.

**Recommended fix**

Move message/history persistence to SQLite with a unique key such as `(chat_id, message_id)`. Use real upserts and indexes on chat/timestamp.

Translations and vocabulary caches are also good candidates for the same database once the schema exists.

**Status:** Open

---

### F-006 — Medium — Media is downloaded even when the renderer will not display it

**Area:** performance / memory / network use  
**Files:** `whatsapp-translator/main.ts`, `whatsapp-translator/src/gateway.ts`, `whatsapp-translator/renderer/app.ts`

`loadMedia()` attempts to download any supported media message and converts it to a base64 data URL. The renderer only renders actual media content for images; other media types are represented as a label such as `[media: videoMessage]`.

Large videos/audio/documents can therefore be downloaded and base64-encoded unnecessarily.

**Recommended fix**

- only auto-load media types that are displayed
- preferably lazy-load media when requested or when an image enters the viewport
- avoid base64 IPC for large payloads where possible

**Status:** Open

---

### F-007 — Medium — Known-word casing is inconsistent in the renderer

**Area:** correctness / UI state  
**Files:** `whatsapp-translator/src/cache.ts`, `whatsapp-translator/renderer/app.ts`

The cache preserves the original spelling of known words while deduplicating case-insensitively. The renderer stores returned words directly in a `Set`, but later checks membership using `w.toLowerCase()`.

Example: a stored word `Halo` does not equal a lookup for `halo` in a case-sensitive `Set`.

**Recommended fix**

Normalize the renderer's membership set, for example:

```ts
new Set(words.map((w) => w.toLocaleLowerCase()))
```

Keep a separate display list if preserving the user's original casing is desirable.

**Status:** Open

---

### F-008 — Medium — Pagination cursor type does not match runtime value

**Area:** type safety / API contract  
**Files:** `whatsapp-translator/src/types.ts`, `whatsapp-translator/src/gateway.ts`, `whatsapp-translator/main.ts`, `whatsapp-translator/renderer/app.ts`

`PageResult.cursor` is declared as `string | null`, but the gateway actually returns an object containing `timestamp` and `id`. Casts through `unknown`/`never` hide the inconsistency.

**Recommended fix**

Define a shared cursor type, e.g.:

```ts
interface MessageCursor {
  timestamp: number;
  id: string;
}
```

Use it consistently in gateway, IPC DTOs, main process, renderer, and tests.

**Status:** Open

---

### F-009 — Medium — `previousTranslation` is passed but never used during retranslation

**Area:** translation behavior  
**Files:** `whatsapp-translator/main.ts`, `whatsapp-translator/src/translator.ts`

The main process passes the existing translation into `translateChain()` when retranslating, and `TranslateOptions` exposes `previousTranslation`, but prompt construction does not include it.

This makes correction comments less effective when they refer to the previous result.

**Recommended fix**

When `force/retranslate` is used, optionally include the previous translation in a clearly delimited data field together with the user's correction/comment.

Do not include it for normal first-pass translation unless there is a specific quality reason.

**Status:** Open

---

### F-010 — Medium — Translation instructions and untrusted chat content share one user prompt

**Area:** LLM robustness / prompt injection  
**Files:** `whatsapp-translator/src/translator.ts`, `whatsapp-translator/src/free-router.ts`

The translator builds one large text prompt and sends it as a single `user` message. Conversation messages are untrusted data and can contain text that attempts to override translation instructions.

There are no tools attached, so this is primarily a translation-fidelity risk rather than a system-compromise risk.

**Recommended fix**

Use a system message for immutable translator behavior and send the target/context as structured user data. Explicitly delimit context and target message fields.

Keep local output validation and placeholder validation.

**Status:** Open

---

### F-011 — Medium — Reconnect strategy does not distinguish terminal and transient disconnects

**Area:** WhatsApp/Baileys reliability  
**File:** `whatsapp-translator/src/gateway.ts`

Any socket close schedules `startSocket()` again after three seconds. Logout/authentication-invalid states should not be retried indefinitely, and transient failures should normally use bounded exponential backoff with jitter.

**Recommended fix**

Inspect Baileys disconnect reasons and classify them into:

- terminal: logged out / invalid credentials / pairing required
- transient: network/server interruption

Use exponential backoff for transient reconnects and surface terminal states to the UI.

**Status:** Open

---

### F-012 — Low/Medium — Opening a group also refreshes all group metadata

**Area:** responsiveness  
**File:** `whatsapp-translator/renderer/app.ts`

`selectGroup()` calls `getGroups()` again before loading the selected group's page. Chat opening therefore depends on refreshing all participating group metadata.

**Recommended fix**

Cache group metadata from connection/history events and make opening a chat independent of a full group refresh.

**Status:** Open

---

### F-013 — Low/Medium — Profile-picture lookup can slow message DTO conversion

**Area:** responsiveness / network use  
**File:** `whatsapp-translator/src/gateway.ts`

`toMessageDTO()` awaits `profileOf()`, and the first lookup for a participant can perform a network request for the profile picture. Loading many messages from many participants can therefore become serially network-bound.

**Recommended fix**

Return message DTOs immediately with cached/basic identity data, then fetch profile images asynchronously and patch the renderer later.

**Status:** Open

## Positive observations

These are intentional design choices worth preserving:

- `contextIsolation: true` and `nodeIntegration: false` are already enabled.
- Renderer message text is escaped before HTML insertion.
- Translation requests support cancellation and stale-result protection.
- Manual edits are protected against late translation results.
- Free-provider routing is bounded to approved model IDs with explicit deadlines, cooldowns, concurrency limits, and no silent paid fallback.
- Incomplete provider responses are rejected rather than silently cached.
- Unicode-aware name/handle masking has meaningful regression coverage.
- Vocabulary output is locally validated before caching.
- Synthetic tests cover important translation, persistence, and renderer races.

## Recommended near-term order

1. F-001 — speaker-aware contextual representation
2. F-002 — Electron hardening
3. F-003 — centralize secure app-data storage
4. F-004 — stop plaintext prompt logging by default
5. F-007 / F-008 / F-009 — small correctness fixes
6. F-005 — SQLite migration
7. F-006 / F-011 / F-012 / F-013 — performance and operational hardening
8. F-010 — structured system/user model messages

## Resolved findings

None yet.
