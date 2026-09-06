# WA Gateway

Responsibility: the personal WhatsApp connection.

- Connects to WhatsApp via Baileys with QR pairing on the human's personal account; session persisted locally
- Lists the human's groups; any group can be picked at runtime
- Requests full desktop history on pairing and persists group messages locally for later opens/context
- Receives group messages: text, images, quote-reply links, timestamps, sender names and photos; primes names from group participant metadata for translation privacy masking
- Sends messages exactly as typed — no translation
- Sends replies to messages

Provenance: [commit-baileys](../../ideas/commit-baileys.md), [whatsapp-personal-account-qr](../../ideas/whatsapp-personal-account-qr.md), [pick-any-group](../../ideas/pick-any-group.md), [full-chat-features](../../ideas/full-chat-features.md), [no-auto-outgoing-translation](../../ideas/no-auto-outgoing-translation.md) · evidence: [Baileys](../../sources/github/baileys.md)
