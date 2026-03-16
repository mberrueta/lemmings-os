# Implement World Management

## Execution Metadata

- **Spec / Plan**: `llms/tasks/0001_implement_world_management/plan.md`
- **Created**: 2026-03-16
- **Status**: PLANNING
- **Current Task**: N/A
- **Planning Agent**: `tl-architect`

## Goal

Introduce the persisted `World` domain foundation into LemmingsOS and expose it through a read-only operator UI.

This issue is not just a UI bootstrap slice anymore. It should:

- add real persisted `World` domain foundations
- ingest bootstrap filesystem config from `default.world.yaml`
- add a lightweight cache layer for stable `World` reads
- connect bootstrap config to the persisted `World` record
- expose read-only operator views on top of persisted domain state, declared bootstrap config, and runtime checks

The UI may remain mostly read-only, but `World` should enter the system as a real domain concept rather than as an isolated YAML file loaded on demand.

## Project Context

### Current implementation

- `lib/lemmings_os_web/live/home_live.ex`
- `lib/lemmings_os_web/live/world_live.ex`
- `lib/lemmings_os_web/live/tools_live.ex`
- `lib/lemmings_os_web/live/settings_live.ex`
- `lib/lemmings_os_web/components/home_components.ex`
- `lib/lemmings_os_web/components/world_components.ex`
- `lib/lemmings_os_web/components/system_components.ex`
- `lib/lemmings_os/mock_data.ex`
- `lib/lemmings_os_web/live/mock_shell.ex`

Observed facts:

- The current shell is fully mocked through `LemmingsOs.MockData`.
- LiveViews are thin and delegate most rendering to stateless components.
- There are no domain schemas, migrations, or runtime registry modules implemented yet for Worlds, Cities, Departments, Lemmings, or Tools.
- `LemmingsOs.Application` currently starts only the repo, pubsub, telemetry, and endpoint.
- Existing LiveView coverage in this area is minimal and mostly navigation-oriented.

### ADRs that constrain this issue

- `docs/adr/0002-agent-hierarchy-model.md`
- `docs/adr/0003-world-as-isolation-boundary.md`
- `docs/adr/0012-tool-policy-authorization-model.md`
- `docs/adr/0015-runtime-cost-governance.md`
- `docs/adr/0019-llm-model-provider-execution-model.md`
- `docs/adr/0020-hierarchical-configuration-model.md`
- `docs/adr/0021-core-domain-schema.md`
- `docs/adr/0022-deployment-and-packaging-model.md`
- `docs/adr/0023-error-handling-and-degradation-model.md`
- `docs/adr/0024-observability-and-monitoring-model.md`

Planning implications:

- `World` is a hard governance boundary, not a normal CRUD record.
- ADR 0002 / 0021 / `docs/architecture.md` still describe schema-backed hierarchy entities, so this issue should move toward that model, not away from it.
- The bootstrap YAML remains important, but now as bootstrap ingestion / sync input, not as the long-term center of the feature.
- Runtime state, persisted domain state, and declared bootstrap config must stay separate in the read models.
- Degraded and unavailable states must be explicit; no fake “healthy” status.
- This plan intentionally diverges from ADR 0021 / ADR 0020 and the current high-level data model in `docs/architecture.md` by preferring scoped JSONB columns on `worlds` instead of a single `config_jsonb` column; that divergence must be updated explicitly in docs during this issue.

## Scope

### Included

- Add a real `worlds` persistence foundation
- Add a `World` schema and a `Worlds` domain boundary/context
- Introduce minimal bootstrap YAML ingestion from `default.world.yaml`
- Connect bootstrap ingestion to persisted `World` creation/update
- Build read models for `World`, `Home`, `Tools`, and `Settings`
- Replace mocked `World`, `Home`, `Tools`, and `Settings` data flows with real sources where available
- Add runtime checks, warnings, and explicit unavailable states
- Add tests for schema/context, bootstrap ingestion, read models, and LiveViews
- Review ADR/doc alignment at the end of implementation

### Explicitly excluded

