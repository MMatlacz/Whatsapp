# ideas — human-created, two states (live / archived)

---
*unclassified*
- [Incoming group messages are shown translated to Polish, original below](translate-incoming-to-polish.md) — open group → already translated, original below
- [Translations are cached locally](translations-cached-locally.md) — local cache
- [Translations are contextual](translations-contextual.md) — context-aware
- [Old history is persisted and used as translation context](old-history-context.md) — full sync + local history
- [Messages can be retranslated with a comment, or edited and saved](retranslate-edit-translations.md) — retranslate/comment + manual edit
- [Outgoing messages are sent as typed — no automatic translation](no-auto-outgoing-translation.md) — no auto-translate; external translation app, paste back
- [The app supports all WhatsApp chat features](full-chat-features.md) — replies, images, quote-replies, timestamps, names, photos
- [WhatsApp connects via the human's personal account (QR bridge)](whatsapp-personal-account-qr.md) — personal account, not Cloud API
- [Any group can be picked at runtime](pick-any-group.md) — pick-any-group, confirmed
- [The WhatsApp connection commits to Baileys](commit-baileys.md) — bridge choice (switched after upstream wwebjs break)
- [The app is a desktop app](desktop-app-form.md) — desktop form
- [Translation falls back to keyless engines if the free-model provider fails](free-engine-fallback.md) — keyless fallback
- [Retranslate-with-comment overwrites the edited translation, per message](retranslate-overwrites-edit.md) — per-message overwrite
- [Export sentences and a list of unfamiliar words for language learning](export-language-learning.md) — unfamiliar-word export
- [Words marked as known go into a global list and stay untranslated in translations](keep-known-words-untranslated.md) — global known-word list
- [Translation uses a ban-safe free-model provider, not bannable account tricks](ban-safe-free-model-translation.md) — free-model chain with fallback
- [Names and handles are masked before translation and restored after](privacy-name-masking.md) — privacy masking
