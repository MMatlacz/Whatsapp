# Native Web Transport Findings

Research date: 2026-09-06

Companion to `docs/native-app-plan.md`. This document records findings about using WhatsApp Web as the transport for a native macOS/iOS app instead of implementing the WhatsApp multi-device protocol directly.

## Executive conclusion

The most promising transport spike for the native app is **Apple WebKit/WebPage on macOS 26+**, using WhatsApp Web itself as the protocol implementation and injecting a small JavaScript bridge similar to `whatsapp-web.js`.

Recommended order:

1. **Apple WebPage / WebKit on macOS** — highest priority spike.
2. **Apple WebPage / WebKit on iOS while foregrounded** — technically promising, but verify service-worker/session behavior.
3. **whatsmeow local Go transport** — fallback if WebKit cannot reliably expose WhatsApp internals or session state.
4. **Ground-up Swift WhatsApp protocol client** — last resort only.
5. **Obscura** — not recommended as the primary transport.

The biggest iOS issue is independent of the chosen WhatsApp implementation: ordinary iOS apps are suspended after entering the background, so neither a hidden WebKit page nor a custom WebSocket client can remain continuously connected indefinitely. A no-backend iOS app should therefore be designed as foreground-connected unless a Mac companion or other permitted relay is introduced.

## A-001 — High-value candidate — Apple `WebPage` is effectively a native headless WebKit page

Apple added WebKit-for-SwiftUI APIs in iOS/macOS 26. `WebPage` can load and control interactive web content **without presenting a `WebView`**. It supports JavaScript calls, a custom user agent, persistent `WKWebsiteDataStore`, navigation handling, and a `WKUserContentController`.

This provides most of the browser-management primitives needed by a `whatsapp-web.js` style architecture while staying entirely inside the system WebKit engine.

Potential flow:

```text
SwiftUI app
   |
   +-- WebPage (not normally visible)
   |     +-- https://web.whatsapp.com
   |     +-- persistent WKWebsiteDataStore
   |     +-- desktop Safari user agent
   |     +-- injected WhatsApp bridge JS
   |     +-- WhatsApp Web owns encryption/session/network protocol
   |
   +-- WKScriptMessageHandler
   |     +-- message events -> Swift
   |     +-- group/chat metadata -> Swift
   |
   +-- FoundationModels translation
   +-- native SwiftUI chat UI
```

For initial pairing, temporarily attach the same `WebPage` to a visible `WebView` and let the user scan/link. After authentication, keep the `WebPage` alive without rendering it in the normal app UI.

**Recommended spike:** make `web.whatsapp.com` reach its normal linked-device screen, pair a burner account, hide the `WebView`, and verify the page remains functional through `WebPage.callJavaScript`.

## A-002 — High-value candidate — Port the browser bridge, not the WhatsApp protocol

`whatsapp-web.js` does not implement WhatsApp encryption/networking itself. It loads the real WhatsApp Web application, injects JavaScript that exposes WhatsApp's internal Store/modules, and bridges browser events back to Node through Puppeteer.

The same conceptual bridge can be implemented using WebKit:

| whatsapp-web.js / Puppeteer | Apple WebKit equivalent |
| --- | --- |
| `page.evaluate()` | `WebPage.callJavaScript()` / `WKWebView.evaluateJavaScript()` |
| `page.exposeFunction()` | `WKScriptMessageHandler` / `WKScriptMessageHandlerWithReply` |
| init/injected script | `WKUserScript` via `WKUserContentController` |
| browser profile | persistent `WKWebsiteDataStore` |
| page navigation listener | WebPage/WKNavigationDelegate navigation events |
| browser UI | native SwiftUI; optional WebView for pairing/debugging |

A useful reference is `wwebjs-electron`, which already demonstrates that whatsapp-web.js does not fundamentally require a separately spawned browser: it can attach to an application's existing Chromium view and use the same injected Store-based API.

**Recommendation:** reuse/port the small injected JavaScript concepts and data shapes rather than trying to port Puppeteer or Node wholesale. Keep the Swift-facing bridge intentionally small: new message, history page, group list, send, reply, media metadata, connection state.

## A-003 — macOS assessment — Strong candidate

WhatsApp officially supports current Safari for WhatsApp Web, so the WebKit engine itself is a supported browser target. Native macOS WhatsApp-Web wrappers using WebKit have also existed historically.

macOS does not have the iOS application-suspension limitation, so a hidden `WebPage` can remain alive as long as the app is running. This makes the architecture particularly attractive for the planned macOS-first POC.

Advantages over the Go/whatsmeow path:

- WhatsApp itself implements protocol crypto and protocol changes.
- No Baileys/whatsmeow protocol schema maintenance.
- No Go runtime/sidecar or gomobile integration.
- Same engine family as officially-supported Safari.
- Native Swift JS bridge supplied by WebKit.
- Session/browser storage managed by WebKit.

Main risk: WhatsApp regularly changes/minifies its internal JS modules, so Store/module injection remains brittle. This is the same maintenance class as whatsapp-web.js, but usually less work than maintaining the entire network protocol.

**Current recommendation:** move a WebPage transport spike ahead of P0.1 whatsmeow in the native roadmap.

## A-004 — iOS assessment — Foreground promising, background is the product blocker

`WebPage`, `WebView`, `WKUserContentController`, persistent website data and JS bridging are available on iOS 26 as well. Therefore the same transport design is technically worth testing in the foreground.

However, iOS normally suspends an app shortly after it enters the background. Long-lived ordinary network connections are not a general-purpose background execution mode. Consequently:

