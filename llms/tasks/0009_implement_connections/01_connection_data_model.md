# Task 01: Connection Data Model

## Status
- **Status**: REVISED

## Objective
Define the simplified `connections` table used by the corrected MVP.

## Requirements
- Keep one row per `type` per exact scope.
- Columns: `id`, `world_id`, `city_id`, `department_id`, `type`, `status`, `config`, `last_test`, timestamps.
- Remove old model fields (`slug`, `name`, `provider`, `secret_refs`, `metadata`, `last_tested_at`, `last_test_status`, `last_test_error`).
- Add scope-shape check constraint.
- Add partial unique indexes by scope for `type`.
- Keep parent scope owner FKs as non-promoting (`delete_all` or restrict).

## Acceptance
- Migration reflects the simplified schema exactly.
- Scope-shape and uniqueness constraints are enforced by DB.
