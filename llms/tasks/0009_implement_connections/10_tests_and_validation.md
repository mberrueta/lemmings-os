# Task 10: Tests and Validation

## Status
- **Status**: REVISED

## Objective
Validate the simplified Connections MVP behavior.

## Required Coverage
- schema + uniqueness by type/scope
- hierarchy nearest-wins by type
- runtime facade without Secret Bank calls
- caller-only secret resolution
- UI type dropdown + default config population
- no raw secret leakage in UI/events/errors/runtime facade/`last_test`

## Acceptance
- Deterministic tests pass for the revised model.