- Full CRUD UI for hierarchy management
- Full persistence for `City`, `Department`, and `Lemming` in this issue unless strictly required as a follow-up dependency
- Full tool policy editing
- Full ADR-0020 resolver stack (`Config.Resolver`, `Config.Validator`, cache invalidation, full hierarchical merge semantics)
- Installer, wizard, or first-run onboarding
- Auth/admin management
- Distributed topology management
- Redesign of the existing visual shell
- Hidden mock fallbacks that make missing runtime data look real

## Source-of-Truth Model

The implementation should separate data into distinct categories and never blur them in templates.

| Category | Examples | Characteristics | UI treatment |
|---|---|---|---|
| Persisted domain state | `world.id`, `slug`, `name`, persisted status/metadata, bootstrap linkage metadata | durable, app-owned | shown as system-of-record identity |
| Bootstrap declared config | providers, limits, budgets, runtime defaults, bootstrap path, load/shape results | filesystem-authored, ingestion input | shown as declared config |
| Runtime-derived status | postgres reachability, provider check results, reload/import result, tool registry availability | ephemeral and health-oriented | shown as health/status with timestamps |
| DB operational state | counts, recent usage, queue/backlog state when available | historical or durable system state | shown only when real sources exist |

Templates should receive normalized read models, not raw YAML maps, parser exceptions, or direct runtime structs.

## Frozen Contracts

These contracts should be treated as fixed for this issue unless implementation discovers a concrete blocker.

### 1. Exact bootstrap YAML shape

The bootstrap ingestion flow should support this exact top-level shape in this issue:

```yaml
world:
  id: "world_local"
  slug: "local"
  name: "Local World"

infrastructure:
  postgres:
    url_env: "DATABASE_URL"

cities: {}

tools: {}

models:
  providers:
    ollama:
      enabled: true
      base_url: "http://127.0.0.1:11434"
      default_billing_mode: "zero_cost"
      allowed_models:
        - "llama3.2"
        - "qwen2.5:7b"
    openai:
      enabled: false
      api_key_env: "OPENAI_API_KEY"
      base_url: "https://api.openai.com/v1"
      default_billing_mode: "metered"
      allowed_models: []
  profiles:
    default:
      provider: "ollama"
      model: "qwen2.5:7b"
      fallbacks:
        - provider: "ollama"
          model: "gemma2"
        - provider: "openai"
          model: "gpt-4o-mini"

limits:
  max_cities: 1
  max_departments_per_city: 20
  max_lemmings_per_department: 50

costs:
  budgets:
    monthly_usd: 0
    daily_tokens: 1000000

runtime:
  idle_ttl_seconds: 3600
  cross_city_communication: false
```

Rules for this issue:

- `world`, `infrastructure`, `models`, `limits`, `costs`, and `runtime` are required top-level sections
- `cities` and `tools` are required placeholder sections for visibility, but remain out of scope for full implementation
- `allowed_models` stays a list of strings in this issue
- provider entries may include `enabled`, `base_url`, `api_key_env`, and `default_billing_mode`
- profile fallback chains must be preserved and visible in the UI
- unknown extra keys should produce warnings, not silent acceptance

### 2. Frozen UI status taxonomy

Use this taxonomy consistently across `Home`, `World`, `Tools`, and `Settings`:

| Status | Meaning |
|---|---|
| `ok` | source loaded or check passed with no operator action needed |
| `degraded` | partially usable, warning condition, or dependency problem with fallback/continued operation |
| `unavailable` | source or runtime data cannot currently be obtained |
| `invalid` | config exists but failed parse or shape validation |
| `unknown` | state has not yet been observed or is not yet implemented |

Rules:

- do not invent page-local alternatives for the same semantics
- pages may derive display copy from these statuses, but should not invent new categories without need
- `Tools` may still use sublabels like `registered` or `enabled`, but page-level health should map back to this taxonomy

### 3. Frozen warning structure

Warnings and validation issues should use this normalized structure:

