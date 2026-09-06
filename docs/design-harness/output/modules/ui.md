# UI

Responsibility: the desktop chat surface.

- Desktop app; Electron main process shared with the gateway
- Chat view: original below an optional translation; timestamps, sender names and photos, images, quote-reply rendering
- Group picker — any group
- Each incoming text message has a Translate button; it translates only that message with context
- While translation or retranslation is pending, the message actions show an inline spinner and “Translating…” status
- Translated messages retain retranslate-with-comment and edit + save controls
- Word selection on the original message: marked words join the global known-word list and stay untranslated in translations
- Compose box sends as typed; no outgoing translation

Provenance: [desktop-app-form](../../ideas/desktop-app-form.md), [translate-incoming-to-polish](../../ideas/translate-incoming-to-polish.md), [full-chat-features](../../ideas/full-chat-features.md), [pick-any-group](../../ideas/pick-any-group.md), [retranslate-edit-translations](../../ideas/retranslate-edit-translations.md), [keep-known-words-untranslated](../../ideas/keep-known-words-untranslated.md), [no-auto-outgoing-translation](../../ideas/no-auto-outgoing-translation.md)
