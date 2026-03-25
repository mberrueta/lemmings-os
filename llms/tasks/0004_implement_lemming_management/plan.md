# LemmingsOS — 0004 Implement Lemming Management

## Execution Metadata

- Spec / Plan: `llms/tasks/0004_implement_lemming_management/plan.md`
- Created: `2026-03-23`
- Status: `PLANNING`
- Related Issue: `#7`
- Upstream Dependency: Departments merged in `PR #13`

## Goal

Introduce the first real persisted **Lemming definition** foundation in LemmingsOS as a child of `Department`.

The branch should end with:

- a persisted `lemmings` table scoped by `world_id`, `city_id`, and `department_id`
- a real `LemmingsOs.Lemmings.Lemming` schema and `LemmingsOs.Lemmings` context
- status-aware Lemming lifecycle APIs and operator actions
- Lemming participation in hierarchical config resolution through `World -> City -> Department -> Lemming`
- a new `tools_config` shared config embed module introduced at the Lemming level
- real Lemming-backed read models for the Departments and Lemmings pages
- a simplified, truthful Home overview that surfaces real topology counts including Lemmings
- a real Department-scoped Lemming listing replacing the current mock-backed `department_lemming_preview`
- a real Lemming detail/read page showing the stored definition
- a Department-scoped Lemming create flow
- deletion guardrails that block unsafe hard deletes
- import/export support for Lemming definitions (JSON)

---

## Project Context

### Related Entities

- `LemmingsOs.Worlds.World` - Top-level isolation boundary; grandparent scope for Lemmings
  - Location: `lib/lemmings_os/worlds/world.ex`
  - Key fields: `slug`, `name`, `status`, config buckets
- `LemmingsOs.Cities.City` - Runtime node; parent City scope for Lemmings
  - Location: `lib/lemmings_os/cities/city.ex`
  - Key fields: `slug`, `name`, `node_name`, `status`, `last_seen_at`, config buckets
- `LemmingsOs.Departments.Department` - Direct structural parent for Lemmings
  - Location: `lib/lemmings_os/departments/department.ex`
  - Key fields: `slug`, `name`, `status`, `notes`, `tags`, config buckets
- `LemmingsOs.Config.Resolver` - Hierarchical config resolution; must be extended to Lemming scope
  - Location: `lib/lemmings_os/config/resolver.ex`
  - Currently resolves: `World -> City -> Department`
- `LemmingsOs.Config.LimitsConfig` - Shared limits config embed
  - Location: `lib/lemmings_os/config/limits_config.ex`
  - Already includes `max_lemmings_per_department`
- `LemmingsOs.Config.RuntimeConfig` - Shared runtime config embed
- `LemmingsOs.Config.CostsConfig` - Shared cost config embed with nested `Budgets`
- `LemmingsOs.Config.ModelsConfig` - Shared models config embed with `providers`/`profiles`

### Related Features

- **Department Management** (`lib/lemmings_os_web/live/departments_live.ex`)
  - Pattern to follow: city selector, department listing, detail tabs (overview/lemmings/settings)
  - Department detail currently uses `MockData.lemmings_for_department/1` for the Lemmings tab
  - Reusable components in `lib/lemmings_os_web/components/world_components.ex`
- **Lemmings page (mock)** (`lib/lemmings_os_web/live/lemmings_live.ex`)
  - Currently backed entirely by `LemmingsOs.MockData.lemmings/0`
  - Uses `LemmingsOsWeb.LemmingComponents.lemmings_page/1` for rendering
- **Create Lemming page (mock)** (`lib/lemmings_os_web/live/create_lemming_live.ex`)
  - Fully mock-backed form; no persistence; dispatches `put_flash` on "save"
  - Form fields: `name`, `role`, `model`, `system_prompt` (mock concepts, not final schema)
- **Home Dashboard** (`lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`)
  - `build_topology_card_meta/1` already counts cities and departments; must add Lemming counts
- **Cities page snapshot** (`lib/lemmings_os_web/page_data/cities_page_snapshot.ex`)
  - Department cards already shown per selected city; Lemming counts can be surfaced here

### Naming Conventions Observed

- **Context modules**: `LemmingsOs.Worlds`, `LemmingsOs.Cities`, `LemmingsOs.Departments` (plural noun)
- **Schema modules**: `LemmingsOs.Worlds.World`, `LemmingsOs.Cities.City`, `LemmingsOs.Departments.Department` (nested under context, singular)
- **Config embeds**: `LemmingsOs.Config.{LimitsConfig, RuntimeConfig, CostsConfig, ModelsConfig}`
- **Tables**: `worlds`, `cities`, `departments` (plural snake_case)
- **Primary keys**: UUID via `@primary_key {:id, :binary_id, autogenerate: true}`
- **Timestamps**: `timestamps(type: :utc_datetime)`
- **Context functions**: `list_*`, `fetch_*`, `get_*!`, `create_*`, `update_*`, `delete_*`, `topology_summary`
- **Lifecycle helpers**: `activate_*`, `drain_*`, `disable_*`, `set_*_status`
- **Status helpers**: `statuses/0`, `status_options/0`, `translate_status/1`
- **Changesets**: declare `@required` and `@optional`, use `cast` + `validate_required`
- **Filter pattern**: private multi-clause `filter_query/2` with pattern matching on keyword list
- **Page snapshots**: `LemmingsOsWeb.PageData.*Snapshot` modules
- **Factories**: `LemmingsOs.Factory` in `test/support/factory.ex`
- **Error modules**: `LemmingsOs.Departments.DeleteDeniedError` (defexception under context namespace)
- **Gettext domain**: `dgettext("default", ".lemming_status_*")` for status translations
- **i18n keys**: dot-prefixed (`.some_key`)

### ADRs That Constrain This Work

- **ADR 0002**: `World -> City -> Department -> Lemming` hierarchy is canonical
- **ADR 0003**: World is the hard isolation boundary; all Lemming APIs must be World-scoped
- **ADR 0008**: Lemming persistence model (defines `lemming_types` and `lemming_instances` as architectural targets; this issue implements the definition layer only)
- **ADR 0020**: hierarchical configuration model; must support `World -> City -> Department -> Lemming` inheritance
- **ADR 0021**: core domain schema; describes `lemming_types` (World-scoped definitions) and `lemming_instances` (runtime executions); this issue diverges by using Department-scoped `lemmings` table -- see Terminology section

---

## Terminology Alignment

### Critical Divergence: `lemmings` vs `lemming_types`

