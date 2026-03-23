# Department Management -- Operator Guide

## Overview

Department management gives operators a persisted control-plane layer below City.
Departments now exist as real database rows scoped to a World and City, and the
operator UI exposes navigation, lifecycle actions, delete guardrails, and an
initial settings surface.

This document covers:

- what a Department is in the shipped system
- how to navigate Department list and detail views
- what the lifecycle actions do today
- how delete guardrails behave
- what the settings tab can and cannot do yet
- which areas are still mock-backed or deferred

---

## Concepts

### Department vs City

LemmingsOS uses a four-level hierarchy: World, City, Department, Lemming.

- A **City** is the runtime node and the parent scope for Departments.
- A **Department** is a persisted logical grouping inside a City.
- A Department belongs to both a `world_id` and a `city_id`.

The shipped Department model is primarily operator-facing and control-plane
oriented. It gives operators a durable place to store:

- name and slug
- administrative status
- notes and tags
- local config overrides for limits, runtime, costs, and models

It does **not** yet mean the runtime is spawning or supervising Lemmings inside
that Department.

### Administrative status

Department status is an operator-managed lifecycle field. The shipped values are:

- `active`
- `draining`
- `disabled`

These values are persisted. They are not derived from runtime health.

### Persistence scope

Department list surfaces remain explicitly scoped to a selected City. The
operator UI uses `/departments?city=<city_id>` for the list and
`/departments?city=<city_id>&dept=<department_id>` for detail.

Direct fetch-by-ID exists in the context layer, but the operator-facing flow is
still city-scoped for navigation clarity.

---

## Operator Flows

### Opening the Departments page

Navigate to `/departments`.

Behavior:

- If no Cities exist, the page shows an empty state.
- If Cities exist and no `city` query param is present, the UI defaults to the
  first City.
- The page shows a City selector, a department list for the selected City, and a
  city map panel.

### Switching City scope

Use the City selector at the top of the page.

Behavior:

- Changing the selector patches the route to `?city=<city_id>`.
- The department list and map refresh to show only Departments in that City.
- Departments from other Cities are not shown in that list surface.

### Opening Department detail

Click a Department row in the list.

Behavior:

- The route patches to `?city=<city_id>&dept=<department_id>`.
- The detail view replaces the list layout.
- The detail page has three tabs:
  - `Overview`
  - `Lemmings`
  - `Settings`

### Overview tab

The Overview tab is the default detail surface.

It shows:

- current administrative status
- parent City
- parent World
- slug
- name
- tags
- notes
- lifecycle action buttons

### Lemmings tab

The Lemmings tab is currently **mock-backed**.

What is honest today:

- the tab exists and is navigable
- it renders a preview list with a visible mock-backed banner
- preview items can link into the existing `/lemmings` route shape

What it does **not** mean:

- there is no Department-hosted Lemming runtime orchestration here yet
- the tab is not an authoritative runtime inventory
- the tab should be treated as a preview surface, not a source of truth

### Settings tab

The Settings tab exposes the initial Department settings foundation.

It is split into three areas:

1. **Effective config**
   Shows the resolved `World -> City -> Department` values currently seen by the
   shipped resolver.

2. **Local overrides**
   Shows only values explicitly persisted on the Department row. If a value is
   inherited and not locally set, the UI shows it as unavailable rather than
   pretending it is owned locally.

3. **V1 editable settings**
   The current editable fields are intentionally narrow:
   - `max_lemmings_per_department`
   - `idle_ttl_seconds`
   - `cross_city_communication`
   - `daily_tokens`

Saving the form updates the Department's local override buckets. It does not
provide per-field source tracing or explanation metadata.

---

## Lifecycle Actions

The Overview tab exposes four lifecycle buttons:

- `Activate`
- `Drain`
- `Disable`
- `Delete`

### Activate / Drain / Disable

These actions update the persisted Department `status` and keep the operator on
the same detail page.

Current shipped behavior:

- `Activate` sets status to `active`
- `Drain` sets status to `draining`
- `Disable` sets status to `disabled`

The page then re-renders the detail with the updated status badge and flash
message.

### Delete

Delete is intentionally conservative.

The shipped system does **not** claim that Department hard delete is generally
safe. Instead, it enforces two guardrails:

1. A Department that is not `disabled` cannot be deleted.
2. Even if the Department is `disabled`, delete is still denied when safe
   removal cannot be proven.

In the current implementation, operators should expect delete attempts to be
rejected unless future runtime-backed safety signals are added. The UI surfaces
the denial honestly instead of pretending delete succeeded.

This means the current delete button is best understood as:

- a guarded administrative action
- with conservative denial by default
- not a guaranteed destructive operation

---

## Creation and Editing

### Creation

Department persistence and context APIs exist, including `create_department/3`,
but the shipped operator UI does **not** currently include a Department creation
form.

Operators should treat Department creation as a control-plane capability exposed
through the domain layer today, not as a completed self-service UI flow.

### Editing

There is no general-purpose Department edit screen yet.

What can be edited in the shipped UI:

- the narrow V1 settings fields on the Settings tab
- the lifecycle `status` through the Overview action buttons

What cannot be edited through a dedicated Department form yet:

- slug
- name
- notes
- tags

---

## Known Limitations

- Department runtime supervision is not shipped yet.
- Department-hosted Lemming execution is not shipped yet.
- The Lemmings tab is mock-backed and should not be treated as authoritative.
- Delete is conservatively denied unless safety can be proven.
- The settings surface is an initial foundation, not the final Department
  configuration UX.
- The resolver returns effective values only; it does not explain which scope
  supplied each field.
- There is no Department creation UI yet.
- There is no general-purpose Department edit UI yet.

---

## Related Docs

- [docs/operator/city-management.md](city-management.md) -- City lifecycle,
  heartbeat, and multi-city operator flows
- [docs/architecture.md](../architecture.md) -- high-level architecture overview
- [docs/adr/0020-hierarchical-configuration-model.md](../adr/0020-hierarchical-configuration-model.md)
  -- configuration inheritance and deferred resolver capabilities
