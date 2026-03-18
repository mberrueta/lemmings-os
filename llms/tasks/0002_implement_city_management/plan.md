# LemmingsOS — 0002 Implement City Management

## Execution Metadata

- Spec / Plan: `llms/tasks/0002_implement_city_management/plan.md`
- Created: `2026-03-18`
- Status: `PLANNING`
- Planning Sources:
  - `llms/constitution.md`
  - `llms/project_context.md`
  - `llms/agents/po_analyst.md`
  - `llms/tasks/0001_implement_world_management/plan.md`
  - `docs/architecture.md`
  - ADR 0002, 0003, 0017, 0020, 0021, 0022, 0023

## Goal

Introduce the first real `City` domain foundation in LemmingsOS.

The branch should end with:

- persisted `cities` rows scoped to a real persisted `World`
- a real `LemmingsOs.City` schema and `LemmingsOs.Cities` domain boundary
- startup registration of the local runtime as the first city
- heartbeat-backed liveness using `last_seen_at`
- a centralized `Config.Resolver.resolve/1` for `World -> City`
- city CRUD/read pages backed by real persistence rather than `MockData`
- a simple `docker-compose` demo showing 2 or 3 cities in the UI
- visible stale behavior when one city stops heartbeating
- ADR and architecture docs updated to match the narrowed implementation

This issue is intentionally the City equivalent of the recently completed `World`
foundation work: real persisted domain first, honest operator visibility next,
distributed systems ambition deferred.

## Project / Architecture Context

The repository already contains a real persisted `World` foundation:

- `LemmingsOs.World` persists identity, status, bootstrap linkage, and split config buckets.
- `LemmingsOs.Worlds` owns retrieval and bootstrap upsert.
- `LemmingsOs.WorldBootstrap.Importer` syncs bootstrap YAML into persistence at startup.
- `WorldPageSnapshot`, `HomeDashboardSnapshot`, and `SettingsPageSnapshot` already separate persisted state from runtime signals.

City management is still mock-backed:

- [`lib/lemmings_os_web/live/cities_live.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/cities_live.ex) reads from `LemmingsOs.MockData`.
- [`lib/lemmings_os/mock_data.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/mock_data.ex) currently invents city status, region, geometry, and agent counts.
- [`lib/lemmings_os_web/components/world_components.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/components/world_components.ex) still renders city-oriented surfaces from mock data.

That leaves the system in an inconsistent state:

- architecture and ADRs say `City` is a real runtime node
- the persisted domain stops at `World`
- the UI still implies authority with mock topology data

This issue closes that gap without expanding into full multi-node orchestration.

## Architectural Tradeoffs

This branch intentionally prefers:

- truthful partial desmoke over fake completeness
- minimal DB enforcement for ownership and identity over over-constrained schema policy
- local heartbeat presence over premature distributed coordination
- centralized resolver-based config merge over UI-local merge behavior
- startup/runtime identity attachment over automatic discovery
- simple local demo reproducibility over production-packaging completeness
- explicit deferral of secure remote attachment over premature security mechanism decisions

## ADRs / Docs That Constrain The Work

- ADR 0002: `City` is a first-class hierarchy level and a real node concept.
- ADR 0003: `World` remains the hard isolation boundary; all city APIs must stay World-scoped.
- ADR 0017: `City` is the runtime execution unit and fault boundary, but the full node membership / routing story is not required here.
- ADR 0020: configuration is hierarchical and should support `World -> City` inheritance.
- ADR 0021: `cities` is a canonical core domain entity, but its currently documented shape must be narrowed to the implementation chosen here.
- ADR 0022: minimal self-hosted deployments must stay simple; one world and one city on one host remains the default path.
- ADR 0023: degraded and unavailable states must be reported honestly, not inferred from invented data.
- [`docs/architecture.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/architecture.md) already describes `City` as an OTP node and references city health behavior.

The existing `World` implementation already refined older ADR wording around `config_jsonb`
into split scoped JSONB columns. This City issue should follow the same rigor: if implementation
narrows ADR wording, the docs must be updated explicitly in the same branch.

## Scope Included

