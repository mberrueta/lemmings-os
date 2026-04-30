# Task 12: Security Audit for Secret Leakage

## Status
- **Status**: REVISED

## Objective
Audit the revised Connections implementation for secret leakage and scope isolation.

## Requirements
- Runtime facade never calls Secret Bank.
- Only caller modules resolve secret refs.
- No raw secrets in persistence/UI/events/logs/errors/runtime descriptors.
- Cross-world and sibling-department isolation intact.

## Acceptance
- No leak paths in reviewed code and tests.
