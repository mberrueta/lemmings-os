# Task 04: Hierarchy Lookup and Read Model

## Status
- **Status**: REVISED

## Objective
Implement nearest-wins visibility by `type` across World/City/Department scopes.

## Requirements
- Visible list and resolver keyed by `type`.
- Child override by same `type` shadows parent.
- Sibling department isolation and world isolation are preserved.
- Read model exposes source scope and local/inherited flags.

## Acceptance
- Visible rows do not duplicate shadowed parent rows of same `type`.
- Resolution follows Department -> City -> World.