- `cities` persistence foundation and migration
- `LemmingsOs.City` schema
- `LemmingsOs.Cities` context / domain boundary
- first-city creation during startup/bootstrap flow
- minimal city startup presence contract for the local node
- reusable `Config.Resolver.resolve/1`
- city-local override buckets:
  - `limits_config`
  - `runtime_config`
  - `costs_config`
  - `models_config`
- heartbeat-backed `last_seen_at`
- minimal city CRUD/read pages
- replacement of mock city data in the UI where City data is claimed to be real
- simple multi-city compose demo
- stale/down visibility in the UI when a city stops heartbeating
- tests, coverage report, and ADR/doc alignment
- City desmoke only requires City-backed data to become real
- existing City surfaces may temporarily keep Department/Lemming child sections visually usable through explicit mock-backed read-model adapters

## Explicitly Excluded

- automatic city discovery
- automatic remote runtime registration
- full distributed Erlang clustering or membership protocol
- world-level dispatch into a target city
- failover, migration, or rescheduling
- rich city-to-city messaging
- secure remote city onboarding and final attachment security design
- storing distributed Erlang cookies in `cities`
- final encrypted secret distribution
- full department or lemming persistence unless a direct dependency is uncovered
- Department and Lemming desmoke
- config explainability / source-trace UI
- fake topology fields such as decorative region or geometry coordinates solely to preserve mock visuals

## Frozen Contracts / Resolved Decisions

### 1. City creation model

- The first city is created together with the world/bootstrap flow.
- The first city runs where the world deployment runs.
- Additional cities may later be created manually through DB/CRUD flows.
- This issue does not require automatic discovery or automatic registration of remote runtimes.

### 2. Runtime identity

- `City` represents a BEAM runtime node.
- `node_name` is the persisted runtime identity for this issue.
- `node_name` must store the full BEAM node identity in `name@host` form, not a logical label.
- `host`, `distribution_port`, and `epmd_port` are nullable future-facing connectivity hints.
- Those hints are not authoritative liveness inputs in this issue.

### 3. Status vs liveness

- `status` is administrative / lifecycle state only.
- Recommended admin states for this issue:
  - `active`
  - `disabled`
  - `draining`
- Real-time liveness is derived from `last_seen_at`, not `status`.
- The UI should render derived liveness such as:
  - `alive`
  - `stale`
  - `unknown`

### 4. Config model

- `City` follows the same split config-bucket pattern as `World`.
- Cities persist only local overrides.
- Effective config is resolved at read time.
- Resolver logic stays centralized and out of schemas and LiveViews.

### 5. Shared config shapes

The issue statement freezes the requirement that `City` use the same config embed
shapes as `World`. The current repo still stores `World` config columns as raw
`:map` fields.

Recommended implementation rule for this issue:

- introduce shared config embed modules for the four scoped buckets
- keep the physical JSONB column layout unchanged
- adopt those shared embeds for both `World` and `City`
- do not broaden the issue into a general configuration redesign beyond those four buckets

This is the only adjacent `World` refactor that should be allowed into scope.

### 6. Demo boundary

- The compose demo must show multiple cities in the UI.
- It does not need real cross-city work dispatch.
- It does not need secure remote attachment.
- It does not need a control-plane membership protocol.
- It does need honest stale behavior when one city stops heartbeating.

## Recommended `cities` Table Shape

Recommended relational shape:

```text
cities
  id
  world_id
  slug
  name
  node_name
  host
  distribution_port
  epmd_port
  status
  last_seen_at
  limits_config
  runtime_config
  costs_config
  models_config
  inserted_at
  updated_at
```

### Required columns

- `id` - UUID / `:binary_id`
- `world_id` - FK to `worlds.id`
- `slug`
- `name`
- `node_name` - full BEAM node identity in `name@host` form
- `status`

### Optional columns

- `host`
- `distribution_port`
- `epmd_port`
- `last_seen_at`

### Config columns

- `limits_config`
- `runtime_config`
- `costs_config`
- `models_config`

Rules:

- back them with JSONB / `:map` storage, consistent with `World`
- default to empty overrides, not copied parent config
- do not introduce a single `config_jsonb` catch-all blob

### Recommended indexes / constraints

- FK index on `cities(world_id)`
- unique index on `cities(world_id, slug)`
- unique index on `cities(world_id, node_name)`
- index on `cities(world_id, status)`
- index on `cities(world_id, last_seen_at)`

