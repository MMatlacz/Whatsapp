# WhatsApp Translator

Source-available native Apple app experiment for local-first Indonesian -> Polish WhatsApp translation.

This project is not affiliated with WhatsApp, Meta, Apple, or OpenAI.

## Status

The active development branch is `apple`.

Current implementation focus:

- native SwiftUI iPhone app under `native-ios/`
- Apple Foundation Models / `SystemLanguageModel` experiments for on-device translation
- native WebKit experiments for WhatsApp Web transport
- local-first storage and privacy
- no backend unless the product direction explicitly changes

The legacy Electron/TypeScript implementation remains under `whatsapp-translator/` as reference material only.

## License

This repository is **source-available, not open source**.

The code is licensed under the PolyForm Noncommercial License 1.0.0. Noncommercial personal self-building, study, testing, and hobby use are permitted. Commercial use, resale, paid hosting, App Store or marketplace redistribution, inclusion in commercial products, or use by or for a business requires a separate written commercial license from the copyright holder.

The copyright holder reserves the right to distribute paid App Store or other commercial builds under separate proprietary/commercial terms.

See `LICENSE`, `CONTRIBUTING.md`, and `SECURITY.md`.

## Native iOS app

Open the native project:

```bash
open native-ios/WhatsAppTranslator.xcodeproj
```

Then:

1. Select a development team for code signing.
2. Choose a physical Apple-Intelligence-capable iPhone when testing Foundation Models.
3. Build and run the `WhatsAppTranslator` target.
4. Use the diagnostics screen to verify model availability, context size, advertised Indonesian/Polish support, and WebKit initialization.
5. Use the P0.1 benchmark screen to run the synthetic Indonesian/Polish translation benchmark.

Simulator-only success is not enough for P0/P0.1 completion because Apple Intelligence and Foundation Models behavior must be validated on real hardware.

## Roadmap workflow

Work is tracked through GitHub issues. Normal changes must use pull requests targeting `apple`.

Repository process rules:

- one focused issue per PR;
- one closing reference per PR, for example `Closes #38`;
- split oversized issues before implementation;
- do not use a closing keyword unless all acceptance criteria are met;
- use squash merge for normal PRs;
- required checks, especially `Secret checks`, must pass before merge.

## Secret and privacy policy

Never commit:

- API keys, access tokens, passwords, or OAuth credentials;
- `.env` or `.env.*` files;
- `.pi/` local agent/task state;
- WhatsApp pairing, authentication, session, or device material;
- generated logs that may contain credentials or personal data;
- private keys, certificates, signing identities, or provisioning profiles.

The repository should remain safe to publish at any time.

## Repository layout

```text
native-ios/             Native SwiftUI iPhone app and benchmark harness
whatsapp-translator/    Legacy Electron/TypeScript reference implementation
docs/                   Architecture notes, ADRs, and native benchmark docs
.github/                PR template and CI workflows
```