ADR-0021 describes two entities:

- `lemming_types` -- World-scoped agent definitions with `module`, `default_config_jsonb`, `capabilities_jsonb`, `version`
- `lemming_instances` -- runtime execution records bound to a Department

Issue #7 introduces `lemmings` as a **Department-scoped agent definition** with `instructions`, `description`, config buckets, and status. This is conceptually closer to what ADR-0021 calls `lemming_types`, but with key differences:

1. **Scope**: `lemming_types` is World-scoped; `lemmings` is Department-scoped
2. **Identity**: `lemming_types` has `module`; `lemmings` has `instructions`
3. **Table name**: `lemming_types` vs `lemmings`

This divergence is intentional per Issue #7. The spec explicitly states:

- "We are not introducing a separate type/assignment model in this PR"
- "A lemming definition belongs directly to a department"
- A future runtime entity (e.g., `lemming_instances`) will be added separately

**The ADR must be updated** in this branch to document this narrowing, following the precedent set by Cities (ADR-0021 update for split config columns) and Departments.

### Mock Data Field Mapping

The existing mock data uses runtime-oriented fields that are explicitly **out of scope** for this issue:

| Mock field | This issue | Notes |
|---|---|---|
| `role` | Not persisted | Conceptually replaced by `instructions` + `description` |
| `current_task` | Out of scope | Runtime instance concern |
| `status` (`:running`, `:thinking`, `:idle`, `:error`) | Different statuses | Definition uses `draft`, `active`, `archived` |
| `model` | Not a direct field | Part of `models_config` via config merge |
| `system_prompt` | Conceptually `instructions` | But `instructions` is the behavioral definition, not runtime prompt |
| `tools` | Not a direct field | Part of `tools_config` via config merge |
| `recent_messages` | Out of scope | Runtime instance concern |
| `activity_log` | Out of scope | Runtime instance concern |
| `accent` | Not persisted | Visual attribute, may be added later |

---

## Frozen Contracts / Resolved Decisions

### 1. Lemming identity and ownership

- `Lemming` is a real persisted child of `Department`.
- Every Lemming row must include `world_id`, `city_id`, and `department_id`.
- `world_id` remains explicit to preserve the project rule that World-scoped entities carry their World ownership directly.
- `city_id` is explicit for the same reason (Department already carries both).
- `department_id` is the immediate structural parent.

### 2. Lemming table shape

Initial persisted shape:

```text
lemmings
  id
  world_id
  city_id
  department_id
  slug
  name
  description
  instructions
  status
  limits_config
  runtime_config
  costs_config
  models_config
  tools_config
  inserted_at
  updated_at
```

### 3. `slug`

- required
- unique per department
- DB unique index must be `[:department_id, :slug]`

### 4. `name`

- required
- not unique

### 5. `description`

- optional
- plain text only
- operator-facing summary of what the lemming does
- bounded max length (similar to Department `notes`)

### 6. `instructions`

- nullable at the DB level (a `draft` lemming may not yet have instructions)
- **required for `active` status** -- a Lemming cannot be activated without `instructions`; the `activate_lemming/1` function and any status transition to `active` must validate presence
- text field (no length constraint at the DB level; application-level guidance)
- the core behavioral definition of the lemming
- stored exactly as authored (mixed-language acceptable)
- does NOT contain runtime-owned details (tools list, available agents, retry logic)
- runtime prompt assembly will combine `instructions` with injected runtime context

### 7. `status`

Allowed persisted lifecycle values:

- `draft` -- editable, not intended for runtime use
- `active` -- visible and operationally available
- `archived` -- historical/reference only, not operational

Only `active` lemmings should participate in normal operational flows. `draft` and `archived` lemmings are visible to operators but should not be selectable for runtime instantiation.

### 8. Config model

- Lemmings use the same split bucket model already used by Worlds, Cities, and Departments.
- Lemming rows persist local overrides only.
- Effective config must be resolved through the existing resolver, extended to `World -> City -> Department -> Lemming`.
- Lemmings add a fifth bucket: `tools_config`.

### 9. `tools_config` — PROVISIONAL, Lemming-only in v1

> **Intentional asymmetry.** This is a deliberate provisional decision for this PR, not an oversight.
> The four existing config buckets (limits, runtime, costs, models) live at every level of the hierarchy (World → City → Department). `tools_config` breaks that symmetry by existing **only at the Lemming level** in this issue.
>
> **Why now:** tools are a core safety and execution boundary; Lemmings need tool-level config from day one.
>
> **Why not everywhere yet:** there is no concrete use case for `tools_config` at Department/City/World today. Adding it without a use case would be speculative and would require migration + schema changes across 3 entities.
>
> **Future path:** `tools_config` is expected to propagate upward to Department → City → World in a future issue, at which point it will participate in normal hierarchical merge like the other 4 buckets. The `ToolsConfig` embedded schema and resolver design must be built to support this upgrade path without breaking changes.

- A new shared embedded schema `LemmingsOs.Config.ToolsConfig` must be created (same pattern as `LimitsConfig`, `RuntimeConfig`, etc.).
- **v1 shape is intentionally minimal — two fields only:**
  - `allowed_tools` — list of tool name strings (default `[]`)
  - `denied_tools` — list of tool name strings (default `[]`)
- **Explicitly NOT in this PR:**
  - per-tool overrides or per-tool config maps
  - approval hints, confirmation requirements, or restriction levels
  - tool categories, namespaces, or grouping
  - any tool governance, policy, or authorization model
  - nested structs inside `ToolsConfig`
- The embed should be a flat struct with two list fields. If future issues need richer tool governance, they extend the embed then — not now.
- **Governance semantics disclaimer:** v1 `ToolsConfig` is a local config bucket only. It does NOT define merge semantics (override-dominant vs deny-dominant), does NOT redefine or narrow ADR-0012 / ADR-0020 governance rules, and does NOT constitute a tool authorization model. When `tools_config` propagates upward in a future issue, the merge strategy (e.g., should `denied_tools` at World level be override-dominant or union-dominant?) must be designed then with its own ADR discussion. v1 sidesteps this entirely because there is only one level (Lemming) — no merge conflict is possible.
- World, City, and Department schemas are **NOT modified** in this issue — no `tools_config` column, no migration.
- The `Config.Resolver` should merge `tools_config` at the Lemming level only; parent levels contribute empty/nil.
- When resolving at World/City/Department scope, `tools_config` is NOT included in the return map (backward compatible).

