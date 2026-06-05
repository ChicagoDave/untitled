# ADR-0008 — Reference is mechanical, never editorial

## Context

The reference system (§9) — peek, the `@`-bible, scene memory — could plausibly grow editorial features: continuity-checking, generation, structure coaching. But the product's entire premise is a tool that shuts up and handles mechanics silently (the guiding principle, §1; a load-bearing non-goal, §2).

## Decision

Reference is a peek plus a fuzzy index over the writer's own bible. No AI, no continuity-checking, no generation. Lookup is mechanical, never editorial.

## Consequences

- The tool's virtue — getting out of the way — is preserved; an opinionated assistant would violate the whole premise.
- The genuinely useful (and hard) continuity tooling is left on the table by choice.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-008.
