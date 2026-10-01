# Architecture Decision Records

This directory holds Architecture Decision Records (ADRs): short documents capturing a significant decision, its context and its consequences.

ADRs are created when a decision is actually made — never in advance.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-notch-window-strategy.md) | Notch window strategy | Accepted |
| [0002](0002-activity-engine.md) | Activity Engine and notch state machine | Accepted |
| [0003](0003-app-runtime-configuration.md) | App runtime configuration | Accepted (sandbox to revisit) |
| [0004](0004-command-center-presentation.md) | Command center presentation | Accepted |

## When to write one

- The decision is hard or expensive to reverse.
- It affects more than one domain (e.g. Core and UI).
- There were real alternatives and the reasoning matters to future contributors.

## Naming

`NNNN-short-kebab-title.md`, numbered sequentially, e.g. `0001-notch-window-strategy.md`.

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN | Deprecated
- Date: YYYY-MM-DD

## Context

What problem are we solving? What constraints apply (performance, privacy, public-API-only, etc.)?

## Decision

What we decided.

## Alternatives Considered

What else we evaluated and why it was rejected.

## Consequences

What becomes easier or harder. Follow-up work.
```

Accepted ADRs are not edited to change their decision; write a new ADR that supersedes them.
