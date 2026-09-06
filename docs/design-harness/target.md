# target — acceptance criteria for output

## Purpose

Plan a WhatsApp interface: the human opens the app, opens group A, and can translate
individual messages to Polish with the original below. Each translation is cached
locally and uses previous and related messages as context; messages can be
retranslated with a comment or edited and saved manually. Sending a message does
not auto-translate; the human may use a translation app for outgoing text.

## Current requirements
- User opens the app, user opens group A — each incoming message shows its original and a Translate button
- Clicking Translate translates only that message to Polish and shows it above the original
- Translations are cached locally
- Manual translations use previous conversation and related quoted messages, including preceding old history when available
- Old group history is requested on first pairing, persisted locally, and available when reopening the app
- Messages can be retranslated with a comment, or a translation can be manually edited and saved
- Sending a message does not auto-translate; the user can use a translation app
- The app supports all WhatsApp chat features: reply to messages, view images, see when a message is a reply to an earlier message, timestamps, usernames, photos
- Export sentences and a list of unfamiliar (translated) words for language learning
- Words marked as known go into a global list and stay untranslated in translated messages
- Names and handles are masked before translation and restored after (privacy)

## Fulfilment map
- User opens the app, user opens group A — messages show originals + Translate buttons → [system.md](output/system.md) · [UI](output/modules/ui.md)
- Clicking Translate translates one message above its original → [UI](output/modules/ui.md) · [Translator](output/modules/translator.md)
- Translations are cached locally → [Local Cache](output/modules/cache.md)
- Manual translations use previous/related old history → [Translator](output/modules/translator.md) · [WA Gateway](output/modules/wa-gateway.md)
- Old history is requested, persisted, and loaded on reopen → [WA Gateway](output/modules/wa-gateway.md) · [Local Cache](output/modules/cache.md)
- Retranslate with a comment, or edit and save → [Local Cache](output/modules/cache.md) · [Translator](output/modules/translator.md)
- Sending does not auto-translate → [WA Gateway](output/modules/wa-gateway.md) · [UI](output/modules/ui.md)
- All WhatsApp chat features → [UI](output/modules/ui.md) · [WA Gateway](output/modules/wa-gateway.md)
- Export sentences and word list → [Export](output/modules/export.md)
- Known words stay untranslated → [Translator](output/modules/translator.md) · [UI](output/modules/ui.md) · [Local Cache](output/modules/cache.md)
- Names/handles masked before translation → [Translator](output/modules/translator.md)
