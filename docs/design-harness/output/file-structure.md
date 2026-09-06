# file-structure — the design on disk

## Tree

```
whatsapp-translator/
├── package.json          deps: electron, baileys, qrcode
├── main.js               Electron main process; window + app lifecycle
├── preload.js            IPC bridge — renderer has no direct Node access
├── renderer/
│   ├── index.html        chat view shell
│   ├── app.js            group picker, message list, manual Translate, compose, edit/retranslate controls
│   └── styles.css        chat layout: optional translation, original below
├── src/
│   ├── gateway.js        Baileys gateway, QR, groups, history, media, replies
│   ├── history.js        persistent JSONL message history
│   ├── translator.js     manual contextual Translator module
│   ├── cache.js          Local translation cache module
│   └── export.js         Export module
└── data/                 WhatsApp session, history + translation cache (gitignored)
```

## module → file map

- [WA Gateway](modules/wa-gateway.md) → src/gateway.js (+ preload.js IPC hooks)
- [Translator](modules/translator.md) → src/translator.js (+ src/auth-store.js)
- [Local Cache](modules/cache.md) → src/cache.js + src/history.js (+ data/)
- [UI](modules/ui.md) → renderer/ (+ main.js, preload.js)
- [Export](modules/export.md) → src/export.js (+ data/)

Electron because Baileys is a Node library — one runtime, no sidecar; Tauri would add a Rust shell. Swap later without touching the module design.
