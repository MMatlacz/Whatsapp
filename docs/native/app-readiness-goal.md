# App readiness execution goal

Owner requested execution of all six readiness points on 2026-09-13.
This checklist is evidence-driven; simulator, CI and physical-device gates are distinct.

## Work queue

- [ ] 1. Hidden live WhatsApp transport feeding native chat list, paginated history,
  incoming events, text sends/replies and reconnect. Preserve the linked profile.
- [ ] 2. Durable chat cache/drafts; SQLite integration of translation revisions,
  correction comments and language-scoped known words.
- [ ] 3. Translation quality improvement and reproducible corpus evaluation.
  TranslateGemma baseline: 10 major errors in 36 cases. Production translation stays
  disabled until semantic quality and resource gates pass; align words without guessing.
- [ ] 4. Real end-to-end send/receive, offline recovery, restored sessions,
  uncertain-send handling and duplicate prevention. Real test messages require a
  specified recipient and text; no unrelated conversations should be modified.
- [ ] 5. Sustained physical-device testing, total app plus WebKit memory and stability
  evidence. Keep #122 open until acceptance criteria actually pass.
- [ ] 6. Passing Linux/Apple/secret checks, required GitHub review, clean issue scope,
  and protected squash merges into apple. No bypasses or workflow weakening.

## Current evidence and immediate action

Native interface and translation-review controls are in draft PRs #130 and #132.
Live adapter and validated model routing are not complete. Local sample UI evidence
is recorded separately in native-swiftui-chat-plan.md and native-translation-controls.md.

CI run 34721765457 failed because Linux Swift 6 XCTest discovery invokes synchronous
MainActor test methods from a nonisolated context. Convert the four affected test
entrypoints to async so generated discovery uses async test wrappers; keep actor
isolation and all assertions. Run 34721982612 now confirms Linux test-core and
lint pass on PR #132 head 452f12d; Apple build also passed in 19m23s.
Secret checks passed in run 34721982632.

Qwen functional run 34721982615 failed in the macOS fallback benchmark: fixture
qwen-slang-mager-no-context reached 96 generated tokens, was classified truncated,
and finished cancelled. The command correctly exited 1 for invalid output. Do not
relax that gate or rerun merely to obtain a lucky passing sample. This is separate
from the existing TranslateGemma semantic-quality rejection.

Local live-transport branch now bundles the pinned runtime and connects it to the
native model. The initial detached runtime reported authentication required.
Checking registration separately showed a registered but not authenticated session.
Attaching invisible WebKit to the native view lifecycle then reached ready, with
registered/authenticated/main-ready/online flags all true. On 2026-09-13 the iPhone
15 Pro Max simulator displayed real account chats in the native list. No session
deletion or relinking was necessary. No real test messages have been sent.
The native QR sheet opens, but scanning a fresh code remains unverified.

SQLite core schema v2 adds drafts; the native composer loads and saves them with
visible storage errors. Fourteen persistence tests and six native chat tests pass,
including database reopening and model recreation. The integrated simulator build
passes. Chat and loaded-message caching are now integrated; an offline model test
verifies cached history remains readable while sending is disabled.
On 2026-09-13 an unsent temporary draft in the self-conversation survived stopping
and relaunching the iPhone 15 Pro Max app and reopening that conversation. The exact
text was observed, then cleared without sending. Quote draft restoration and
translation-to-SQLite integration are still outstanding. Offline simulator cache
verification remains separate from this connected restart test.

The full shared-core suite now passes 109 tests, and four adapter tests pass.
These do not establish live send/receive, sustained stability, physical-device
memory acceptance, translation quality or approval to merge.

Simulator target: Translation diagnostic iPhone 15 Pro Max. Preserve auth and user data.
Required external review, real-message authorization and physical-device access are
not inferred from successful local builds or sample tests.
