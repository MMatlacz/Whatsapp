# Native macOS + iOS Plan — Apple Intelligence translation, native Swift WhatsApp

Target: a native SwiftUI replacement for the Electron WhatsApp Translator,
translating Indonesian → Polish with **Apple's on-device foundation models**
(GenerativeModels framework), using a **native Swift implementation of the
WhatsApp multi-device protocol** (no Node/Baileys on device), landing first as
a **macOS-only proof of concept**.

## Outcome

A macOS 26+ SwiftUI app that links a WhatsApp account, receives group
messages, and translates them with the on-device Apple Intelligence LLM —
prompt-controlled, so glossaries ("keep these words untranslated" → known
words), idiom handling, context, and privacy masking keep working like today.
A later phase adds compose, media, vocabulary hover, export, then iOS sharing
the same Swift core.

Free-only constraint preserved: on-device Apple Intelligence costs no API
money and keeps data on the device. The paid Apple Foundation Models server
API is explicitly out of scope.

## Decisions

- **Translation engine: Apple Intelligence on-device LLM** (`GenerativeModels`,
  iOS/macOS 26+, Apple-silicon). Prompt control matches current `buildPrompt`
  semantics (context window, known words, comment/retranslate, placeholders).
  Conservative fallback if availability or id→pl quality disappoints during
  Phase 0: Apple `Translation` framework (free, offline, but no glossary
  control) — decided by a Phase 0 quality gate, not by default.
- **WhatsApp layer: native Swift protocol client** reusing the multi-device
  design Baileys implements (QR/linking handshake, noise encryption,
  protobuf messages, websocket). One shared Swift package serves macOS and
  iOS; the Electron app stays as-is meanwhile.

  **Finding (checked 2026-09): no macOS/Swift WhatsApp library exists.**
  Surveyed candidates and their state:
  - `whatsmeow` (tulir/whatsmeow, Go, MPL-2.0, ~7.2k stars, active) — full
    multi-device client: QR/pairing, noise handshake, all protobuf types,
    media, appstate, 15 SQL schema migrations. The only complete, maintained
    implementation outside Node.
  - `sigalor/whatsapp-web-reveng` + `-multi-device-reveng` — protocol
    documentation and reference Python implementation (not a library).
  - `pywhats` (Python, pre-alpha), `amarula` (Elixir OTP, independent),
    `wuzapi` (REST wrapper over whatsmeow).
  - Swift candidates are dead: `jordansinger/WhatsAppKit` (repo removed),
    `oculta/whatsmeow-native` (gone); remaining "Swift WhatsApp" repos are
    Firebase demo clones, not protocol clients.

  Consequence: the Swift rewrite is greenfield with no prior art. The P0.1
  gate therefore tests **whatsmeow embedded as a local Go sidecar** first
  (static darwin binary spawned by the SwiftUI app, same JSON-RPC contract as
  the Baileys echo rig; later reusable on iOS via gomobile bindings). The
  Swift protocol rewrite stays as the fallback if Go bindings on the target
  OS prove unusable.
- **Milestone 1: macOS-only POC** — link account, group list, read incoming
  messages, translate them on-device. No compose, media, export yet.
- **Storage**: sessions in Keychain (secure), messages/translations in a local
  store (SwiftData or SQLite — decide in Phase 2 on volume), mirroring the
  current cache/history split (raw history append-only + translations cache
  with revision/context/learningMode-aware keys).
- **Privacy**: keep the `{{P1}}` masking discipline in prompt building even
  though the LLM is on-device (consistency, screenshots, logging). Masked
  prompt may be written to the local translation log; names recorded as hash.
- **No backend — confirmed product constraint (2026-09).** No server-owned
  WhatsApp sessions, no cloud translation, no edge workers, no accounts, no
  telemetry. The WhatsApp connection and the LLM both run on-device; the only
  helper process is the local Go sidecar (POC only). Contrast with
  WhatLingo's architecture (server-held sessions, Go backend, Cloudflare
  Workers) — intentionally the opposite; see
  `docs/competitive-landscape.md`.
- **Feature parity strategy**: reuse the existing prompt design, cache-key
  semantics, and test fixtures; do not re-derive product behavior.

## Architecture

```
┌─ SwiftUI app (macOS 26+) ───────────────────────────────┐
│  Views (sidebar: groups | chat: bubbles, actions)        │
│  TranslationService ── GenerativeModels (on-device LLM)  │
│    └ prompt builder (ported buildPrompt + masking)       │
│  Store (messages, translations cache, known words)       │
│  WhatsAppClient (shared Swift package)                   │
│    └ NOISE handshake + protobuf + websocket + session    │
└──────────────────────────────────────────────────────────┘
                │ JSON-RPC over local socket (POC; native later)
┌─ Node sidecar (POC ONLY, development scaffolding) ──────┐
│  Baileys echo server — used only until the Swift        │
│  protocol client links a real account; then deleted     │
└──────────────────────────────────────────────────────────┘
```

