# WebKit-backed Chats app: simulator handoff

Date: 2026-09-12. Simulator: iPhone 15 Pro Max, iOS 26.5.

## Implemented

- Primary Chats tab hosting WhatsApp's interface, with shared Session and Diagnostics tabs.
- Explicit first connection and automatic reopening of the existing profile after launch.
- Foreground refresh without reloading the current chat or draft.
- Page-size menu, confirmed reload, confirmed local-profile disconnect, and page failure/process-termination recovery.
- External user-clicked web links open outside the chat view; script redirects cannot replace the main page with an external site.
- Released-browser callbacks cannot repopulate disconnected session state.
- Existing CI macro/plugin build options applied consistently to the main app, with Metal toolchain provisioning before its MLX-dependent build. Workflows and secret gates remain enabled.

## Observed

- Final app build, installation, and launch succeeded on iPhone 15 Pro Max with Xcode 26.6.
- First launch shows Open WhatsApp with translation explicitly disabled.
- Opening loads the WhatsApp page in Chats. Continue to WhatsApp Web reaches QR login.
- Returning through Session and Open Chats preserves the existing page and selected page size.
- The page-size menu applies the selected size; reload presents its unfinished-message warning before navigation.
- Relaunch automatically reopens WhatsApp without another Open WhatsApp action. This is unauthenticated profile reopening, not evidence of authenticated-session restoration.
- 95 native-core tests passed. Focused SwiftLint, project syntax, and whitespace checks passed.

## Required account-dependent tests

The simulator has not been linked to an account by the agent. The user must complete linking in the WhatsApp app, keeping codes and credentials out of chat and repository artifacts. After linking, verify chat browsing, history scrolling, composing, sending an explicitly authorized test message, receiving it, relaunch restoration, and offline reconnect. Disconnect and error recovery still require runtime acceptance testing beyond their compiled implementation.

No successful send, delivery acknowledgement, authenticated restoration, or offline sync is claimed. No real-message native bridge, custom SwiftUI conversation UI, or translation engine was enabled. Physical-device requirements in #5, #6, and #122 remain separate. This handoff does not close the broader native transport/UI roadmap.
