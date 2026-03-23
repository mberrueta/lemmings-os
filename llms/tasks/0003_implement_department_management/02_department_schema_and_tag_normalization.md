# Task 02: Department Schema and Tag Normalization

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 01
- **Blocks**: Task 03, Task 04
- **Estimated Effort**: M

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for schemas, changesets, and domain-side validation.

## Objective
Create the persisted Department schema with lifecycle helpers, metadata validation, shared config embeds, and canonical tag normalization.

## Expected Outputs

- [x] new `LemmingsOs.Departments.Department` schema module
- [x] changeset rules for status, notes, tags, and config embeds
- [x] helper functions for statuses and tag normalization

## Acceptance Criteria

- [x] schema follows repo naming and `@required` / `@optional` conventions
- [x] `notes` is validated as bounded plain text metadata
- [x] tags normalize trim/downcase/separator cleanup/reject blank/deduplicate
- [x] schema exposes status helpers consistent with current World/City patterns
- [x] no context queries or LiveView code are introduced in this task

## Execution Summary
Implemented by Codex with a parallel implementation review from `dev-backend-elixir-engineer`.

### Work Performed
- Added the new persisted schema module `LemmingsOs.Departments.Department`.
- Matched the existing World/City conventions for `@required`, `@optional`, `:binary_id`, split config embeds, helper functions, and translated status options.
- Moved slug and tag normalization logic into the shared `LemmingsOs.Helpers` module and reused it from Department and factories.
- Implemented reusable Department tag normalization that trims, downcases, collapses repeated separators into `-`, rejects blanks, and deduplicates while preserving first-seen order.
- Added schema-focused ExUnit coverage for changeset validation, tag normalization, translated status helpers, uniqueness, and FK constraints.
- Updated the Task 01 migration summary to reflect application-level status validation.

### Outputs Created
- `lib/lemmings_os/departments/department.ex`
- `lib/lemmings_os/helpers.ex`
- `test/lemmings_os/departments/department_test.exs`
- `test/lemmings_os/helpers_test.exs`
- `test/support/factory.ex`
- `priv/gettext/en/LC_MESSAGES/default.po`
- `priv/gettext/es/LC_MESSAGES/default.po`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| `notes` should use a 280-character application-level limit | The plan requires a small bounded operator note field but does not freeze a numeric limit; 280 is a conservative V1 bound suitable for card/detail presentation |
| Repeated runs of whitespace, hyphens, and underscores should collapse to a single `-` | This matches the updated tag normalization decision and avoids storing visually distinct but equivalent tags |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Used `assoc_constraint/2` for both `world` and `city` | `foreign_key_constraint/2` with generated FK names | Aligns with existing schema style and keeps the constraint declaration tied to association names |
| Named the slug uniqueness validation `:departments_city_id_slug_index` | A generic `unique_constraint(:slug)` without explicit index name | The persisted uniqueness contract is composite on `[:city_id, :slug]`, so the changeset must point at the real DB index |
| Added tests in this task instead of deferring all coverage to a later phase | Waiting for a later test phase | The constitution requires executable logic changes to ship with tests in the same change set |

### Blockers Encountered
- None

### Verification
- `mix test test/lemmings_os/departments/department_test.exs`