**ADR obligation:** The ADR update for this PR (ADR-0020) must explicitly document: (1) the asymmetry as a provisional decision with rationale and expected future propagation path; (2) that v1 `ToolsConfig` carries no governance semantics and does not alter ADR-0012 / ADR-0020 merge rules.

### 10. Language model

- The operating language is defined by the City.
- `Lemming` does NOT have a `language` field.
- `instructions` are stored as authored; mixed-language acceptable.

### 11. Import/export — minimal, context-first

> **Scope guard.** The primary deliverable is context-level functions (`export_lemming/1`, `import_lemmings/4`). The UI is intentionally minimal to avoid scope creep in this PR.

- Context functions for JSON export (single definition) and import (single or batch into a Department) are required.
- Format: JSON with `name`, `slug`, `description`, `instructions`, `status`, config buckets.
- **`schema_version` field**: exported JSON must include a top-level `"schema_version": 1` field. Import must read and respect it. v1 import should accept `schema_version: 1` (or missing, for forward tolerance) and reject unknown future versions with a clear error. This is cheap to add now and protects future imports from silent misinterpretation.
- No full external skill importer in this issue.
- **UI ceiling for this PR:**
  - Export: a simple "Export JSON" action on the Lemming detail view (downloads a `.json` file)
  - Import: a simple "Import JSON" action on the Department Lemmings tab (paste or file upload, no wizard, no preview, no field mapping)
  - No drag-and-drop, no multi-step wizard, no import preview/diff, no progress bar
- If the minimal UI proves too costly during implementation, the UI portion can be deferred to a follow-up issue while keeping the context functions in this PR.

---

## User Stories

### US-1: List Lemmings within a Department

As an **operator**, I want to see all Lemming definitions within a selected Department, so that I can understand what agents are defined and their current lifecycle status.

### US-2: View Lemming definition detail

As an **operator**, I want to view the full stored definition of a Lemming (name, slug, description, instructions, status, config), so that I can review its behavioral specification and configuration overrides.

### US-3: Create a new Lemming definition

As an **operator**, I want to create a new Lemming definition within a Department, so that I can define a specialized agent for that Department's purpose.

### US-4: Edit a Lemming definition

As an **operator**, I want to update an existing Lemming's name, description, instructions, status, and config overrides, so that I can refine its behavioral specification.

### US-5: Transition Lemming lifecycle status

As an **operator**, I want to change a Lemming's status between `draft`, `active`, and `archived`, so that I can control which definitions are operationally available.

### US-6: Delete a Lemming definition (guarded)

As an **operator**, I want to be prevented from deleting a Lemming definition, so that no definition is lost while the system lacks runtime signals to confirm deletion safety.

### US-7: View effective config summary on Lemming detail

As an **operator**, I want to see a summary of the effective configuration for a Lemming on its detail page, so that I can verify what values are in effect without navigating the full hierarchy.

### US-8: View Lemming counts in topology summaries

As an **operator**, I want to see Lemming definition counts on the Home dashboard and in Department cards, so that I can understand the overall topology at a glance.

### US-9: Export a Lemming definition

As an **operator**, I want to export a Lemming definition as JSON, so that I can share it, back it up, or use it as a template.

### US-10: Import Lemming definitions into a Department

As an **operator**, I want to import one or more Lemming definitions from JSON into a Department, so that I can bootstrap definitions efficiently (e.g., from LLM-assisted authoring).

### US-11: Browse Lemmings across Departments

As an **operator**, I want to browse all Lemming definitions across Departments (the top-level Lemmings page), so that I can get a cross-cutting view of all defined agents.

---

## Acceptance Criteria

### US-1: List Lemmings within a Department

**Scenario: Department has lemmings**
- **Given** a Department with 3 Lemming definitions (1 draft, 1 active, 1 archived)
- **When** the operator navigates to the Departments page and selects the "Lemmings" tab for that Department
- **Then** all 3 Lemming definitions are listed with name, slug, status badge, and description preview

**Scenario: Department has no lemmings**
- **Given** a Department with zero Lemming definitions
- **When** the operator views the "Lemmings" tab
- **Then** an empty state message is shown with a call-to-action to create the first Lemming

**Criteria Checklist:**
- [ ] Lemming list is ordered by `inserted_at` ascending, then `id` ascending (matching Department ordering convention)
- [ ] Status badges use appropriate tone: draft=default, active=success, archived=muted
- [ ] Lemming list is loaded from `LemmingsOs.Lemmings.list_lemmings/3` (real persistence)
- [ ] No `MockData` calls remain in the Departments Lemmings tab

### US-2: View Lemming definition detail

**Scenario: View active lemming**
- **Given** an active Lemming with name "code-reviewer", description, and instructions
- **When** the operator selects the Lemming from the listing
- **Then** a detail panel or page shows: name, slug, description, instructions (full text), status, config overview

**Criteria Checklist:**
- [ ] Instructions are rendered as preformatted or prose text (no truncation on detail view)
- [ ] Config section shows a read-only effective config summary (see US-7 for scope)
- [ ] `tools_config` values shown when present (allowed/denied tools)
- [ ] The detail view works for all three statuses (draft, active, archived)

### US-3: Create a new Lemming definition

**Scenario: Happy path creation**
- **Given** the operator is on the Departments page, has selected a Department, and clicks "New Lemming"
- **When** the operator fills in name ("code-reviewer"), slug is auto-generated, sets status to "draft", and provides description and instructions
- **Then** the Lemming is persisted with the correct `world_id`, `city_id`, `department_id`
- **And** a success flash is shown
- **And** the new Lemming appears in the listing

**Scenario: Slug conflict**
- **Given** a Department already has a Lemming with slug "code-reviewer"
- **When** the operator tries to create another Lemming with the same slug
- **Then** a validation error is shown inline on the slug field

**Scenario: Missing required fields**
- **Given** the operator submits the create form with an empty name
- **When** the form is validated
- **Then** inline validation errors appear for required fields

**Criteria Checklist:**
- [ ] `world_id` and `city_id` are set by the context, not from form params
- [ ] Slug uniqueness is scoped to `[:department_id, :slug]`
- [ ] Validation messages are internationalized via `dgettext("errors", ...)`
- [ ] Default status for new Lemmings is `draft`
- [ ] Config buckets default to empty structs (inherit everything from parent)
- [ ] On success: flash message shown, listing refreshed

### US-4: Edit a Lemming definition

