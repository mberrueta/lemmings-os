# Task 02: Connection Schema and Changeset

## Status
- **Status**: REVISED

## Objective
Update `LemmingsOs.Connections.Connection` to the simplified fields and validation model.

## Requirements
- Schema fields: `type`, `status`, `config`, `last_test`, scope FKs.
- Required fields: `world_id`, `type`, `status`, `config`.
- Validate status in `enabled|disabled|invalid`.
- Validate scope shape.
- Validate `type` through registry.
- Validate `config` using type module behavior.
- Add unique constraints aligned with new DB index names.

## Acceptance
- No old fields remain in schema/changeset.
- Changeset enforces type and config validity for registered types.
