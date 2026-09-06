# Security Policy

## Reporting a vulnerability

Please do not report security issues by opening a public GitHub issue.

Use GitHub's private vulnerability reporting flow when it is enabled for this repository. If that is not available, contact the repository owner privately through GitHub and include enough detail to reproduce the issue without including unrelated personal data.

Security reports, vulnerability reproductions, and proof-of-concept descriptions do not grant any right to use this project commercially. The repository remains licensed under the PolyForm Noncommercial License 1.0.0 unless a separate written commercial license says otherwise.

For suspected leaked credentials, tokens, WhatsApp pairing/authentication material, signing material, or session state:

1. Revoke or rotate the affected secret first.
2. Remove the material from the working tree.
3. Purge it from reachable Git history when appropriate.
4. Verify with the repository secret checks before merging.

Do not paste secret values into issues, pull requests, commit messages, CI logs, screenshots, or chat transcripts.

## Supported versions

This project is still pre-release. Security fixes are applied to the `apple` branch only unless another supported branch is explicitly documented.

## Security expectations

The repository should remain safe to publish at any time. Never commit:

- API keys, provider tokens, access tokens, or refresh tokens
- OAuth credentials or local provider auth stores
- private keys, certificates, signing identities, or provisioning profiles
- `.env` or `.env.*` files
- `.pi/` local agent/task state
- WhatsApp pairing, authentication, session, or device credentials
- generated logs that may contain credentials, message contents, local paths, or personal data

All pull requests targeting `apple` must pass the `Secret checks` workflow before merge.

## Commercial use

The public source is available for permitted noncommercial purposes only. Commercial deployment, App Store or marketplace redistribution, paid hosting, resale, inclusion in commercial products, or use by or for a business requires a separate written commercial license from the copyright holder.