**Scenario: Update instructions**
- **Given** an existing Lemming with instructions "You are a code reviewer"
- **When** the operator changes instructions to "You are a thorough code reviewer focused on security"
- **Then** the update is persisted and the detail view reflects the change

**Criteria Checklist:**
- [ ] All mutable fields can be updated: name, slug, description, instructions, status, config buckets
- [ ] `world_id`, `city_id`, `department_id` cannot be changed via update
- [ ] Validation errors are shown inline on the form
- [ ] On success: flash message, detail view refreshed

### US-5: Transition Lemming lifecycle status

**Scenario: Activate a draft lemming with instructions**
- **Given** a Lemming in `draft` status with non-empty `instructions`
- **When** the operator clicks "Activate"
- **Then** the status changes to `active` and the UI reflects the new status badge

**Scenario: Activate a draft lemming without instructions (denied)**
- **Given** a Lemming in `draft` status with nil or empty `instructions`
- **When** the operator clicks "Activate"
- **Then** activation is denied with an error: "Instructions are required to activate a lemming"
- **And** the status remains `draft`

**Scenario: Archive an active lemming**
- **Given** a Lemming in `active` status
- **When** the operator clicks "Archive"
- **Then** the status changes to `archived`

**Scenario: Reactivate an archived lemming**
- **Given** a Lemming in `archived` status (which already has `instructions` from when it was active)
- **When** the operator clicks "Activate"
- **Then** the status changes to `active`

**Criteria Checklist:**
- [ ] All transitions are allowed: draft -> active, active -> archived, archived -> active, draft -> archived
- [ ] **Activation guard**: any transition to `active` must validate that `instructions` is present and non-empty
- [ ] Status transition uses `LemmingsOs.Lemmings.set_lemming_status/2`
- [ ] Flash message confirms the transition (or explains denial)
- [ ] Available actions change based on current status
- [ ] "Activate" button is disabled or shows tooltip when `instructions` is empty

### US-6: Delete a Lemming definition (guarded)

**Scenario: Delete always denied**
- **Given** a Lemming definition in any status (`draft`, `active`, or `archived`)
- **When** the operator attempts to delete it
- **Then** deletion is denied with `DeleteDeniedError{reason: :safety_indeterminate}`
- **And** an error message explains that deletion is not available

**Criteria Checklist:**
- [ ] `delete_lemming/1` always raises/returns `LemmingsOs.Lemmings.DeleteDeniedError{reason: :safety_indeterminate}`
- [ ] No status, no condition, no workaround allows hard deletion in this PR
- [ ] Error message is internationalized
- [ ] UI does not expose a "Delete" button (or shows it disabled with explanatory tooltip) — deletion is not an available action in this slice

### US-7: View effective config summary on Lemming detail

> **UI ceiling.** The resolver extension is the real deliverable (backend, Task 05). The detail page shows a read-only config summary — not a rich bucket-by-bucket editor or inherited-vs-local diff view. Keep it simple.

**Scenario: Lemming inherits all config from parents**
- **Given** a Lemming with empty config buckets
- **When** the operator views the Lemming detail page
- **Then** the config section shows the effective (merged) values as a read-only summary

**Scenario: Lemming has local overrides**
- **Given** a Lemming with `runtime_config.idle_ttl_seconds: 1800` overriding a parent value
- **When** the operator views the Lemming detail page
- **Then** the config section shows the effective values including the override

