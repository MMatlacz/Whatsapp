# Local Cache

Responsibility: durable local store of translations.

- Stores each translation locally, keyed by message: original + translation
- Manual edits are saved and persisted
- Opening a group shows cached translations instantly — no re-translation
- Retranslate-with-comment overwrites the message's translation even if it was manually edited — retranslation is per message
- Stores one global known-word list; every translation and retranslation honors it

Provenance: [translations-cached-locally](../../ideas/translations-cached-locally.md), [retranslate-edit-translations](../../ideas/retranslate-edit-translations.md), [retranslate-overwrites-edit](../../ideas/retranslate-overwrites-edit.md), [keep-known-words-untranslated](../../ideas/keep-known-words-untranslated.md), [translate-incoming-to-polish](../../ideas/translate-incoming-to-polish.md)