| Field | Meaning |
|---|---|
| `severity` | `info`, `warning`, or `error` |
| `code` | stable machine-readable identifier |
| `summary` | short operator-facing title |
| `detail` | fuller explanation |
| `source` | origin such as `bootstrap_file`, `shape_validation`, `import_sync`, `runtime_check`, or `tools_snapshot` |
| `path` | config path or logical section when applicable |
| `action_hint` | concise operator guidance |

Rules:

- this structure should be used by bootstrap ingestion, shape validation, import/sync reporting, and runtime snapshot composition
- templates should render normalized issues directly rather than reverse-engineering parser output
- if a field is not applicable, omit it rather than filling placeholder text

### 4. Persisted `worlds` column shape

Recommended `worlds` table shape for this issue:

Normal columns:

- `id`
- `slug`
- `name`
- `status`
- `bootstrap_source`
- `bootstrap_path`
- `last_bootstrap_hash`
- `last_import_status`
- `last_imported_at`
- timestamps

Scoped JSONB columns:

- `limits_config`
- `runtime_config`
- `costs_config`
- `models_config`

Rules:

- use JSONB for world-level declarative configuration where future operator editing is plausible
- do not use a single giant `config` blob for the whole world payload
- do not persist `tools_config` in `worlds` in this issue
- do not persist `cities_config` in `worlds` in this issue
- runtime-derived state, tool installation state, effective tool authorization state, health checks, and full bootstrap payload dumps must not be treated as persisted world configuration
- this is an intentional departure from the current ADR/doc wording around `config_jsonb` and must be documented as such
- bootstrap linkage columns on `worlds` are for current-state operational metadata only, not import history
- if multiple bootstrap sources, repeated sync history, or audit-grade import tracking become required, they should move to a separate table rather than growing `worlds`

## Page-by-Page Breakdown

| Page | Purpose | Real data to show | Data source category | Allowed actions | Deferred / explicitly not in this issue |
|---|---|---|---|---|---|
| Home | operational overview of current World health and capacity | persisted world identity, bootstrap config health, runtime health summary, counts when real hierarchy/runtime sources exist, alerts when real sources exist | persisted domain + bootstrap config + runtime state + DB/read model | navigation only | synthetic metrics, invented counts, drill-down management workflows |
| World | read-only World contract and config health | persisted world identity, config file path, import/load status, parse/validation result, infrastructure basics, providers, allowed models, profiles, fallback chains, limits, budgets, runtime defaults, placeholder cities/tools, warnings/errors | persisted domain + bootstrap config + runtime checks | refresh status, reload/import config, inspect warnings/errors | YAML editing, policy mutation, full hierarchy CRUD |
| Tools | effective runtime capability view | runtime-known tools, description, category/risk metadata when available, registry/availability state, partial mismatch visibility when practical | runtime state + DB/read model + partial declared config references | filter, inspect state | full policy engine, install/edit workflows |
| Settings | local instance info, not governance authoring | runtime/app version, node/host info, current world config path, last import/reload status, validation summary, help links | runtime state + bootstrap config + persisted world metadata | read-only links/help | editable settings forms |

### Page-specific notes

#### Home

- This page should stop acting like a second settings summary.
- If DB/runtime hierarchy sources do not exist, do not invent cards that look authoritative.
- Prefer fewer cards with honest unavailable states over a fuller dashboard with implied precision.
- Prioritize actionable signals: healthy, degraded, blocked, bootstrap/config issues, runtime issues.

#### World

- This is still the primary deliverable of the issue.
- The page should make it obvious which values come from persisted world identity, which come from bootstrap YAML, and which come from runtime checks.
- `cities` and `tools` should remain visible as declared sections without implying full implementation.

#### Tools

- The page should reflect runtime capability first, not a decorative registry.
- In this issue, the Tools page should present runtime capability state first; policy reconciliation against future hierarchical config remains partial/deferred.

#### Settings

- The current mock form should be removed or reduced to read-only runtime information.
- World-level governance editing should not be duplicated here.

## Architecture / Implementation Approach

### 1. Introduce the persisted World domain foundation

Before desmoking pages, add the minimum real domain layer for `World`.

Expected foundation:

