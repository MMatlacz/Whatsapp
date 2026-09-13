# Visible WebKit pairing: simulator validation

Validated on 2026-09-12 with iPhone 15 Pro Max, iOS 26.5, using the native app.

## Change

- Load WhatsApp Web opens an interactive page using the controller's existing WKWebView and dedicated persistent profile.
- Done returns to diagnostics and refreshes the session heuristic. Show WhatsApp Web reopens the same view without navigation or profile replacement.
- The phone-link shortcut presents the page even when its selector finds no entry. It also recognizes the observed "Log in with phone number" wording.
- Desktop content mode is explicit. A generated iOS launch screen removes the previous legacy 320×480 viewport and black bars.

## Observed simulator checks

- Build, install, and launch succeeded on iPhone 15 Pro Max.
- The app fills the available device screen, and Load WhatsApp Web presents the page.
- The initial WhatsApp download prompt offers Continue to WhatsApp Web. Selecting it reaches QR login.
- Scrolling the page exposes Log in with phone number. Selecting it opens the country selector, phone input, and Next button.
- Text entry works. Closing with Done and reopening with Show WhatsApp Web preserves the phone form and its entered test text.
- Diagnostics report finished navigation and successful JavaScript execution. Session detection remains a non-authoritative heuristic; it can still report unknown-ui on the phone-entry form.
- No account linking was completed, and no message was sent. Test input was not submitted with Next. App relaunch cleared the transient form instance after testing.

## Other validation and limits

- 95 native-core tests passed; focused SwiftLint reported no violations.
- Xcode project syntax and git diff whitespace checks passed.
- Local simulator builds used Xcode's -skipMacroValidation and -skipPackagePluginValidation arguments for the existing MLX dependencies. Repository CI workflows and required secret checks were not modified.
- Pairing codes, page screenshots, raw device identifiers, and runtime logs are not included in this evidence file.
- This does not establish physical-iPhone linking, authenticated-session restoration, offline synchronization, or whole-app/WebKit memory stability. Issues #5, #6, and #122 retain those gates. Production translation remains disabled.
