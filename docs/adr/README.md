# Architecture Decision Records

Use Architecture Decision Records (ADRs) for decisions that materially affect the product architecture, security model, privacy posture, platform support, storage model, transport layer, or model/runtime strategy.

## File naming

Use numbered, lowercase, hyphenated filenames:

```text
0001-use-webkit-for-whatsapp-transport.md
0002-use-local-on-device-translation.md
```

## Template

```md
# ADR NNNN: Title

## Status

Proposed | Accepted | Superseded

## Context

What problem are we solving? What constraints matter?

## Decision

What are we choosing?

## Alternatives considered

- Alternative A: why not?
- Alternative B: why not?

## Consequences

What becomes easier, harder, riskier, or more expensive because of this decision?

## Follow-up

What should be validated later?
```

Keep ADRs concise. Link to issues, pull requests, research notes, and benchmark results when useful.
