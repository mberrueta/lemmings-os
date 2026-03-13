# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for LemmingsOS.

## Promotion rule

Working analysis can live in `llms/tasks/**`, but once a decision is accepted it
must be captured here as an ADR.

## Suggested naming

Use `NNNN-short-title.md`, for example: `0004-lemming-identity-model.md`.

## ADR format

Each ADR should include these sections:

* **Status** — Proposed / Accepted / Deprecated / Superseded
* **Date** — YYYY-MM-DD
* **Decision Makers** — who made the call
* **Context** — the problem or situation requiring a decision
* **Decision Drivers** — constraints and goals that shaped the choice
* **Considered Options** — alternatives evaluated (at least 2)
* **Decision** — what was decided
* **Rationale** — why this option best satisfies the drivers
* **Consequences** — positive outcomes, trade-offs, and follow-ups
* **Implementation Notes** — actionable steps (if applicable)
