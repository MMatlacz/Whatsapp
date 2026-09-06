# AGENTS.md

## Repository direction

- `apple` is the canonical/default development branch for the Apple-native implementation.
- Do not push implementation changes directly to `apple` during normal development.
- Create a focused branch for each change and merge it into `apple` through a pull request.
- A pull request must not be merged until all required CI checks pass, including the repository secret checks.
- Do not bypass, disable, weaken, or mark secret checks as optional unless the user explicitly requests a security-policy change.

## Current implementation focus

- The active native application lives under `native-ios/`.
- The project is migrating toward a native SwiftUI iOS/macOS architecture.
- Current architecture work includes:
  - WhatsApp Web transport through Apple WebKit where feasible;
  - Apple Foundation Models / on-device language models for contextual translation;
  - local-first storage and privacy;
  - no backend unless the product direction explicitly changes.

## GitHub workflow

- Roadmap work is tracked with GitHub issues and milestones.
- Update the relevant issue with meaningful implementation findings or blockers when useful.
- Do not close an issue until its acceptance criteria are actually met.
- Use focused branches and commits that reference the relevant roadmap item when appropriate.
- Open a pull request targeting `apple` for implementation, build, workflow, configuration, and documentation changes.
- Before merging, confirm the PR is up to date enough to receive the current required checks and that those checks pass.

## Secret and sensitive-data policy

- Never commit credentials, API keys, access tokens, refresh tokens, private keys, signing material, session state, WhatsApp pairing/authentication material, or local credential stores.
- Never commit `.pi/`, `.env`/`.env.*`, provider auth files, private key/certificate files, or generated logs that may contain credentials or personal data.
- The automated `Secret checks` GitHub Actions workflow is a required merge gate for `apple`.
- If a secret check fails, investigate and remove the sensitive material rather than suppressing the finding. Add an allowlist only for a confirmed false positive and keep it as narrow as possible.
- If a real secret reaches Git history, treat it as compromised: rotate/revoke it first, then purge it from history when appropriate.
- Do not paste discovered secret values into issues, PR comments, commit messages, CI logs, or chat responses.

## Safety around existing work

- Preserve unrelated user changes.
- Do not rewrite or force-update shared history unless explicitly requested.
- Do not delete branches or tags unless explicitly requested or the task specifically requires their cleanup.