- a hidden WebPage cannot be assumed to keep WhatsApp Web connected while the app is suspended;
- a custom Swift WhatsApp WebSocket implementation has the same lifecycle problem;
- embedding Obscura would not solve it;
- the app cannot promise WhatLingo-style continuous incoming message translation while closed using only local iPhone execution.

Product choices for iOS therefore need to be explicit:

1. **Foreground-connected mode** — translation works while the app is open; reconnect/sync on launch.
2. **Mac companion relay** — the user's Mac remains the linked WhatsApp device and sends translated updates to the iPhone over a permitted local/cloud relay. This preserves the no company-owned backend principle but depends on the Mac being available.
3. **Backend/session relay** — WhatLingo-like always-on behavior, but conflicts with the current no-backend product constraint.

Do not spend effort on a Swift protocol rewrite expecting it to fix iOS background delivery; it does not address the OS lifecycle limitation.

## A-005 — iOS WebKit caveat — Service Worker support must be explicitly proven

WhatsApp Web uses Service Worker/browser persistence mechanisms and IndexedDB heavily. Current WebKit documentation/issues still show special restrictions around Service Workers in ordinary iOS `WKWebView` contexts; browser-entitled apps have broader Service Worker access, and App-Bound Domains have historically exposed additional support.

`WebPage` uses the same WebKit data-store/content infrastructure, so do not assume WhatsApp Web will fully authenticate solely because the initial HTML renders.

The iOS POC must verify:

```javascript
navigator.serviceWorker
indexedDB
crypto.subtle
WebSocket
```

and then perform a real link + restart/session restore test.

If WebKit renders the login page but stalls at "Signing in", Service Worker/storage behavior is the first thing to inspect.

## A-006 — Obscura assessment — Not recommended

Obscura is an impressive lightweight Rust/V8 browser engine with CDP compatibility and macOS binaries, and Puppeteer/Playwright can connect to it. That makes it superficially attractive as a small replacement for Chromium.

For this project it currently has two major disadvantages:

1. Its own compatibility documentation says **Service Workers are not implemented / remain incomplete**. WhatsApp Web uses a Service Worker and browser database state, making this a high-risk compatibility gap.
2. There is no normal iOS distribution/runtime path. Embedding a non-WebKit browser engine on iOS requires Apple's alternative/embedded browser-engine entitlements in supported regions and substantial conformance/security requirements. A hidden browser used as an automation engine is also a poor fit for the intended in-app-browsing entitlement model.

On macOS, Obscura could still be an experimental fallback if Service Worker support lands and a real WhatsApp Web smoke test passes, but there is little reason to prefer it over system WebKit for an Apple-native app.

**Status:** Do not put Obscura on the critical path.

## A-007 — Chromium sidecar remains a useful diagnostic fallback

If WebKit fails because WhatsApp relies on Chromium-specific behavior, a native SwiftUI app can still run a hidden Chromium process and drive it over CDP. This preserves a native UI while using the same browser environment as whatsapp-web.js.

This is heavier than WebKit and complicates packaging/notarization/App Store distribution, but it is much less risky technically than implementing the WhatsApp protocol from scratch.

Suggested fallback ladder:

```text
Apple WebPage/WebKit
       ↓ compatibility failure
Chromium/CDP browser sidecar
       ↓ packaging/product failure
whatsmeow local Go client
       ↓ unacceptable integration constraints
native Swift protocol implementation
```

## POC acceptance tests

### macOS WebPage transport spike

- [ ] Load `https://web.whatsapp.com` with current desktop Safari UA.
- [ ] Confirm WhatsApp Web reaches QR / link-with-phone-number state.
- [ ] Pair a burner account.
- [ ] Use a persistent `WKWebsiteDataStore`; restart app and verify session restoration.
- [ ] Run JS from Swift after pairing and enumerate basic WhatsApp internal modules/state.
- [ ] Inject a JS -> Swift message handler and receive one incoming text event.
- [ ] Send one text message through an injected browser-side function.
- [ ] Detach/hide the WebView and verify `WebPage` keeps receiving messages on macOS.
- [ ] Sleep/wake the Mac and verify recovery/reinjection.
- [ ] Record the exact WhatsApp Web build and required injected module names.

### iOS WebPage transport spike

- [ ] Repeat QR/pairing test on physical iPhone with desktop UA.
- [ ] Verify `navigator.serviceWorker`, IndexedDB, WebCrypto and WebSocket availability.
- [ ] Restart and verify session persistence.
- [ ] Lock/background for 30s, 2m and 10m; document when message events stop.
- [ ] Resume and verify WhatsApp Web reconnects and catches up without requiring relink.

## Roadmap impact

Proposed change to `docs/native-app-plan.md`:

- Replace P0.1's first experiment from "embed whatsmeow sidecar" to **"prove Apple WebPage + WhatsApp Web + JS bridge"**.
- Keep whatsmeow as the second transport gate.
- Treat the native Swift protocol rewrite as last resort, not the expected Phase 1 endpoint.
- Add an explicit iOS background-connectivity product gate before promising full feature parity with WhatLingo.

## References checked

- Apple WebKit for SwiftUI / `WebPage` documentation (iOS/macOS 26).
- Apple `WKUserContentController` and script-message APIs.
- Apple `WKWebsiteDataStore` persistence APIs.
- Apple background execution guidance for iOS.
- Apple alternative browser engine entitlement requirements.
- WhatsApp Help Center supported browser / linked-device documentation.
- `wwebjs/whatsapp-web.js` architecture and current issues around IndexedDB/service-worker state.
- `wwebjs-electron` existing-browser integration approach.
- `h4ckf0r0day/obscura` Puppeteer/Playwright compatibility documentation.