Recommended migration notes:

- use `timestamps(type: :utc_datetime)`
- follow the existing `World` migration style
- treat `last_seen_at` as operational metadata, not declarative config

## Recommended `City` Schema Shape

Recommended module and context:

- schema: `LemmingsOs.City`
- context: `LemmingsOs.Cities`

Recommended schema responsibilities:

- persist durable city identity and world scoping
- persist admin state
- persist local config overrides only
- expose helper functions for admin status and derived liveness

Recommended association shape:

- `belongs_to :world, LemmingsOs.World`
- add child associations only where they materially help current read paths
- do not introduce Department or Lemming persistence as a hidden dependency

Recommended changeset rules:

- declare `@required` and `@optional`
- require `slug`, `name`, `node_name`, and `status`
- validate that `node_name` is the full BEAM node identity shape for this issue, not a shorthand label
- validate admin status inclusion
- validate uniqueness for `slug` and `node_name` per world
- keep `world_id` controlled in context functions, not trusted from form params
- keep `last_seen_at` out of operator-facing form casts

Recommended helper functions:

- `statuses/0`
- `status_options/0`
- `translate_status/1`
- `liveness/2` or equivalent helper that accepts a city and freshness threshold

## Recommended `Cities` Context Contract

The Cities context should mirror the rigor of `Worlds`:

- explicit World-scoped APIs
- `opts`-based list filters
- private `filter_query/2`
- web layer talks to the context, not the schema or repo

Recommended public API surface for this issue:

```elixir
list_cities(%World{} = world, opts \\ [])
list_cities(world_id, opts \\ [])
list_cities_query(%World{} = world, opts \\ [])
get_city!(%World{} = world, id)
fetch_city(%World{} = world, id)
get_city_by_slug(%World{} = world, slug)
create_city(%World{} = world, attrs)
update_city(%City{} = city, attrs)
delete_city(%City{} = city)
upsert_runtime_city(%World{} = world, attrs)
heartbeat_city(%City{} = city, seen_at \\ DateTime.utc_now())
stale_cities(%World{} = world, cutoff)
```

Rules:

- all public retrieval/list APIs must require explicit world scope
- failure-returning APIs should return `{:ok, data}` / `{:error, reason}`
- any multi-row or bootstrap-coupled flow should use `Ecto.Multi`
- preload `:world` where resolver or UI read models require parent config

## Recommended `Config.Resolver` Contract For This Issue

Module:

- `LemmingsOs.Config.Resolver`

Required entrypoints:

```elixir
resolve(%World{} = world)
resolve(%City{world: %World{}} = city)
```

Required behavior:

- no DB access inside the resolver
- use pattern matching by scope struct
- caller must preload parent chain before calling
- return a plain map with the effective config structs:

```elixir
%{
  limits_config: %LimitsConfig{},
  runtime_config: %RuntimeConfig{},
  costs_config: %CostsConfig{},
  models_config: %ModelsConfig{}
}
```

Merge rule for this issue:

- pure in-memory merge
- child overrides parent
- no trace or explain output
- no source metadata
- no special governance merge semantics

Architectural intent:

- resolver owns effective-config assembly
- schemas own persistence and basic validation
- read models consume resolver output
- UI must not reimplement config merge behavior

## Runtime / Heartbeat Model

This issue needs minimal runtime presence, not full distributed orchestration.

Recommended model:

1. Startup path:
   - world bootstrap sync runs first
   - persisted default world is resolved
   - local runtime upserts its city row
   - a lightweight heartbeat worker starts after the city is known

2. Identity inputs:
   - `node_name` must be explicitly resolved from runtime config / env
   - `node_name` must resolve to the full BEAM node identity in `name@host` form
   - `host`, `distribution_port`, and `epmd_port` may be captured when provided
   - do not persist the Erlang cookie

3. Heartbeat behavior:
   - update `last_seen_at` on a fixed interval
   - do not mutate `status`
   - log with `world_id` and `city_id` metadata
   - fail honestly if no world row can be resolved

