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
isolation and all assertions. Re-run remote checks before declaring CI fixed.

Simulator target: Translation diagnostic iPhone 15 Pro Max. Preserve auth and user data.
Required external review, real-message authorization and physical-device access are
not inferred from successful local builds or sample tests.