**Criteria Checklist:**
- [ ] `Config.Resolver.resolve/1` accepts `%Lemming{department: %Department{city: %City{world: %World{}}}}` and returns the full merged config including `tools_config`
- [ ] Config resolution is pure in-memory; no DB access inside the resolver
- [ ] Detail page shows effective config as a read-only summary (collapsed or flat key-value list is fine)
- [ ] Local overrides are visible (at minimum: the Lemming's own config bucket values are shown in the settings/edit form)
- [ ] No requirement for a visual diff of inherited vs. local values in this PR — a simple display of the merged result is sufficient

### US-8: View Lemming counts in topology summaries

**Scenario: Home dashboard shows lemming counts**
- **Given** a World with 2 Cities, 3 Departments, and 7 Lemming definitions
- **When** the operator views the Home dashboard
- **Then** the topology card shows `7` Lemming definitions alongside City and Department counts

**Scenario: Department cards show lemming counts**
- **Given** a Department with 4 Lemming definitions (2 active, 1 draft, 1 archived)
- **When** the operator views the Cities page and selects the City containing this Department
- **Then** the Department card shows Lemming count information

**Criteria Checklist:**
- [ ] `LemmingsOs.Lemmings.topology_summary/1` returns `lemming_count` and `active_lemming_count` for a World
- [ ] `HomeDashboardSnapshot.build_topology_card_meta/1` includes `lemming_count` and `active_lemming_count`
- [ ] Department cards on the Cities page include a Lemming count

### US-9: Export a Lemming definition

**Scenario: Export single lemming as JSON**
- **Given** an active Lemming definition
- **When** the operator clicks "Export JSON" on the detail view
- **Then** a `.json` file is downloaded containing the Lemming's name, slug, description, instructions, status, and config buckets

**Criteria Checklist:**
- [ ] `export_lemming/1` context function returns a portable JSON-serializable map
- [ ] Export includes `"schema_version": 1` at the top level
- [ ] Export format is a plain JSON object with well-known keys
- [ ] Config bucket values are included as nested objects
- [ ] `world_id`, `city_id`, `department_id` are NOT included in the export (definitions are portable)
- [ ] `id` is NOT included in the export (importing creates new records)
- [ ] UI: single "Export JSON" button/link on detail view — no options, no configuration

### US-10: Import Lemming definitions into a Department

**Scenario: Import valid JSON definition**
- **Given** a valid JSON string or file with a Lemming definition
- **When** the operator imports it into a Department
- **Then** a new Lemming is created with the imported values, scoped to the target Department

**Scenario: Import with slug conflict**
- **Given** a JSON definition with slug "code-reviewer" and the Department already has that slug
- **When** the operator imports
- **Then** the import fails with a validation error about the slug conflict

**Criteria Checklist:**
- [ ] `import_lemmings/4` context function accepts JSON data (single object or array) and creates records
- [ ] Import accepts `schema_version: 1` (or missing — tolerate absence for forward compatibility)
- [ ] Import rejects unknown `schema_version` values (e.g., `2`) with a clear error
- [ ] Import creates new records; it does not update existing ones
- [ ] `world_id`, `city_id`, `department_id` are set from the import target, not from the JSON
- [ ] Validation errors are surfaced clearly (per-record errors for batch)
- [ ] Batch import of multiple definitions is supported (array of objects)
- [ ] UI: simple paste-or-upload input on Department Lemmings tab — no wizard, no preview, no field mapping
- [ ] If UI proves too costly, it can be deferred; the context functions are the hard requirement

### US-11: Browse Lemmings across Departments

**Scenario: Cross-department listing**
- **Given** a World with multiple Departments containing Lemming definitions
- **When** the operator navigates to `/lemmings`
- **Then** all Lemming definitions are listed, showing their parent Department name alongside each entry

**Criteria Checklist:**
- [ ] The Lemmings page is backed by real persistence, not `MockData`
- [ ] Each Lemming entry shows its Department and City ancestry
- [ ] No mock fields (role, current_task, recent_messages, activity_log) are rendered
- [ ] The page presents definition data only -- no runtime state pretended to be real

---

## Edge Cases

### Empty States

- [ ] No Lemming definitions exist in a Department -> Show empty state with CTA to create first Lemming
- [ ] No Lemming definitions exist in any Department in the World -> Lemmings page shows an honest empty state
- [ ] Department is `disabled` or `draining` -> Lemming creation may still be allowed (definitions are configuration, not runtime)

### Validation Errors

- [ ] Empty `name` -> Inline error: field is required
- [ ] Empty `slug` -> Inline error: field is required
- [ ] Duplicate `slug` within same Department -> Inline error: "slug has already been taken" (dgettext)
- [ ] Same `slug` in different Departments -> Allowed (uniqueness is Department-scoped)
- [ ] `status` not in allowed values -> Changeset validation error
- [ ] `description` exceeding max length -> Inline error with character count guidance
- [ ] Activate Lemming with nil/empty `instructions` -> Denied with clear error message; status remains unchanged

### Permission / Scope Errors

- [ ] Attempt to create Lemming with `department_id` belonging to a different World -> Error: `:department_not_in_world` or similar
- [ ] Attempt to create Lemming with `city_id` mismatching the Department's city -> Error caught at context level

### Delete Safety

- [ ] Delete of any Lemming (any status) -> Always denied with `DeleteDeniedError{reason: :safety_indeterminate}`
- [ ] No conditional delete logic exists in this PR — the function unconditionally denies

### Concurrent Access

- [ ] Two operators edit the same Lemming simultaneously -> Last write wins (consistent with Department behavior)
- [ ] Two operators create Lemmings with the same slug simultaneously -> One succeeds, one gets unique constraint error

### Config Resolution Edge Cases

- [ ] Lemming has nil config buckets -> Resolver returns parent (Department) effective config
- [ ] All levels have nil config -> Resolver returns struct defaults
- [ ] `tools_config` is nil at all levels -> Resolver returns empty `ToolsConfig` struct
- [ ] Lemming's parent chain is not preloaded -> Resolver must require preloaded parent chain (no DB access)

### Import/Export Edge Cases

- [ ] Import JSON with unknown extra keys -> Ignored (forward compatibility)
- [ ] Import JSON missing required fields -> Validation error per missing field
- [ ] Import empty array -> No-op, no error
- [ ] Export Lemming with empty config buckets -> Export includes empty objects, not nulls

### Boundary Conditions

- [ ] Maximum slug length: validated (reasonable bound, e.g., 100 characters)
- [ ] Maximum name length: validated (reasonable bound)
- [ ] Maximum description length: bounded (same pattern as Department `notes`, e.g., 280-500 characters)
- [ ] Instructions length: no hard DB limit, but application guidance should document expected range
- [ ] Special characters in slug: only lowercase alphanumeric and hyphens (consistent with `Helpers.slugify/1`)

---

## UX States

### Department Detail -- Lemmings Tab

| State | Behavior |
|-------|----------|
| **Loading** | Show skeleton or spinner while Lemming list loads |
| **Empty** | Show "No lemmings defined yet" with "Create Lemming" CTA button |
| **Populated** | Show Lemming list with name, slug, status badge, description preview |
| **Error** | Show error message if Department/World context cannot be resolved |

### Lemming Detail View

| State | Behavior |
|-------|----------|
| **Loading** | Show skeleton while Lemming detail and config resolution loads |
| **Not Found** | Show "Lemming not found" if ID is invalid or deleted |
| **Draft** | Show full detail with "Activate" action available |
| **Active** | Show full detail with "Archive" action available |
| **Archived** | Show full detail with "Activate" action available, visual indication of archived state |
| **Config Empty** | Show "Inheriting all configuration from parents" note in config summary (no complex empty-per-bucket UI) |

### Lemming Create Form

| State | Behavior |
|-------|----------|
| **Initial** | Empty form with default status "draft", config buckets empty |
| **Validating** | Live validation on `phx-change`, inline errors shown |
| **Submitting** | Submit button disabled during save |
| **Success** | Flash message, redirect to Lemming detail or listing |
| **Validation Error** | Inline errors on affected fields, form data preserved |
| **Slug Conflict** | Specific inline error on slug field |

### Lemming Settings/Edit Form

| State | Behavior |
|-------|----------|
| **Loaded** | Form pre-populated with current values |
| **Dirty** | Save button enabled when changes detected |
| **Saving** | Save button disabled during save |
| **Success** | Flash message, detail view refreshed |
| **Validation Error** | Inline errors, form data preserved |

### Lemmings Index Page (cross-department)

| State | Behavior |
|-------|----------|
| **Loading** | Show skeleton while world-wide Lemming list loads |
| **Empty** | Show "No lemmings defined in any department" with guidance |
| **Populated** | Show Lemming list with Department/City ancestry context |
| **World Unavailable** | Show "World not found" error state |

### Home Dashboard -- Topology Card

| State | Behavior |
|-------|----------|
| **With Lemmings** | Show city count, department count, and lemming count |
| **Zero Lemmings** | Show `0` for lemming count (honest) |

---

## What a `Lemming` Means in This Issue

In this issue, `Lemming` represents:

- the persisted **agent definition**
- its specific configuration overrides
- its scope within a Department
- the base object the runtime will later use to launch instances

It does **NOT** represent:

- a live instance
- a supervised runtime process
- real execution state
- mailbox / runtime state / checkpoints

---

## Design Philosophy

LemmingsOS encourages:

- many specialized lemmings
- not super-agents
- one primary responsibility per lemming
- composition and delegation between lemmings

The `instructions` field is the core behavioral definition in v1. We are not introducing a skill-based schema in this issue.

---

## Prompt Assembly / Runtime Contract

The final runtime prompt should NOT come 100% from the database. It should be split:

**Persisted in `lemmings`:**
- `name`
- `description`
- `instructions`
- config buckets

**Injected by runtime (future issue):**
- available tools (derived from effective `tools_config` + tool registry)
- available agents
- runtime rules
- output format / action contract
- system wrapper

This split is documented here for clarity but does NOT require implementation in this issue.

---

## Explicitly Out of Scope

1. **Runtime process creation** -- no OTP processes, no supervised Lemmings
2. **Real lemming instance execution** -- no `lemming_instances` table
3. **Runtime lifecycle fields** -- no `agent_module`, `started_at`, `stopped_at`, `instance_ref`, `parent_instance_id`
4. **Mailbox/state/checkpoint persistence** -- belongs to future runtime issue
5. **Full skill packaging/import model** -- the import/export is simple JSON, not a skill packaging system
6. **Complex multilingual translation storage** -- instructions stored as authored
7. **`tools_config` on World/City/Department** -- new embed is Lemming-only in this issue
8. **Visual attributes** (accent colors, avatars) -- may be added in a future UX issue
9. **`language` field on Lemming** -- language is City-level per frozen decision
10. **Mock runtime state rendering** -- the detail view must NOT pretend to show `current_task`, `recent_messages`, or `activity_log` from mock data

---

## Scope Included

- `lemmings` persistence foundation and migration
- `LemmingsOs.Lemmings.Lemming` schema
- `LemmingsOs.Lemmings` context / domain boundary
- `LemmingsOs.Config.ToolsConfig` shared embedded schema
- Lemming metadata fields: `slug`, `name`, `description`, `instructions`, `status`
- Lemming split config buckets: `limits_config`, `runtime_config`, `costs_config`, `models_config`, `tools_config`
- Lemming lifecycle APIs and convenience wrappers
- Extending `LemmingsOs.Config.Resolver` to `World -> City -> Department -> Lemming`
- `LemmingsOs.Lemmings.DeleteDeniedError` for safe delete guardrails
- Lemming factory in `test/support/factory.ex`
- Department Lemmings tab desmoke (replace `MockData` with real persistence)
- Lemmings index page desmoke (replace `MockData` with real persistence)
- Create Lemming page desmoke (replace mock form with real persistence)
- Home topology summary inclusion of Lemming counts
- Cities page Department cards inclusion of Lemming counts
- JSON import/export for Lemming definitions
- Tests: schema, context, resolver extension, LiveView pages
- ADR/doc updates if implementation decisions narrow existing ADR wording

---

## Recommended `lemmings` Table Shape

```text
lemmings
  id              UUID PK
  world_id        FK -> worlds.id, NOT NULL
  city_id         FK -> cities.id, NOT NULL
  department_id   FK -> departments.id, NOT NULL
  slug            string, NOT NULL
  name            string, NOT NULL
  description     text, nullable
  instructions    text, nullable
  status          string, NOT NULL, default "draft"
  limits_config   map/jsonb, NOT NULL, default {}
  runtime_config  map/jsonb, NOT NULL, default {}
  costs_config    map/jsonb, NOT NULL, default {}
  models_config   map/jsonb, NOT NULL, default {}
  tools_config    map/jsonb, NOT NULL, default {}
  inserted_at     utc_datetime
  updated_at      utc_datetime
```

### Recommended indexes / constraints

- FK index on `lemmings(world_id)`
- FK index on `lemmings(city_id)`
- FK index on `lemmings(department_id)`
- unique index on `lemmings(department_id, slug)`
- index on `lemmings(world_id, city_id, department_id, status)` (hierarchy + status filter)

### Recommended migration notes

- use `timestamps(type: :utc_datetime)`
- follow the existing `Department` migration style exactly
- use `:delete_all` on all three FK references (matching Department)
- `description` and `instructions` use `:text` type (unbounded text)

---

## Recommended `Lemming` Schema Shape

Recommended module and context:

- schema: `LemmingsOs.Lemmings.Lemming`
- context: `LemmingsOs.Lemmings`

Recommended schema responsibilities:

- persist durable Lemming definition identity and hierarchy scoping
- persist admin status
- persist local config overrides only (5 buckets)
- expose helper functions for admin status

Recommended association shape:

- `belongs_to :world, LemmingsOs.Worlds.World`
- `belongs_to :city, LemmingsOs.Cities.City`
- `belongs_to :department, LemmingsOs.Departments.Department`

Recommended changeset rules:

- declare `@required ~w(slug name status)a`
- declare `@optional ~w(description instructions)a`
- validate that status is in `["draft", "active", "archived"]`
- **activation guard**: when status is being set to `active`, validate that `instructions` is present and non-empty (custom validation in changeset or context-level guard in `activate_lemming/1`)
- validate `description` max length
- keep `world_id`, `city_id`, `department_id` controlled in context functions, not trusted from form params
- `assoc_constraint(:world)`, `assoc_constraint(:city)`, `assoc_constraint(:department)`
- `unique_constraint(:slug, name: :lemmings_department_id_slug_index)`
- cast all 5 config embeds with their respective changeset functions

Recommended helper functions:

- `statuses/0` -- returns `["draft", "active", "archived"]`
- `status_options/0` -- returns translated tuples for select inputs
- `translate_status/1` -- pattern-matched status translation via `dgettext`

---

## Recommended `Lemmings` Context Contract

The Lemmings context should mirror the rigor of `Departments`:

- explicit World + Department scoped APIs
- `opts`-based list filters
- private `filter_query/2`
- web layer talks to the context, not the schema or repo

Recommended public API surface:

```elixir
list_lemmings(world_or_world_id, department_or_department_id, opts \\ [])
list_all_lemmings(world_or_world_id, opts \\ [])
fetch_lemming(id, opts \\ [])
get_lemming!(id, opts \\ [])
fetch_lemming_by_slug(department_or_department_id, slug)
get_lemming_by_slug!(department_or_department_id, slug)
create_lemming(world_or_world_id, city_or_city_id, department_or_department_id, attrs)
update_lemming(lemming, attrs)
delete_lemming(lemming)
set_lemming_status(lemming, status)
activate_lemming(lemming)
archive_lemming(lemming)
topology_summary(world_or_world_id)
export_lemming(lemming)
import_lemmings(world_or_world_id, city_or_city_id, department_or_department_id, json_data)
```

Rules:

- all public retrieval/list APIs must require explicit world scope or be reachable through hierarchy
- the cross-department `/lemmings` page is part of branch scope, so the context must expose an explicit World-scoped listing API: `list_all_lemmings/2`; the web layer must not assemble this ad hoc by looping through Departments
- failure-returning APIs should return `{:ok, data}` / `{:error, reason}` tuples
- `create_lemming` must validate that the Department belongs to the specified City and World
- preload `:world`, `:city`, `:department` where resolver or UI read models require parent config

---

## Recommended `Config.Resolver` Extension

The resolver must gain a new clause:

```elixir
resolve(%Lemming{department: %Department{city: %City{world: %World{}}}} = lemming)
```

Required behavior:

- resolve full `World -> City -> Department` effective config first
- merge Lemming local overrides on top
- include `tools_config` in the returned map (new key)
- return type gains `:tools_config` key

Return shape for Lemming scope:

```elixir
%{
  limits_config: %LimitsConfig{},
  runtime_config: %RuntimeConfig{},
  costs_config: %CostsConfig{},
  models_config: %ModelsConfig{},
  tools_config: %ToolsConfig{}
}
```

For World, City, and Department scopes, `tools_config` is NOT added to the return map in this issue (backward compatible).

---

## Task Breakdown

| Task | Agent | Description |
|---|---|---|
| 01 | `dev-db-performance-architect` | `lemmings` migration, FKs, indexes, and constraint review |
| 02 | `dev-backend-elixir-engineer` | `ToolsConfig` shared embedded schema |
| 03 | `dev-backend-elixir-engineer` | Lemming schema, changeset rules |
| 04 | `dev-backend-elixir-engineer` | Lemmings context, lifecycle APIs, and delete guardrails |
| 05 | `dev-backend-elixir-engineer` | `Config.Resolver` extension to Lemming scope |
| 06 | `dev-backend-elixir-engineer` | Import/export context functions |
| 07 | `dev-frontend-ui-engineer` | Home topology summary -- add Lemming counts |
| 08 | `dev-frontend-ui-engineer` | Cities page Department cards -- add Lemming counts |
| 09 | `dev-frontend-ui-engineer` | Department Lemmings tab desmoke |
| 10 | `dev-frontend-ui-engineer` | Lemming detail view |
| 11 | `dev-frontend-ui-engineer` | Create Lemming page desmoke |
| 12 | `dev-frontend-ui-engineer` | Lemmings index page desmoke |
| 13 | `dev-frontend-ui-engineer` | Lemming settings/edit form |
| 14 | `dev-frontend-ui-engineer` | Import/export minimal UI (export button + paste/upload input, no wizard) |
| 15 | `qa-test-scenarios` | Test scenario and coverage plan |
| 16 | `qa-elixir-test-author` | ExUnit and LiveView tests |
| 17 | `dev-backend-elixir-engineer` | Branch validation, `mix test`, `mix precommit` |
| 18 | `audit-pr-elixir` | Security and performance review |
| 19 | `tl-architect` | ADR and architecture update (REQUIRED — current docs describe lemmings as runtime processes) |
| 20 | `audit-pr-elixir` | Final PR audit |

## Task Sequence

| # | Task | Status | Approved | Dependencies |
|---|---|---|---|---|
| 01 | Lemmings Migration and Indexes | PENDING | [ ] | None |
| 02 | ToolsConfig Shared Embedded Schema | BLOCKED | [ ] | None (can parallel with 01) |
| 03 | Lemming Schema and Changeset | BLOCKED | [ ] | Task 01, Task 02 |
| 04 | Lemmings Context and Lifecycle APIs | BLOCKED | [ ] | Task 03 |
| 05 | Config Resolver Lemming Extension | BLOCKED | [ ] | Task 03 |
| 06 | Import/Export Context Functions | BLOCKED | [ ] | Task 04 |
| 07 | Home Topology Summary -- Lemming Counts | BLOCKED | [ ] | Task 04 |
| 08 | Cities Page Department Cards -- Lemming Counts | BLOCKED | [ ] | Task 04 |
| 09 | Department Lemmings Tab Desmoke | BLOCKED | [ ] | Task 04, Task 05 |
| 10 | Lemming Detail View | BLOCKED | [ ] | Task 09 |
| 11 | Create Lemming Page Desmoke | BLOCKED | [ ] | Task 04, Task 09 |
| 12 | Lemmings Index Page Desmoke | BLOCKED | [ ] | Task 04 |
| 13 | Lemming Settings/Edit Form | BLOCKED | [ ] | Task 10 |
| 14 | Import/Export Minimal UI (deferrable) | BLOCKED | [ ] | Task 06, Task 10 |
| 19 | ADR and Architecture Update | BLOCKED | [ ] | Task 01, Task 02, Task 03, Task 04, Task 05 |
| 15 | Test Scenarios and Coverage Plan | BLOCKED | [ ] | Task 09, Task 10, Task 11, Task 12, Task 13, Task 14, Task 19 |
| 16 | Test Implementation | BLOCKED | [ ] | Task 15 |
| 17 | Branch Validation and Precommit | BLOCKED | [ ] | Task 16 |
| 18 | Security and Performance Review | BLOCKED | [ ] | Task 17 |
| 20 | Final PR Audit | BLOCKED | [ ] | Task 18, Task 19 |

---

## Acceptance Criteria (Branch-Level)

The branch is reviewable only when all of the following are true:

- a persisted `lemmings` table exists with:
  - `world_id`, `city_id`, `department_id`
  - `slug`, `name`, `description`, `instructions`
  - `status`
  - the four existing config buckets plus `tools_config`
- `LemmingsOs.Lemmings.Lemming` and `LemmingsOs.Lemmings` exist and follow explicit hierarchy scoping rules
- `LemmingsOs.Config.ToolsConfig` embedded schema exists
- `Config.Resolver.resolve/1` resolves effective config through `World -> City -> Department -> Lemming` including `tools_config`
- Lemming CRUD pages use real persistence and no longer depend on `LemmingsOs.MockData`
- Department Lemmings tab shows real persisted Lemming definitions
- Lemmings index page shows real persisted Lemming definitions across Departments
- Create Lemming form creates real persisted records
- Home dashboard topology card includes Lemming counts
- Import/export context functions (`export_lemming/1`, `import_lemmings/4`) work via JSON
- Import/export UI is minimal (export button + paste/upload) or deferred if costly
- Delete is guarded by `DeleteDeniedError` (safety_indeterminate in this slice)
- Tests cover:
  - schema/changeset behavior
  - context CRUD and lifecycle APIs
  - resolver merge behavior at the Lemming level
  - LiveView Lemming pages
  - import/export functions
- `mix test` passes
- `mix precommit` passes
- coverage report is generated using the repo's accepted coverage workflow
- ADR/doc updates match the implementation that actually shipped

---

## Assumptions

1. This issue follows the same "persisted domain first, honest UI second" approach used by World, City, and Department.
2. `tools_config` is introduced as a new Lemming-only config bucket; it does not propagate to World/City/Department in this issue.
3. The `lemmings` table name diverges from ADR-0021's `lemming_types`. The ADR must be updated to document this narrowing.
4. Hard deletion is unconditionally denied in this PR. No status, condition, or workaround enables it. Future issues may introduce guarded deletion once runtime signals exist, but this PR makes no promises about that behavior.
5. The existing mock Lemmings page, Create Lemming page, and Department Lemmings tab will be fully desmoked in this issue.
6. Import/export is simple JSON, not a full skill packaging or importer system.
7. The Lemming status model (`draft`, `active`, `archived`) is different from Department (`active`, `disabled`, `draining`) because Lemmings are definitions, not operational units.

---

## Risks / Open Questions

1. **ADR-0021 terminology divergence**: The spec uses `lemmings` (Department-scoped definitions) where ADR-0021 describes `lemming_types` (World-scoped definitions). This needs to be reconciled in the ADR update. The spec's choice is intentional and aligns with the "direct relationship, no type/assignment model" decision in Issue #7.

2. **`tools_config` as a Lemming-only bucket**: Adding a 5th config bucket only at the Lemming level creates an asymmetry in the config model. The resolver must handle this gracefully. Future issues may add `tools_config` to Department/City/World, at which point the resolver should merge naturally. This asymmetry should be documented.

3. **Existing mock Lemmings page structure**: The current `LemmingsLive` and `CreateLemmingLive` are fully mock-backed with runtime-oriented fields (`role`, `current_task`, `model`, `system_prompt`, `tools`). The desmoke will require significant restructuring of these pages to show definition-oriented data instead.

4. **Department's `create_lemming` scope validation**: The context's `create_lemming` function must validate that the Department belongs to the specified City and World, following the `Departments.create_department` pattern that validates `city_not_in_world`. A similar guard (`department_not_in_city_world` or equivalent) is needed.

5. **Import/export format stability**: The JSON import/export format should be documented clearly because it will be used for LLM-assisted bootstrapping. Forward compatibility (unknown keys ignored) and clear versioning are important.

6. **Router changes**: The current routes are flat (`/lemmings`, `/lemmings/new`). The desmoke may benefit from nested or parameterized routes that include Department context (e.g., `/departments?city=X&dept=Y&tab=lemmings`). The current Departments page already handles Lemming listing via the tab system, so `/lemmings` may become a cross-department overview.

---

## ADR / Doc Update Requirements

> **This is a required task, not optional.** The current architecture docs describe lemmings as runtime processes with fields like `agent_module`, `started_at`, `stopped_at`, etc. This PR ships a fundamentally different model (persisted definitions, not runtime processes). The docs must be corrected in this branch to avoid leaving misleading documentation in the codebase.

This issue **must** update the relevant ADRs and architecture docs in the same branch.

Those updates must:

- correct the existing runtime-process description of lemmings to reflect the definition-first model shipped in this PR
- explain why `lemmings` was chosen over `lemming_types` for the table name
- clarify that `lemmings` are Department-scoped definitions, not World-scoped type definitions
- state that a future `lemming_instances` table will represent runtime executions
- **`tools_config` asymmetry (provisional)**: document that `tools_config` exists only at the Lemming level in this PR as a deliberate provisional decision; that the 4 existing buckets remain symmetric across World/City/Department; that `tools_config` is expected to propagate upward in a future issue; and that v1 carries no governance semantics (see frozen contract #9)
- list which behaviors remain deferred (runtime processes, instance execution, skill packaging)
- remove or supersede any references to `agent_module`, `started_at`, `stopped_at`, `instance_ref`, `parent_instance_id` as lemming fields — those belong to the future `lemming_instances` entity

**Required** doc targets:

- `docs/adr/0021-core-domain-schema.md` — add Lemming shipped schema section; correct runtime-process language
- `docs/adr/0020-hierarchical-configuration-model.md` — add `tools_config` and 4-level merge; governance disclaimer
- `docs/architecture.md` — correct Lemming description from runtime process to persisted definition

---

## Change Log

| Date | Task | Change | Reason |
|---|---|---|---|
| 2026-03-23 | Plan | Created expanded Lemming management plan from Issue #7 draft | PO review: validated against codebase, aligned terminology, added acceptance criteria, user stories, edge cases, and UX states |
| 2026-03-23 | Plan | `instructions` required for `active` status | Prevent activating a Lemming with no behavioral definition; nullable at DB level, guarded at context/changeset level on activation |
| 2026-03-23 | Plan | Strengthened `tools_config` provisional framing | Explicitly marked as intentional asymmetry with rationale, future propagation path, and ADR-0020 documentation obligation |
| 2026-03-23 | Plan | Hardened delete guardrail — unconditional deny | Removed future "delete allowed" scenario from acceptance; no conditional delete logic in this PR; no promises about future behavior |
| 2026-03-23 | Plan | Capped import/export UI scope | Context functions are the hard requirement; UI is minimal (export button + paste/upload) and deferrable if costly; no wizard/preview/drag-drop |
| 2026-03-23 | Plan | Capped effective config UI — read-only summary | Resolver extension is the real deliverable; detail page shows flat summary, no bucket-by-bucket editor or inherited-vs-local diff view |
| 2026-03-23 | Plan | Froze `ToolsConfig` shape — two flat list fields only | `allowed_tools` + `denied_tools` only; no per-tool overrides, approval hints, governance model, or nested structs in this PR |
| 2026-03-23 | Plan | `ToolsConfig` governance semantics disclaimer | v1 is local-only, no merge semantics defined, does not alter ADR-0012/0020 rules; merge strategy deferred to future upward propagation issue |
| 2026-03-23 | Plan | ADR/doc update marked as REQUIRED | Current docs describe lemmings as runtime processes (`agent_module`, `started_at`, etc.); must be corrected in this branch, not optional |
| 2026-03-23 | Plan | Added `schema_version` to import/export format | Export includes `"schema_version": 1`; import accepts v1 or missing, rejects unknown versions; cheap future-proofing for format stability |