4. Liveness derivation:
   - `alive` when `last_seen_at` is within the freshness threshold
   - `stale` when `last_seen_at` is older than the threshold
   - `unknown` when no heartbeat has been observed

5. Scope discipline:
   - heartbeat is only local-city presence
   - do not add remote health polling in this issue
   - do not add background jobs that reinterpret stale as `status = disabled`

Recommended implementation note:

- keep the freshness threshold simple and local to this issue
- document it in the plan and operator docs
- do not turn threshold tuning into a governance feature yet

## Docker Compose / Local Multi-City Demo Expectations

The repo currently has no root `Dockerfile` or `docker-compose.yml`, so this issue
must introduce the demo artifacts directly.

Required demo outcome:

- one world/control-plane app container
- two or three city app containers
- shared Postgres
- all cities visible in the UI
- one stopped city becomes stale in the UI after the documented threshold

Recommended demo rules:

- run the same app image in each container
- vary identity with env vars / runtime config
- ensure each container persists a distinct full BEAM `node_name` in `name@host` form
- treat the control-plane container as a city too
- share the same `worlds` and `cities` persistence
- do not require the nodes to dispatch work to each other
- do not require secure remote attachment
- do not require cluster membership automation

Recommended operator contract:

- city rows may be bootstrap-created or operator-created
- runtime nodes upsert their presence and identity against those persisted rows during startup
- city liveness comes only from each runtime node updating its own `last_seen_at`
- stopping a container demonstrates stale behavior without any fake state transition

## UI / Read Model Expectations

### General rule

The UI must stay honest. If a city surface cannot be driven from persisted data,
the mock surface should be removed or simplified rather than backfilled with fake authority.

### Cities page

Required expectations:

- real city list
- real city detail or show surface
- minimal create/edit/delete operator flows for city metadata and local overrides
- visible admin status and derived liveness rendered separately
- health / heartbeat timestamps visible enough to debug the demo
- Department and Lemming child sections do not need to be desmoked in this issue

Recommended approach:

- create city-specific read models instead of passing raw Ecto structs into HEEx
- use LiveView streams for collections
- keep forms scoped to metadata and override buckets only
- do not imply runtime attachment simply because a row exists
- if existing City subviews still need Department/Lemming content to remain usable, expose that content via explicit mock-backed adapter fields in the City read model
- keep those child collections visibly non-authoritative and easy to remove in the future Department/Lemming issues

### World page

Required expectations:

- replace city placeholders / mock-backed city summaries where the page claims to show real city data
- show real persisted cities for the current world
- show real liveness derived from `last_seen_at`
- keep effective config read paths centralized through the resolver

### Home page

Allowed expectations:

- a small city health summary when real city rows exist
- honest counts of visible cities
- degraded/unavailable presentation when runtime presence is missing

Not allowed:

- invented topology cards
- fake activity or region summaries

### Settings page

Recommended expectations:

- show local node identity
- show the current runtime city row if available
- show last heartbeat freshness as read-only diagnostics

### Visual design constraint

If the current city map depends on fake fields such as `region`, `x`, `y`, or hand-placed geometry:

- replace it with a real list/card/read-only topology summary
- do not add fake geometry columns just to preserve the mock design

If City pages still need child collections for usability before Department/Lemming persistence exists:

- shape them in a page snapshot / adapter layer rather than mutating schema structs
- keep explicit source markers such as `departments_source: :mock` or equivalent
- do not let raw `MockData` become an ad hoc LiveView-domain contract

## Incremental Implementation Phases

### Phase 1. Persistence foundation

- add `cities` migration
- add shared config embed modules backed by the existing four JSONB buckets
- update `World` to use the shared embed types if required to satisfy the frozen contract
- add `City` schema
- add `Cities` context APIs and tests

### Phase 2. Bootstrap and first-city integration

- define the local node identity contract
- integrate first-city upsert into the startup/bootstrap path
- ensure the local deployment always creates its first city alongside the world path
- keep failure handling honest when world bootstrap is unavailable

### Phase 3. Resolver and runtime presence

- add `LemmingsOs.Config.Resolver`
- add `World -> City` effective-config resolution
- add heartbeat worker and `last_seen_at` updates
- define stale/liveness derivation helpers

### Phase 4. UI desmoking

