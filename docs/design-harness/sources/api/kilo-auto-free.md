---
tags: [translation]
---

# Kilo auto free — working contextual translation route

The installed Kilo CLI (7.5.14) exposes `kilo/kilo-auto/free`. A live synthetic
contextual translation test completed at zero cost and was routed to
`stepfun/step-3.7-flash`; with a preceding question, it returned a natural
`Już, kolego...` translation. The no-context smoke test was weaker, so the
integration sends the rolling conversation context rather than only the target
sentence. The contextual run took about 27 seconds.

The local Kilo credential listing showed no stored Kilo credential, while the
user's shell secrets file contains a Kilo token. The application now uses Kilo's
loopback headless server (`kilo serve --pure`) and its documented session/message
HTTP routes, keeping the credential in the server process. Evidence was
collected 2026-09-05 using synthetic text only.
