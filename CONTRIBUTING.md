# Contributing

Thanks for helping improve WhatsApp Translator.

## Branch and pull request workflow

- `apple` is the default development branch.
- Create a focused branch from `apple` for every change.
- Open a pull request targeting `apple`.
- Do not merge until all required checks pass, especially `Secret checks`.
- Keep pull requests small enough to review carefully.
- Reference the relevant GitHub issue when the change implements roadmap work.

Direct pushes to `apple` are reserved for emergency repository maintenance only.

## Local setup

The active native implementation lives under `native-ios/`.

Requirements for native iOS work:

- Xcode with the SDK required by `native-ios/README.md`
- a physical Apple-Intelligence-capable iPhone for Foundation Models validation
- a burner WhatsApp account for transport experiments

Legacy TypeScript/Electron code is still present under `whatsapp-translator/` as historical/reference material.

## Before opening a pull request

Run the checks that apply to your change:

```bash
git status --short
```

For secret hygiene, install `gitleaks` locally and run:

```bash
gitleaks detect --redact --source .
```

If you use `pre-commit`, install the hooks once:

```bash
pre-commit install
```

Then run them before pushing:

```bash
pre-commit run --all-files
```

## Secrets and sensitive data

Never commit:

- API keys, tokens, passwords, or OAuth credentials
- `.env` or `.env.*` files
- `.pi/` local agent/task state
- WhatsApp pairing/authentication/session data
- generated logs that may contain credentials or personal data
- private keys, certificates, signing identities, or provisioning profiles

If CI reports a real secret, rotate/revoke it first, then remove it from the repository and history as appropriate.

## Code style

- Prefer small, testable modules with explicit boundaries.
- Keep WhatsApp transport, storage, UI, and translation engines decoupled.
- Do not let product/UI code depend directly on a specific language model or transport implementation.
- Preserve existing documentation and implementation notes unless the change intentionally supersedes them.

## License

By contributing, you agree that your contributions are licensed under the MIT License in this repository.
