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
- Use squash merge by default so `apple` receives one clean commit per PR.
- Do not require contributors to manually squash their branch before review; the merge operation should produce the clean branch history.

## Issue and pull request closure discipline

- Normal implementation PRs should close exactly one GitHub issue.
- Use a supported GitHub closing keyword in the PR body, preferably `Closes #<issue-number>`.
- Use `Fixes #<issue-number>` for bug fixes and `Resolves #<issue-number>` for decisions or workflow/process issues when that wording is clearer.
- Do not use a closing keyword unless the PR satisfies every acceptance criterion in the issue.
- If a PR only helps with an issue but does not complete it, use `Related to #<issue-number>` and create or update a smaller follow-up issue before merging implementation work.
- If an issue is too large for one PR, split it into smaller issues before implementation. The PR should close the smaller issue, not partially close the oversized parent.
- Draft PRs may be used for exploration, but they should be converted to a normal PR only after their target issue is clear and small enough to close.

## Secret and sensitive-data policy

- Never commit credentials, API keys, access tokens, refresh tokens, private keys, signing material, session state, WhatsApp pairing/authentication material, or local credential stores.
- Never commit `.pi/`, `.env`/`.env.*`, provider auth files, private key/certificate files, or generated logs that may contain credentials or personal data.
- The automated `Secret checks` GitHub Actions workflow is a required merge gate for `apple`.
- Local contributors should install and run the pre-commit hooks from `.pre-commit-config.yaml` when working outside GitHub-hosted automation.
- If a secret check fails, investigate and remove the sensitive material rather than suppressing the finding. Add an allowlist only for a confirmed false positive and keep it as narrow as possible.
- If a real secret reaches Git history, treat it as compromised: rotate/revoke it first, then purge it from history when appropriate.
- Do not paste discovered secret values into issues, PR comments, commit messages, CI logs, or chat responses.

## Source-available governance

- The project is source-available, not open source.
- The repository is licensed under the PolyForm Noncommercial License 1.0.0 in `LICENSE`.
- Noncommercial personal self-building, study, testing, and hobby use are permitted by the repository license.
- Commercial use, resale, paid hosting, App Store or marketplace redistribution, inclusion in commercial products, or use by or for a business requires a separate written commercial license from the copyright holder.
- The copyright holder reserves the right to distribute paid App Store or commercial builds under separate proprietary/commercial terms.
- Do not accept unsolicited code contributions unless the user explicitly requests them.
- Before merging external code contributions, ensure the contribution terms preserve the owner's ability to use the contribution in future paid/commercial releases.
- Contributor and security process docs live in `CONTRIBUTING.md` and `SECURITY.md`.
- Do not add files, dependencies, assets, copied code, model weights, datasets, or generated artifacts unless their license and redistribution terms are compatible with this repository.
- Preserve copyright and license notices when importing third-party code.

## Safety around existing work

- Preserve unrelated user changes.
- Do not rewrite or force-update shared history unless explicitly requested.
- Do not delete branches or tags unless explicitly requested or the task specifically requires their cleanup.