- create city read models / snapshots
- replace `MockData`-backed city surfaces
- add minimal CRUD/read pages
- update related pages to consume real city data

### Phase 5. Demo and validation

- add `Dockerfile` / compose demo artifacts
- define the local multi-city run contract
- add ExUnit and LiveView tests
- generate coverage report
- run final branch validation

### Phase 6. ADR / architecture alignment

- update ADR 0017, 0020, 0021, and 0022 as needed
- update `docs/architecture.md`
- ensure final wording matches the actual narrowed implementation

## Execution Tracking

### Overview

This execution plan adds the real City foundation the same way `World` was introduced:
persisted domain first, runtime presence second, honest UI third, docs updated in the same branch.

The branch should end with a concrete city row model, local city registration, derived liveness,
resolver-backed effective config, real city pages, a simple compose demo, and review-ready validation.

### Technical Summary

#### Codebase Impact

- **New files**: migration, `City` schema/context modules, shared config embeds, resolver, heartbeat modules, page snapshots, compose artifacts, tests, docs
- **Modified files**: application startup, world schema/config typing, LiveViews, components, translations, architecture docs, ADRs
- **Database migrations**: yes, `cities`
- **Operational artifacts**: yes, root container / compose demo files

#### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Issue drifts into distributed systems work | Medium | High | Keep startup self-registration and heartbeat local-only |
| UI keeps mock authority | Medium | High | Remove or simplify surfaces that need fake city geometry |
| Shared config typing broadens too far | Medium | Medium | Limit refactor to the four scoped buckets already frozen for World/City |
| Heartbeat tests become timing-flaky | Medium | High | Keep liveness derivation pure and test heartbeat updates deterministically |
| Compose demo becomes a release-engineering rabbit hole | Medium | Medium | Optimize for one shared image and a narrow local demo, not production packaging completeness |

### Human Reviewer

- approves each task before the next begins
- executes all git operations manually
- reviews the shared config typing decision early
- confirms the final stale-threshold/operator UX is acceptable
- signs off on ADR wording after implementation narrows the docs

### Executing Agents

| Task | Agent | Description |
|---|---|---|
| 01 | `dev-db-performance-architect` | `cities` migration and indexes |
| 02 | `dev-backend-elixir-engineer` | shared config embeds plus `City` schema |
| 03 | `dev-backend-elixir-engineer` | `Cities` context and CRUD APIs |
| 04 | `dev-backend-elixir-engineer` | first-city bootstrap/startup integration |
| 05 | `dev-backend-elixir-engineer` | `Config.Resolver` and effective config merge |
| 06 | `dev-backend-elixir-engineer` | heartbeat worker and presence model |
| 07 | `dev-frontend-ui-engineer` | city read models and `CitiesLive` desmoke |
| 08 | `dev-frontend-ui-engineer` | world/home/settings city integration |
| 09 | `dev-frontend-ui-engineer` | minimal city CRUD/read operator flows |
| 10 | `dev-backend-elixir-engineer` | compose demo and runtime env contract |
| 11 | `qa-test-scenarios` | scenario design and coverage plan |
| 12 | `qa-elixir-test-author` | ExUnit and LiveView tests |
| 13 | `audit-pr-elixir` | security and performance review |
| 14 | `tl-architect` | ADR and architecture updates |
| 15 | `docs-feature-documentation-author` | demo runbook / operator docs |
| 16 | `dev-backend-elixir-engineer` | branch validation, `mix test`, `mix precommit`, and the repo-accepted coverage workflow |
| 17 | `audit-pr-elixir` | final PR audit |

### Task Sequence

