# App readiness execution goal

Owner requested execution of all six readiness points on 2026-09-13.
This checklist is evidence-driven; simulator, CI and physical-device gates are distinct.

## Owner-approved scope amendments

- Translation remains quality-gated. The latest owner instruction supersedes any
  prior experimental opt-in wording: do not enable unvalidated on-device translation
  or actual translation/retranslation. Keep any diagnostic output beside its
  original, label it unvalidated, and never send it automatically. Validated/default
  routing stays disabled until semantic quality and resource gates pass.
- Include contact/group photos and display names in the native chat list and
  conversation header, plus sender names in groups. Use fallback avatars for
  unavailable photos; do not persist temporary photo URLs or authentication data.
- Prioritize the physical phone's reported runtime-startup failure. Its screenshot
  showed runtime not ready with network online; uninitialized registration flags
  do not prove session loss. Preserve the existing linking profile during recovery.

## Work queue

- [ ] 1. Hidden live WhatsApp transport feeding native chat list, paginated history,
  incoming events, text sends/replies and reconnect. Preserve the linked profile.
- [ ] 2. Durable chat cache/drafts; SQLite integration of translation revisions,
  correction comments and language-scoped known words.
- [ ] 3. Translation quality improvement and reproducible corpus evaluation.
  TranslateGemma baseline: 10 major errors in 36 cases. Validated/default routing stays
  disabled until semantic quality and resource gates pass. Do not enable unvalidated
  translation or retranslation; align words without guessing.
- [ ] 4. Real end-to-end send/receive, offline recovery, restored sessions,
  uncertain-send handling and duplicate prevention. Real test messages require a
  specified recipient and text; no unrelated conversations should be modified.
- [ ] 5. Sustained physical-device testing, total app plus WebKit memory and stability
  evidence. Keep #122 open until acceptance criteria actually pass.
- [ ] 6. Passing Linux/Apple/secret checks, required GitHub review, clean issue scope,
  and protected squash merges into apple. No bypasses or workflow weakening.

## Current evidence and immediate action

Native interface and translation-review controls are in draft PRs #130 and #132.
The live adapter is implemented on the local readiness branch; validated model
routing is not complete. Simulator and physical-device evidence remain distinct.

CI run 34721765457 failed because Linux Swift 6 XCTest discovery invokes synchronous
MainActor test methods from a nonisolated context. Convert the four affected test
entrypoints to async so generated discovery uses async test wrappers; keep actor
isolation and all assertions. Run 34721982612 now confirms Linux test-core and
lint pass on PR #132 head 452f12d; Apple build also passed in 19m23s.
Secret checks passed in run 34721982632.

Qwen functional run 34721982615 failed in the macOS fallback benchmark: fixture
qwen-slang-mager-no-context reached 96 generated tokens, was classified truncated,
and finished cancelled. The command correctly exited 1 for invalid output. The
functional limit is now 512 tokens, matching the bounded diagnostic limit while
retaining the published non-thinking sampling settings and rejection of cancelled
or cap-truncated output. All 39 diagnostic package tests pass locally. A fresh CI
run is still required; this is separate from the TranslateGemma semantic rejection.

Live release-gate audit on 2026-09-13: draft PR #130 remains blocked because its
`test-core` job invokes two main-actor-isolated chat tests synchronously; its Apple
build was skipped. Draft PR #132 contains the async discovery fix and has passing
Linux core tests, lint, Apple build, Secret checks, gitleaks and forbidden-file
checks, but its Qwen functional job failed on the invalid/truncated/cancelled
fallback result above. Neither draft has an approving review. The protected `apple`
ruleset requires one approval and strict `Secret checks`; these review and quality
gates remain open. #122 remains open for combined app/WebKit memory, sustained
lifecycle and thermal acceptance.

Local live-transport branch now bundles the pinned runtime and connects it to the
native model. The initial detached runtime reported authentication required.
Checking registration separately showed a registered but not authenticated session.
Attaching invisible WebKit to the native view lifecycle then reached ready, with
registered/authenticated/main-ready/online flags all true. On 2026-09-13 the iPhone
15 Pro Max simulator displayed real account chats in the native list. No session
deletion or relinking was necessary. No arbitrary or unrelated test messages have
been sent.
The native QR sheet opens, and the app also supports WhatsApp's public phone-number
linking flow with memory-only phone number and pairing code state. Physical linking
and restoration through that flow remain unverified.

