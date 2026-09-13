# Native translation controls

Implemented on top of the native chat UI, with SwiftUI Expert guidance for
observable state, item-driven sheets and separately accessible actions.

## User flow

- Original and Polish translation appear together in each textual message card.
- Fix translation opens a local correction editor. Mapped phrases remain editable
  separately so learning-mode substitutions stay attached to the intended phrase.
  Untranslated messages allow a plain manual translation without invented mappings.
- Known words lists the available aligned source words/phrases. Selection is scoped
  by source language and can be reversed. Keep known words in original switches
  between a full translation and mapped source-language substitutions.
- Retranslate with comment saves guidance locally. An injected retranslator receives
  the original, previous translation, language pair, revision and comment. No model
  is injected in the app until translation quality gates are satisfied; the UI says
  explicitly that no model ran. Existing manual corrections are not silently lost.

## Data and safety

The original transport message is immutable. Edits, comments and known-word choices
are stored atomically in Application Support/NativeTranslationEdits/edits-v1.json
with complete iOS file protection. This is a versioned presentation-state store;
integration with the existing SQLite translation-revision/vocabulary tables remains
follow-up work with live chat storage. A read/write error is visible and prevents
overwriting unreadable saved data. These files must never be committed.

Keys include chat, message and language pair; source changes invalidate displayed
records. Revision checks reject stale editors and late model results. No WhatsApp
message is modified or sent by these actions. Known-word substitution uses aligned
parts, not substring replacement; unmapped text remains fully translated.

## Verification — 2026-09-13

iPhone 15 Pro Max simulator, iOS 26.5:

- Build and native navigation succeeded; actions expose separate accessibility nodes.
- Original `Aku minum kopi.` and fixed sample `Piję kawę.` displayed together.
- Selected `kopi`, enabled known-word display, observed `Piję kopi.`.
- Edited the mapped verb and saved; observed `Wypijam kopi.` with manual-edit label,
  while original remained unchanged.
- Entered a retranslation comment; observed saved-comment/quality-gate notice.
- Shared suite: 104 tests passed before the additional delayed-result race test.
- Final focused translation suite: 5 tests passed, including late-result protection.
- Rebuilt/relaunched and observed the saved manual correction; enabling the display
  toggle reused the saved known-word selection without selecting it again.
- SwiftLint and diff whitespace checks passed.

Samples are explicitly marked and are not translation-quality or live-chat evidence.
Automatic retranslation, arbitrary-message alignment and live WhatsApp remain gated.