- `worlds` migration
- `World` schema
- `Worlds` domain boundary/context
- minimum context functions such as `get_world!/1`, `get_default_world/0`, and a bootstrap ingest/upsert function or equivalent
- schema/context tests

Recommended persistence shape:

- normal columns for identity, status, bootstrap linkage, and import metadata
- scoped JSONB columns for plausible future world-level declarative config: `limits_config`, `runtime_config`, `costs_config`, `models_config`
- no single all-purpose `config` blob
- no `tools_config` or `cities_config` persisted on `worlds` in this issue

The exact module naming can be finalized during implementation, but it should clearly represent a persisted World domain boundary, not just a bootstrap helper.

### 2. Treat bootstrap YAML as ingestion input, not final source-of-truth

Add bootstrap filesystem handling as a domain input, not as a standalone UI-only source.

Recommended responsibilities:

- resolve the effective bootstrap config path
- load YAML from disk
- validate the frozen shape
- import/sync the bootstrap identity/config into the persisted `World` record
- expose import result metadata and normalized warnings/errors

Suggested bootstrap modules:

- `LemmingsOs.WorldBootstrap.PathResolver`
- `LemmingsOs.WorldBootstrap.Loader`
- `LemmingsOs.WorldBootstrap.ShapeValidator`
- `LemmingsOs.WorldBootstrap.Importer` or `LemmingsOs.WorldBootstrap.Sync`

This keeps momentum without pretending the full ADR-0020 stack exists, while avoiding a fake domain center around raw YAML.

### 3. Build read models over persisted domain + bootstrap + runtime

Do not push raw Ecto structs, bootstrap maps, or runtime internals directly into HEEx templates.

Suggested read models:

- `WorldPageSnapshot`
- `HomeDashboardSnapshot`
- `ToolsPageSnapshot`
- `SettingsPageSnapshot`

Each snapshot should distinguish:

- persisted world identity/state
- declared bootstrap config
- runtime observed checks
- unavailable or unknown sources

### 4. Add a lightweight World cache layer

`World` data should not require full DB reads on every page load when the underlying data changes infrequently.

Recommended direction:

- add a small cache layer for `World` reads, preferably using `Cachex` if adopted in this issue
- cache stable world retrievals such as default-world lookup and page snapshot inputs
- invalidate or refresh cache entries on bootstrap import/sync and explicit refresh actions
- keep cache scope narrow to `World` domain reads; do not expand it into a general config resolver cache

The cache is an operational optimization around the persisted `World` domain. It must not become the primary source of truth.

### 5. Keep bootstrap validation and runtime health distinct

The World page needs separate result classes:

- bootstrap config validity: parse success, shape validation, missing sections, unsupported keys
- import/sync status: bootstrap successfully applied to persisted domain or not
- runtime health: postgres configured/reachable, provider checks, reload/import status

A valid YAML file can still fail import. A persisted world can still have degraded runtime checks.

### 6. Keep partial data handling strict

This issue should not force full `City` / `Department` / `Lemming` persistence just to make the dashboard look complete.

Recommended behavior:

- persisted `World` data should be fully real in this issue
- bootstrap config should be fully real in this issue
- runtime checks should be real where the runtime can answer them safely
- `Home` and `Tools` should only show higher-fidelity cards when real sources exist
- otherwise use explicit `unavailable` / `unknown` states

### 7. Preserve read-only UI semantics

Allowed interactions remain narrow:

- `WorldLive`: `reload_config`, `refresh_status`, inspect warnings/errors
- `ToolsLive`: local filtering and inspection only
- `SettingsLive`: navigation/help only
- `HomeLive`: navigation only

No CRUD pages are required in this issue.

## Incremental Execution Plan

### Phase 1. World domain foundation

- add `worlds` migration
- add persisted `World` schema and `Worlds` boundary/context
- add minimum context APIs for retrieval and bootstrap upsert/import
- add schema/context tests

### Phase 2. Bootstrap integration

- add `default.world.yaml`
- add path resolver, loader, and shape validator
- add bootstrap importer/sync into persisted `World`
- run bootstrap import during application startup as the default ingestion path for this issue
- add tests for valid, invalid, missing, and warning-producing bootstrap inputs