An authorized self-test was sent through the native composer on 2026-09-13. A
user-supplied phone screenshot and an independent desktop observation showed exactly
one copy arriving in the official WhatsApp app with blue double checks. A follow-up
transport fix stopped treating the absence of quoted-message metadata as a send
failure; native confirmation and history then marked the self-message Read.

Follow-up authorized self-tests showed incoming updates without reopening, restart
restoration, and three unique messages without observed duplication. Durable pending
send state now locks an uncertain send until history reconciliation or explicit retry,
and stores the known message IDs used for duplicate prevention. Runtime testing in the
real group conversation verified that a selected reply target and unsent draft both
survived app termination and relaunch; they were then cleared without sending to the
group. Controlled network-loss recovery and physical-device E2E remain open.

SQLite core schema v3 stores chats/messages, drafts, reply targets and pending-send
recovery records. Translation revisions, correction comments and language-scoped
known words share the SQLite store. The full shared-core suite passes 120 tests,
including database reopening, model recreation, cached offline history and durable
uncertain-send state. The integrated simulator build passes.
On 2026-09-13 an unsent temporary draft in the self-conversation survived stopping
and relaunching the iPhone 15 Pro Max app and reopening that conversation. The exact
text was observed, then cleared without sending. Quote draft restoration and
translation-to-SQLite integration are still outstanding. Offline simulator cache
verification remains separate from this connected restart test.

The iPhone 15 Pro Max simulator shows real chats with contact/group photos and names.
The Keluarga O. Panjaitan conversation shows each group sender's name and a separate
sender-avatar column without covering the message bubble. These observations do not
establish sustained physical-device stability or approval to merge.

Physical-device preparation: on 2026-09-13 the iPhone 15 Pro Max was available. The
latest native app built and signed without package-plugin or macro-validation bypasses,
updated the existing installation in place, and launched through devicectl. No data
container was erased. Phone-number linking then completed through the official WhatsApp
flow. The native chat list, real history, an authorized self-send reaching Read and
linked-session restoration after relaunch were observed on the phone.

Sanitized physical linking-screen baseline on 2026-09-13: a 121.081-second Instruments
Activity Monitor capture collected 55 simultaneous samples across the app, WebContent,
GPU and Networking processes. Peak combined physical footprint was 308,547,624 bytes
(about 294.254 MiB); thermal state stayed Fair and was-induced was false. Attribution
was checked across launch and termination: the four candidate processes exited after
terminating only the app, while unrelated WebKit remained. The phone was still on the
linking screen and unauthenticated, with no model or sustained authenticated workload;
this is a baseline only and does not satisfy #122.

An authenticated 121.404-second all-process Activity Monitor trace then exercised the
native chat list, self history and Keluarga O. Panjaitan group history while the hidden
WebKit transport remained active. The matched app, WebContent, GPU and Networking group
peaked at 975,918,344 bytes (about 930.708 MiB) combined physical footprint; the peak
combined real-memory signal was 1,413,840,896 bytes. Thermal state remained Nominal.
Process attribution was checked by terminating only the app: the three matched WebKit
processes exited with it while older unrelated WebKit processes remained. The linked
session and native chats restored on relaunch. The sanitized measurement is in
`authenticated-webkit-memory-baseline.json`.

This is a bounded authenticated baseline with translation intent enabled but no
validated translation provider loaded. It is not the selected-model concurrency,
memory-pressure, background/foreground or sustained-duration evidence required by
#122, and it does not establish a production phone memory budget. Keep #122 open.

TranslateGemma glossary guidance reduced the provisional review from 10 to 5 major
errors across the same 36 cases, with 18 minor and 13 acceptable outputs. The run used
the exact model revision and greedy settings, but its source tree was dirty and the
review is not independent. Wrong group, pickup, payment/treat and permission meanings
remain major failures, so actual translation and retranslation stay disabled.

Both active native workflows now install the exact owner-reviewed SwiftPM plugin and
macro fingerprints and contain no package-plugin or macro-validation skip flags. Local
YAML parsing, actionlint (with the repository's custom xcode-27 runner label declared),
generated-runtime verification, bridge tests, core tests, simulator build/run and
physical signed build pass. GitHub checks must rerun on the published commit. The apple
ruleset still requires one independent approval and strict Secret checks; no eligible
reviewer is currently configured, and no bypass may be used.

Simulator target: Translation diagnostic iPhone 15 Pro Max. Preserve auth and user data.
Required external review, real-message authorization and physical-device access are
not inferred from successful local builds or sample tests.