POC reality check: linking a real account needs the protocol stack complete,
so the first deliverable uses a local Baileys "echo rig" to exercise the UI +
translation pipeline end-to-end and a minimal Swift client that targets the
same message shapes. The Swift protocol client is the long pole and proceeds
in parallel (Phase 1b).

## Phases and tasks

- [ ] **P0.0** Spike: GenerativeModels entitlement/allowlist workflow on a dev
      Mac; confirm id→pl on-device quality with the 60 synthetic fixtures
      (port `test/translation-cases.ts` to Swift fixtures; `humanReviewed:
      false` outputs saved to `docs/native/`).
- [ ] **P0.1** Spike: protocol availability — embed whatsmeow as a Go sidecar,
      link a burner account, receive one message, stream it to SwiftUI.
      Sweep to the Swift handshake rewrite only if the sidecar path fails
      (evidence above shows no Swift prior art).
- [ ] **P0.2** Port prompt builder + privacy masking + cache-key semantics to
      Swift with unit tests reusing the existing fixture/tokenizer cases.
      Decide SwiftData vs SQLite for the store.
- [ ] **P1.0** macOS POC: sidebar groups + chat list, read-only incoming
      messages, on-device translate button per message, translation below
      original, context from the last 8 messages, errors with retry.
- [ ] **P1.1** Swift protocol client replaces the echo rig for real linking:
      QR from window, session in Keychain, reconnect on network change.
- [ ] **P2.0** Compose send-as-typed, reply, media thumbnails, pagination.
      Port the A-B-A staleness rules from `app.ts` (selection/history
      sequence guards).
- [ ] **P2.1** Translation quality tier: known words (glossary prompt),
      retranslate-with-comment, manual edit (edited flag), export sentence
      pairs + unfamiliar words (ported from `src/export.ts`).
- [ ] **P3.0** Vocabulary hovers: one background LLM request per inspected
      message; cached instant hovers; strict span validation before render
      (port `validateVocabulary` rules); stale-guard via per-view epoch.
- [ ] **P4.0** iOS: share the Swift package (protocol + translation + store);
      SwiftUI views adapt (navigation stack, touch hover = long-press),
      local-network/Handoff notes if iOS needs the Mac for anything.
- [ ] **P4.1** App Store hardening: privacy manifest, screenshot-safe masking,
      `NSLocalNetworkUsageDescription` if used, review of ToS risk (below).

## Verification checklist

- [ ] Unit: prompt builder emits context/known-words/placeholders per fixture
      (ported `self_check` cases, Swift XCTest).
- [ ] Unit: masking covers Unicode names/handles in every prompt field;
      restore round-trips.
- [ ] Unit: cache-key changes on body/translation/context/revision/learningMode
      (ported `free_translation` cases).
- [ ] Unit: vocabulary validation rejects wrong token coverage, bad spans,
      over-long meanings (ported cases).
- [ ] Mock-driven: POC UI translates 20 synthetic messages with a stubbed
      on-device model; errors surface with retry; no provider call leaves
      the device.
- [ ] P0.1 gate: Swift client links a burner WhatsApp account and receives a
      real message — record evidence in `docs/native/`.
- [ ] Live quality sample: 6–12 real on-device translations of the synthetic
      fixtures, stored with `humanReviewed: false`; no native-speaker score
      claimed.
- [ ] Regression: A→B→A chat switches drop in-flight translation results
      (ported smoke scenario as XCUITest once the UI is stable).
- [ ] Long-running: 1h socket churn (sleep/wake, network toggle) reconnects
      and re-syncs history without gaps.

## Risks and limitations

- **WhatsApp ToS / account risk**: third-party clients violate WhatsApp's
  terms; accounts can be banned and App Store review may reject. Mitigated
  only by personal-use framing, low profile, and no paid distribution
  promises. This is the same risk the Electron app already carries.
- **Protocol maintenance**: no Swift prior art exists; with whatsmeow the
  upstream project absorbs protocol churn and the app only tracks its
  releases. The Swift-rewrite fallback inherits the full maintenance burden; a
  packet-capture harness against whatsmeow/Baileys is the diagnostic tool.
- **On-device LLM quality**: id→pl is a low-resource pair; Apple's on-device
  model may lag OpenRouter MiniMax on idioms/slang. P0.0 gate exists; the
  Translation-framework fallback keeps "free + private" if LLM quality fails.
- **OS/device floor**: macOS/iOS 26+ and Apple silicon only; no Intel, no
  pre-26 OS. Entitlement allows-list is developer-approved and cannot be
  assumed instant.
- **No glossary in Translation framework**: irrelevant if LLM tier wins; do
  not silently fall back to it and keep known-words promises.
- Not covered by this plan: watchOS/tvOS, widget translate, server/cloud
  relay of the account, or the paid Apple server API.