### Phase 3. World cache layer

- add cache support for stable `World` reads
- define invalidation/refresh behavior on bootstrap import and explicit refresh
- keep cache scope narrow and domain-centered

### Phase 4. Read models and World page

- build `WorldPageSnapshot`
- add runtime checks and import result reporting
- desmoke `WorldLive` and `WorldComponents`

### Phase 5. Supporting read-only pages

- clean up `Settings`
- build tools runtime snapshot and desmoke `Tools`
- build home dashboard snapshot and desmoke `Home`

### Phase 6. QA and review

- define test scenarios
- implement ExUnit and LiveView tests
- run branch validation and `mix precommit`
- update ADR/doc alignment, including ADR 0021, ADR 0020 references that mention `config_jsonb`, and the high-level data model in `docs/architecture.md`
- run final PR audit

## Risks / Open Questions

- The repo currently has no schema-backed hierarchy foundation at all. Even adding only `World` may expose naming or context-boundary decisions that need human confirmation.
- The YAML parser/library choice is still unresolved from app code and should be decided early.
- The exact persisted fields needed on `worlds` for bootstrap linkage are not fully settled yet. Likely candidates include `id`, `slug`, `name`, and some bootstrap metadata.
- The plan direction for `worlds` persistence is now narrower: normal identity/bootstrap/import columns plus scoped JSONB config columns. Implementation should avoid drifting back to a giant `config` blob.
- Introducing `Cachex` would add a new dependency and invalidation semantics. The task should keep the cache narrow and explicit.
- Provider reachability checks should stay cheap; avoid slow page-load probes.
- `Home` and `Tools` will still have partial data unless other hierarchy/runtime layers exist. The UI must stay honest about that.
- The chosen split JSONB design for `worlds` now intentionally conflicts with ADR 0021 / ADR 0020's current `config_jsonb` wording and with the high-level data model in `docs/architecture.md`; this issue should update those docs explicitly with rationale, alternatives considered, and why the new approach is preferred.
- Bootstrap linkage metadata on `worlds` is acceptable for this issue as current-state operational metadata, but it is not a long-term import-history model. If multiple sources or sync history are needed later, a separate table is the expected direction.

## Execution Tracking

### Overview

This execution plan introduces the real `World` domain first, then layers bootstrap ingestion, read models, and read-only operator UI on top of it. The branch should end with persisted `World` foundations, bootstrap YAML integration, desmoked pages, automated coverage, final validation, and ADR/doc review.

### Technical Summary

#### Codebase Impact

- **New files**: high, including migration, schema/context, bootstrap ingestion modules, cache layer, page snapshots, tests, and shipped YAML
- **Modified files**: moderate to high, concentrated in `lib/lemmings_os/`, `lib/lemmings_os_web/live/`, `lib/lemmings_os_web/components/`, `config/`, `priv/`, and `test/`
- **Database migrations**: Yes, `worlds`
- **External dependencies**: possibly a formal YAML parser decision and `Cachex` if adopted for the cache task

#### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Plan remains too bootstrap-centric after clarification | Medium | High | Put migration/schema/context first and treat YAML as ingestion input |
| UI looks real but still rests on fake authority for counts/usage | Medium | High | Keep fewer-card strategy and strict unavailable states |
| World context naming collides with existing architectural conventions | Medium | Medium | Resolve exact naming in early domain task and document it |
| Cache invalidation becomes sloppy and serves stale world data | Medium | Medium | Keep cache scope narrow and invalidate on import/sync and explicit refresh |
| Tests lag behind the new domain + UI work | Medium | High | Keep dedicated scenario, implementation, and validation tasks before final audit |

### Human Reviewer

- Approves each task before the next task begins
- Executes all git operations
- Reviews naming and scope decisions in the new persisted World domain
- Decides whether ADR/doc updates are warranted at the end
- Final sign-off on branch readiness

### Executing Agents

