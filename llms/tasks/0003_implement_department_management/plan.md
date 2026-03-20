# LemmingsOS — 0003 Implement Department Management

## Execution Metadata

- Spec / Plan: `llms/tasks/0003_implement_department_management/plan.md`
- Created: `2026-03-20`
- Status: `PLANNING`
- Related Issue: `#6`
- Upstream Dependency: Cities merged in `PR #12`

## Goal

Introduce the first real persisted `Department` foundation in LemmingsOS as a child of `City`.

The branch should end with:

- a persisted `departments` table scoped by both `world_id` and `city_id`
- a real `LemmingsOs.Departments.Department` schema and `LemmingsOs.Departments` context
- status-aware Department lifecycle APIs and operator actions
- Department participation in hierarchical config resolution through `World -> City -> Department`
- real Department-backed read models for Cities and Departments pages
- a simplified, truthful Home overview that surfaces real topology counts
- a real Department detail page with `Overview`, `Lemmings`, and `Settings` tabs
- an initial Department settings foundation with inherited guardrails
- deletion guardrails that block unsafe hard deletes

## Scope Included

- `departments` persistence foundation and migration
- `LemmingsOs.Departments.Department` schema
- `LemmingsOs.Departments` context / domain boundary
- Department metadata fields:
  - `slug`
  - `name`
  - `status`
  - `notes`
  - `tags`
- Department split config buckets:
  - `limits_config`
  - `runtime_config`
  - `costs_config`
  - `models_config`
- tag normalization on write
- Department lifecycle APIs and convenience wrappers
- extending `LemmingsOs.Config.Resolver` to `World -> City -> Department`

## Frozen Contracts / Resolved Decisions

### 1. Department identity and ownership

- `Department` is a real persisted child of `City`.
- Every Department row must include both `world_id` and `city_id`.
- `world_id` remains explicit to preserve the project rule that World-scoped entities carry their World ownership directly.
- `city_id` is the immediate structural parent.

### 2. Department table shape

Initial persisted shape:

```text
departments
  id
  world_id
  city_id
  slug
  name
  status
  notes
  tags
  limits_config
  runtime_config
  costs_config
  models_config
  inserted_at
  updated_at
```

### 3. `slug`

- required
- unique per city
- DB unique index must be `[:city_id, :slug]`

### 4. `name`

- required
- not unique

### 5. `status`

Allowed persisted lifecycle values:

- `active`
- `draining`
- `disabled`

### 6. `notes`

- plain text only
- lightweight operator-facing metadata
- no rich text
- no HTML rendering
- small bounded max length

### 7. `tags`

- stored as an array of strings
- default `[]`
- normalized on write
- normalization rules:
  - trim
  - downcase
  - convert whitespace / underscores / repeated separators to `-`
  - reject blanks
  - deduplicate

### 8. Config model

- Departments use the same split bucket model already used by Worlds and Cities.
- Department rows persist local overrides only.
- Effective config must be resolved through the existing resolver, extended to `World -> City -> Department`.

## Task Breakdown

| Task | Agent | Description |
|---|---|---|
| 01 | `dev-db-performance-architect` | departments migration, FKs, indexes, and constraint review |
| 02 | `dev-backend-elixir-engineer` | Department schema, changeset rules, tag normalization |
| 03 | `dev-backend-elixir-engineer` | Departments context and lifecycle APIs |
| 04 | `dev-backend-elixir-engineer` | `Config.Resolver` extension to Department scope |

## Task Sequence

| # | Task | Status | Approved | Dependencies |
|---|---|---|---|---|
| 01 | Departments Migration and Indexes | COMPLETE | [x] | None |
| 02 | Department Schema and Tag Normalization | COMPLETE | [ ] | Task 01 |
| 03 | Departments Context and Lifecycle APIs | COMPLETE | [ ] | Task 02 |
| 04 | Config Resolver Department Extension | COMPLETE | [ ] | Task 02 |
