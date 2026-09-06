# whatsapp-web.js — personal-account client with group send/receive

A WhatsApp client library for NodeJS that connects through the WhatsApp Web browser app for user or business accounts. Supported features include send/receive messages, receive media, message replies, join groups by invite, get group invite, modify group info/settings, add/kick/promote group participants, and mention users/groups — covering the read-any-group and send-to-group needs.

Provenance: [wwebjs/whatsapp-web.js on GitHub](https://github.com/pedroslopez/whatsapp-web.js/) (accessed 2026-09-05); usage docs at [wwebjs.dev](https://wwebjs.dev/). Grade: strong alternative to Baileys when a headless-browser client is acceptable; heavier runtime than pure WebSockets.

Update 2026-09-05: superseded in this project after WhatsApp Web build 2.3000.1043270046 broke the library upstream ([issue #201845](https://github.com/wwebjs/whatsapp-web.js/issues/201845), [#201838](https://github.com/wwebjs/whatsapp-web.js/issues/201838), no fix released); gateway switched to [Baileys](baileys.md).