| Task | Agent | Description |
|---|---|---|
| 01 | `dev-db-performance-architect` | `worlds` migration and persistence shape |
| 02 | `dev-backend-elixir-engineer` | `World` schema and `Worlds` context |
| 03 | `dev-backend-elixir-engineer` | bootstrap YAML loader and shape validation |
| 04 | `dev-backend-elixir-engineer` | bootstrap import/sync into persisted `World` |
| 05 | `dev-backend-elixir-engineer` | World cache layer |
| 06 | `dev-backend-elixir-engineer` | world snapshot and runtime checks |
| 07 | `dev-frontend-ui-engineer` | World page desmoking |
| 08 | `dev-frontend-ui-engineer` | Settings read-only runtime page |
| 09 | `dev-backend-elixir-engineer` | Tools runtime snapshot |
| 10 | `dev-frontend-ui-engineer` | Tools page desmoking |
| 11 | `dev-backend-elixir-engineer` | Home dashboard snapshot |
| 12 | `dev-frontend-ui-engineer` | Home page desmoking |
| 13 | `qa-test-scenarios` | Test scenario and coverage plan |
| 14 | `qa-elixir-test-author` | ExUnit and LiveView tests |
| 15 | `dev-backend-elixir-engineer` | Branch validation and `mix precommit` |
| 16 | `tl-architect` | ADR and architecture update |
| 17 | `audit-pr-elixir` | Final PR audit |

### Task Sequence

| # | Task | Status | Approved | Dependencies |
|---|---|---|---|---|
| 01 | Worlds Migration | ⏳ PENDING | [ ] | None |
| 02 | World Schema and Context | 🔒 BLOCKED | [ ] | Task 01 |
| 03 | Bootstrap YAML Loader and Shape Validation | 🔒 BLOCKED | [ ] | Task 02 |
| 04 | Bootstrap Import and World Sync | 🔒 BLOCKED | [ ] | Task 03 |
| 05 | World Cache Layer | 🔒 BLOCKED | [ ] | Task 04 |
| 06 | World Snapshot and Runtime Checks | 🔒 BLOCKED | [ ] | Task 05 |
| 07 | World Page Desmoke | 🔒 BLOCKED | [ ] | Task 06 |
| 08 | Settings Read-Only Runtime Page | 🔒 BLOCKED | [ ] | Task 07 |
| 09 | Tools Runtime Snapshot | 🔒 BLOCKED | [ ] | Task 08 |
| 10 | Tools Page Desmoke | 🔒 BLOCKED | [ ] | Task 09 |
| 11 | Home Dashboard Snapshot | 🔒 BLOCKED | [ ] | Task 10 |
| 12 | Home Page Desmoke | 🔒 BLOCKED | [ ] | Task 11 |
| 13 | Test Scenarios and Coverage Plan | 🔒 BLOCKED | [ ] | Task 12 |
| 14 | Test Implementation | 🔒 BLOCKED | [ ] | Task 13 |
| 15 | Branch Validation and Precommit | 🔒 BLOCKED | [ ] | Task 14 |
| 16 | ADR and Architecture Update | 🔒 BLOCKED | [ ] | Task 15 |
| 17 | Final PR Audit | 🔒 BLOCKED | [ ] | Task 16 |

### Canonical Task File Map

This mapping is the execution source of truth for task numbering on this branch. Agents should follow the number, title, and filename together.