| # | Task | Status | Approved | Dependencies |
|---|---|---|---|---|
| 01 | Cities Migration and Indexes | ⏳ PENDING | [ ] | None |
| 02 | Shared Config Embeds and City Schema | 🔒 BLOCKED | [ ] | Task 01 |
| 03 | Cities Context and CRUD APIs | 🔒 BLOCKED | [ ] | Task 02 |
| 04 | First-City Bootstrap and Startup Integration | 🔒 BLOCKED | [ ] | Task 03 |
| 05 | Config Resolver and Effective Config Merge | 🔒 BLOCKED | [ ] | Task 02 |
| 06 | Heartbeat Worker and Presence Model | 🔒 BLOCKED | [ ] | Task 04 |
| 07 | City Read Models and `CitiesLive` Desmoke | 🔒 BLOCKED | [ ] | Task 03, Task 05, Task 06 |
| 08 | World / Home / Settings City Integration | 🔒 BLOCKED | [ ] | Task 06, Task 07 |
| 09 | Minimal City CRUD / Read Operator Flows | 🔒 BLOCKED | [ ] | Task 07 |
| 10 | Docker Compose Multi-City Demo | 🔒 BLOCKED | [ ] | Task 04, Task 06 |
| 11 | Test Scenarios and Coverage Plan | 🔒 BLOCKED | [ ] | Task 07, Task 08, Task 09, Task 10 |
| 12 | Test Implementation | 🔒 BLOCKED | [ ] | Task 11 |
| 13 | Security and Performance Review | 🔒 BLOCKED | [ ] | Task 12 |
| 14 | ADR and Architecture Update | 🔒 BLOCKED | [ ] | Task 13 |
| 15 | Demo Runbook and Operator Docs | 🔒 BLOCKED | [ ] | Task 14 |
| 16 | Branch Validation and Precommit | 🔒 BLOCKED | [ ] | Task 15 |
| 17 | Final PR Audit | 🔒 BLOCKED | [ ] | Task 16 |

### Canonical Task File Map

| # | Task | File |
|---|---|---|
| 01 | Cities Migration and Indexes | `llms/tasks/0002_implement_city_management/01_cities_migration_and_indexes.md` |
| 02 | Shared Config Embeds and City Schema | `llms/tasks/0002_implement_city_management/02_shared_config_embeds_and_city_schema.md` |
| 03 | Cities Context and CRUD APIs | `llms/tasks/0002_implement_city_management/03_cities_context_and_crud_apis.md` |
| 04 | First-City Bootstrap and Startup Integration | `llms/tasks/0002_implement_city_management/04_first_city_bootstrap_and_startup_integration.md` |
| 05 | Config Resolver and Effective Config Merge | `llms/tasks/0002_implement_city_management/05_config_resolver_and_effective_config_merge.md` |
| 06 | Heartbeat Worker and Presence Model | `llms/tasks/0002_implement_city_management/06_heartbeat_worker_and_presence_model.md` |
| 07 | City Read Models and CitiesLive Desmoke | `llms/tasks/0002_implement_city_management/07_city_read_models_and_cities_live_desmoke.md` |
| 08 | World Home Settings City Integration | `llms/tasks/0002_implement_city_management/08_world_home_settings_city_integration.md` |
| 09 | Minimal City CRUD Read Operator Flows | `llms/tasks/0002_implement_city_management/09_minimal_city_crud_read_operator_flows.md` |
| 10 | Docker Compose Multi-City Demo | `llms/tasks/0002_implement_city_management/10_docker_compose_multi_city_demo.md` |
| 11 | Test Scenarios and Coverage Plan | `llms/tasks/0002_implement_city_management/11_test_scenarios_and_coverage_plan.md` |
| 12 | Test Implementation | `llms/tasks/0002_implement_city_management/12_test_implementation.md` |
| 13 | Security and Performance Review | `llms/tasks/0002_implement_city_management/13_security_and_performance_review.md` |
| 14 | ADR and Architecture Update | `llms/tasks/0002_implement_city_management/14_adr_and_architecture_update.md` |
| 15 | Demo Runbook and Operator Docs | `llms/tasks/0002_implement_city_management/15_demo_runbook_and_operator_docs.md` |
| 16 | Branch Validation and Precommit | `llms/tasks/0002_implement_city_management/16_branch_validation_and_precommit.md` |
| 17 | Final PR Audit | `llms/tasks/0002_implement_city_management/17_final_pr_audit.md` |

## Acceptance Criteria

The branch is reviewable only when all of the following are true:

- a persisted `cities` table exists with:
  - `world_id`
  - `slug`
  - `name`
  - `node_name`
  - `host`
  - `distribution_port`
  - `epmd_port`
  - `status`
  - `last_seen_at`
  - the four scoped config buckets
