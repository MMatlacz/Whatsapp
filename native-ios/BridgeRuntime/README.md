# Hidden WebKit runtime

Development preparation: `npm ci --ignore-scripts`, `npm test`, `npm run bundle`.
The generated script and upstream license/notice files are local build outputs.
No package install hooks are run. The lockfile pins WA-JS 4.6.0 and its registry
integrity; the bundle step checks the version and Apache-2.0 license declaration.

The application-owned adapter uses the published WA-JS API. It does not export
raw runtime stores, authentication state, keys or media URLs to Swift. It does not
mark chats read or create new contacts as a side effect of sending. An uncertain
send must never be automatically retried by the native client.

Current status: adapter contract tests and local bundle generation pass. Xcode
resource integration, hidden runtime readiness, native state wiring, live account
verification, quote/media metadata and delivery-event mapping remain unfinished.
Do not claim live support from the fixture tests.

References consulted:

- https://wppconnect.io/wa-js/functions/chat.list.html
- https://wppconnect.io/wa-js/functions/chat.getMessages.html
- https://wppconnect.io/wa-js/functions/chat.sendTextMessage.html
- https://wppconnect.io/wa-js/functions/chat.getMessageById.html
- The exact installed package declarations under dist/conn, dist/chat and dist/whatsapp.

Context Hub had no matching WA-JS documentation; the published primary API and
version-pinned declarations were used instead. Before distributing an app bundle,
include the upstream LICENSE and bundled third-party notices and finish the
transitive license inventory. Never copy package test storageState/auth fixtures
into the app or repository.
