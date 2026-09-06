# AGENTS.md

## Repository direction

- `apple` is the canonical/default development branch for the Apple-native implementation.
- New implementation work should be based on and pushed directly to `apple` unless explicitly instructed otherwise.
- Pull requests are **not required** for normal development in this repository. Do not create a PR unless the user explicitly asks for one.
- `legacy-main` preserves the earlier Electron/desktop implementation and should be treated as reference/legacy code unless a task explicitly targets it.
- `main` may exist for compatibility/history, but do not assume it is the active integration branch. Prefer `apple`.

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
- Direct commits to `apple` are expected; use focused commit messages that reference the relevant roadmap item when appropriate.

## Safety around existing work

- Preserve unrelated user changes.
- Do not rewrite or force-update shared history unless explicitly requested.
- Do not delete `legacy-main` or other preserved branches without explicit instruction.