- `LemmingsOs.City` and `LemmingsOs.Cities` exist and follow explicit World scoping rules
- the first city is created or updated during the same startup path that bootstraps the default world
- `Config.Resolver.resolve/1` exists and resolves effective `World -> City` config with no DB access
- city liveness shown in the UI is derived from `last_seen_at`, not `status`
- city CRUD/read pages use real persistence and no longer depend on `LemmingsOs.MockData`
- `WorldLive`, `HomeLive`, and `SettingsLive` no longer imply real city authority from mock data
- the multi-city compose demo starts one world/control-plane app and two or three city nodes against a shared Postgres instance
- stopping one city makes its liveness become stale in the UI within the documented threshold
- tests cover:
  - schema/context behavior
  - resolver merge behavior
  - startup first-city registration
  - heartbeat/liveness derivation
  - LiveView city pages
- security/performance review explicitly covers:
  - N+1 and preload/query-shape risk
  - runtime env and secret handling
  - logging/metadata safety
  - runtime exposure introduced by compose/demo wiring
- `mix test` passes
- `mix precommit` passes
- coverage report is generated using the repo's accepted coverage workflow
- ADR/doc updates match the implementation that actually shipped

## Assumptions

1. This issue may include a narrow shared-config typing refactor on `World` in order to satisfy the frozen World/City shared embed contract.
2. The local runtime can determine a stable `node_name` from explicit runtime configuration or environment.
3. The compose demo is a reference local deployment flow, not the final production packaging story.
4. The current mock city map can be simplified or removed if persisted city data cannot drive it honestly.
5. Full secure remote attachment remains a future issue and must not block local multi-city visibility.

## Risks / Open Questions

1. The repo currently persists `World` config buckets as raw maps. Recommended path: convert both `World` and `City` to shared embed modules backed by the same JSONB columns. If reviewers do not want that adjacent refactor, City cannot fully satisfy the frozen “same embedded schemas” requirement as written.
2. The exact runtime env contract for `node_name` should be finalized early. The implementation should prefer one explicit contract rather than mixing multiple fallback identities across dev and compose.
   Recommended direction: one explicit env-driven full BEAM node identity in `name@host` form.
3. Delete semantics for cities need guardrails. Recommended path: allow minimal admin deletion only where it does not break the demo or orphan future dependent rows.
4. The compose demo needs new container artifacts. Keep that work intentionally narrow so the issue does not become a release-engineering branch.
5. If reviewers insist on preserving the current map visualization, they must accept that it will need a truthful persisted data model. The recommended plan is to simplify the visualization instead.

## Resolved Execution Decisions

- The first city is created during startup/bootstrap on the same deployment that hosts the world.
- City heartbeat is local-only and updates `last_seen_at`.
- Admin `status` and derived liveness stay separate.
- Resolver merge semantics are child-overrides-parent only for this issue.
- City config persists local overrides only.
- The compose demo proves visibility and stale detection, not orchestration.
- City desmoke does not require Department or Lemming desmoke.
- Secure remote node onboarding and encrypted secret distribution remain out of scope.

## ADR / Doc Update Requirements

This issue is expected to update the relevant ADRs and architecture docs in the same branch.

Those updates should explain:

- what the prior ADR wording implied
- what the City implementation actually ships now
- which behaviors remain deferred
- why those deferred behaviors are intentionally not blockers for City persistence and visibility
- that secure remote city attachment and secret distribution remain deferred to a later ADR / security design
- optionally, that future attachment may require persisted encrypted secret material, but that mechanism is not decided in this issue

Minimum doc targets:

- [`docs/architecture.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/architecture.md)
- [`docs/adr/0017-runtime-topology-city-execution-model.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/adr/0017-runtime-topology-city-execution-model.md)
- [`docs/adr/0020-hierarchical-configuration-model.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/adr/0020-hierarchical-configuration-model.md)
- [`docs/adr/0021-core-domain-schema.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/adr/0021-core-domain-schema.md)
- [`docs/adr/0022-deployment-and-packaging-model.md`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/docs/adr/0022-deployment-and-packaging-model.md)

## Change Log

| Date | Task | Change | Reason |
|---|---|---|---|
| 2026-03-18 | Plan | Created initial City management execution plan | Introduce persisted City foundation with minimal multi-city runtime visibility |
