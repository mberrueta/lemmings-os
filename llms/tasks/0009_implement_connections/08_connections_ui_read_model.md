# Task 08: Connections UI Read Model

## Status
- **Status**: REVISED

## Objective
Show scope-aware Connection visibility using simplified fields.

## Requirements
- World page includes a Connections tab for world-scoped visibility.
- City detail includes a Connections tab for city-scoped visibility.
- Department detail includes a Connections tab for department-scoped visibility.
- Display generated label (`SourceScope / type`), status, source local/inherited marker, and `last_test`.
- Never show resolved secrets.

## Acceptance
- Read model matches nearest-wins visibility by `type`.
