# Native SwiftUI chat interface

## Decision

Replace the visible embedded WhatsApp page with native SwiftUI. Hidden WebKit
transport is permitted by the owner; a web page must not become the chat UI.
Preserve the existing persistent authentication profile. Translation remains off.

## Implementation sequence

1. Native searchable chat list, unread/group filters, accessible rows and adaptive navigation.
2. Native message history, incoming/outgoing bubbles, quote selection and multiline composer.
3. Inject the existing WhatsAppTransport protocol; preserve drafts on unconfirmed sends,
   prevent concurrent sends per chat and deduplicate messages by stable identifiers.
4. Implement and validate the missing live runtime adapter behind hidden WebKit:
   chat enumeration, paginated history, events, reconnect and text/reply acceptance.
5. Validate a user-authorized real send, offline recovery and sustained total-process memory.

Steps 1–3 have an initial implementation. Step 4 is not complete. The default
interface does not claim to be connected or populate invented real conversations.
Local sample chats require an explicit action, stay in memory, and never use the network.
No delivery/read receipts are inferred from send acceptance.

## Simulator evidence — 2026-09-12

- Built and launched successfully on Translation diagnostic iPhone 15 Pro Max, iOS 26.5.
- Native accessibility elements expose the chat list, conversation, composer and Send button.
- Opened local sample conversation, typed and sent a sample message; verified native bubble,
  cleared composer and disabled empty Send button.
- No real message was sent. Existing authentication profile was not erased.
- Native search narrowed the list to the matching sample conversation.
- Shared Swift tests: 99 passed, then the fifth new native failure-path test passed
  in the focused suite. SwiftLint reported zero violations for the initial native files.

## Remaining acceptance work

- Live adapter and native connection/pairing state, event subscription and paginated history.
- Durable local drafts/cache using the existing persistence layer.
- Live send failure/reconnect, duplicate prevention across uncertain network outcomes.
- Physical-device memory and sustained stability remain separate from simulator UI evidence.
- Translation quality gates remain unchanged; no production translation enabled.