| # | Task | File |
|---|---|---|
| 01 | Worlds Migration | `llms/tasks/0001_implement_world_management/01_worlds_migration.md` |
| 02 | World Schema and Context | `llms/tasks/0001_implement_world_management/02_world_schema_and_context.md` |
| 03 | Bootstrap YAML Loader and Shape Validation | `llms/tasks/0001_implement_world_management/03_bootstrap_yaml_loader_and_shape_validation.md` |
| 04 | Bootstrap Import and World Sync | `llms/tasks/0001_implement_world_management/04_bootstrap_import_and_world_sync.md` |
| 05 | World Cache Layer | `llms/tasks/0001_implement_world_management/05_world_cache_layer.md` |
| 06 | World Snapshot and Runtime Checks | `llms/tasks/0001_implement_world_management/06_world_snapshot_and_runtime_checks.md` |
| 07 | World Page Desmoke | `llms/tasks/0001_implement_world_management/07_world_page_desmoke.md` |
| 08 | Settings Read-Only Runtime Page | `llms/tasks/0001_implement_world_management/08_settings_readonly_runtime_page.md` |
| 09 | Tools Runtime Snapshot | `llms/tasks/0001_implement_world_management/09_tools_runtime_snapshot.md` |
| 10 | Tools Page Desmoke | `llms/tasks/0001_implement_world_management/10_tools_page_desmoke.md` |
| 11 | Home Dashboard Snapshot | `llms/tasks/0001_implement_world_management/11_home_dashboard_snapshot.md` |
| 12 | Home Page Desmoke | `llms/tasks/0001_implement_world_management/12_home_page_desmoke.md` |
| 13 | Test Scenarios and Coverage Plan | `llms/tasks/0001_implement_world_management/13_test_scenarios.md` |
| 14 | Test Implementation | `llms/tasks/0001_implement_world_management/14_test_implementation.md` |
| 15 | Branch Validation and Precommit | `llms/tasks/0001_implement_world_management/15_branch_validation_and_precommit.md` |
| 16 | ADR and Architecture Update | `llms/tasks/0001_implement_world_management/16_adr_and_architecture_update.md` |
| 17 | Final PR Audit | `llms/tasks/0001_implement_world_management/17_final_pr_audit.md` |

### Assumptions

1. This issue should introduce persisted `World` domain foundations even if the rest of the hierarchy remains out of scope.
2. YAML/bootstrap remains an input to domain state, not the final source-of-truth center.
3. `City`, `Department`, and `Lemming` persistence can stay out of scope unless implementation uncovers a strict dependency.
4. The current shell/layout structure should be preserved while data flows are desmoked.
5. The exact `World` context/module naming may need a small implementation-time decision, but the domain boundary itself is non-optional.
6. A narrow `Cachex`-based cache for `World` reads is acceptable if invalidation stays explicit and local to this issue.
7. Bootstrap import should run at application startup in this issue, with idempotent create-or-update semantics for the persisted default world.
8. For this issue, startup import should overwrite persisted world-level declarative fields from bootstrap YAML on each boot rather than introducing file mtime heuristics or partial sync logic.
9. The bootstrap path override env var for this issue is `LEMMINGS_WORLD_BOOTSTRAP_PATH`, falling back to the shipped `priv/default.world.yaml`.

### Open Questions

1. Are the proposed `worlds` columns now sufficiently frozen for implementation, or is any additional normal column required beyond the current plan? Blocking: Task 01 / 02.
2. Should the cache store only persisted world retrievals, or also page snapshot outputs? Non-blocking, but affects Task 05 and Task 06.
3. Are bootstrap linkage fields on `worlds` sufficient as current-state metadata for this issue, with import history explicitly deferred to a future separate table if needed? Blocking: Task 01 / 02.

### Resolved Execution Decisions

- Bootstrap import runs during application startup in this issue.
- The startup path is the primary ingestion path; any later manual re-import action is secondary and should reuse the same import/sync contract.
- The bootstrap path override env var is `LEMMINGS_WORLD_BOOTSTRAP_PATH`.
- If that env var is unset, bootstrap path resolution falls back to the shipped `priv/default.world.yaml`.
- Startup import must create the persisted default `World` row if it does not exist.
- Startup import must update the persisted default `World` row if it already exists.
- This issue should prefer unconditional startup sync of persisted declarative world fields over file mtime comparison or selective merge heuristics.
- Runtime health remains a separate concern from bootstrap import result and persisted last sync status.

### ADR Update Requirement

This issue is expected to update the relevant ADRs and `docs/architecture.md` if implementation follows the scoped JSONB design on `worlds`.

Those updates should explain:

- what the previous ADR/doc wording said
- why the split-column JSONB design was chosen instead
- what was considered before
- why the new approach is better for the current system direction

### Change Log

| Date | Task | Change | Reason |
|---|---|---|---|
| 2026-03-16 | Plan | Reframed plan around persisted `World` domain foundations plus bootstrap ingestion | User clarified that `World` must enter the system for real |
