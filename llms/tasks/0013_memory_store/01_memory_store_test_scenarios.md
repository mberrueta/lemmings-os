# Task 01: Memory Store Test Scenarios

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, and regressions.

## Agent Invocation
Act as `qa-test-scenarios`. Convert `llms/tasks/0013_memory_store/plan.md` into a concrete scenario matrix before implementation starts.

## Objective
Define the minimum complete scenario matrix for memory data model rules, scope inheritance, `knowledge.store`, chat notification behavior, event safety, and Knowledge UI flows.

## Inputs Required
- [x] `llms/tasks/0013_memory_store/plan.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] Existing Secret Bank, Connections, and Tools Runtime tests for pattern alignment

## Expected Outputs
- [x] Risk-ranked scenario matrix with IDs and test layers (unit/integration/LiveView/manual).
- [x] Traceability from FR/AC items in `plan.md` to scenario IDs.
- [x] Explicit regression checklist for scope boundaries and leak prevention.

## Acceptance Criteria
- [x] Scenarios cover all AC-1 through AC-10 in `plan.md`.
- [x] Department listing scenarios include inherited World/City memories plus local Lemming memories.
- [x] `knowledge.store` invalid input and invalid scope paths are fully covered.
- [x] Notification resilience scenarios verify memory persistence is not rolled back on publish failure.
- [x] Scenario plan is implementation-ready for Tasks 09 and 10.

## Scope & Assumptions
- This task defines what to test; it does not add/modify production code.
- Memory scope is constrained to existing persisted hierarchy: `world_id`, `city_id`, `department_id`, `lemming_id`.
- `knowledge.store` is memory-only in this ticket and must reject file/reference semantics.
- Event and notification verification emphasizes safe metadata and resilience, not durable audit-row persistence.
- LiveView tests should use stable selectors/DOM IDs and avoid full-page raw HTML assertions.
- Pagination is local Ecto query behavior with stable ordering, default page size 25, `limit/offset/count` patterns.

## Risk Areas
- Scope boundary escape across world/city/department/lemming ancestry.
- Department effective-list correctness, including inherited parent memories and local lemming memories.
- `knowledge.store` input drift: unsupported fields, invalid scope paths, missing required fields.
- Notification coupling: memory persistence incorrectly rolled back on publish failure.
- Event leakage of memory content, secrets, runtime internals, or unsafe paths.
- UI ambiguity about owning scope vs inherited scope.

## P0/P1/P2 Coverage Recommendations

| Subsystem | Priority | Recommendation |
|---|---|---|
| Memory model and changesets | P0 | Validate required fields, defaults, memory-only constraints, artifact nullability, source/status constraints. |
| Scope guards and effective listing | P0 | Validate cross-world/sibling isolation and department effective scope composition with stable pagination/search. |
| `knowledge.store` runtime tool path | P0 | Validate happy path, scope defaulting, strict rejection matrix, safe error envelope, and no side effects on reject. |
| Notification resilience | P0 | Validate stored memory survives publish failures and tool call still reports store success. |
| Event safety/observability | P1 | Validate expected lifecycle events are emitted with safe metadata only. |
| Knowledge LiveView flows | P1 | Validate create/edit/delete/list/filter/pagination flows with stable selectors and scope indicators. |
| Manual UX checks | P2 | Validate readability/clarity of inherited indicators and deep-link ergonomics. |

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| MEM-SCH-001 | P0 | Unit | Schema | Memory changeset requires title/content and scope ancestry root | Base attrs without title/content or missing world | Build changeset permutations | Invalid attrs rejected with field errors | AC-1, AC-2 |
| MEM-SCH-002 | P0 | Unit | Schema | Memory defaults are runtime-owned | Minimal valid attrs | Insert memory through context | `status=active`, internal kind/category defaults to memory, `artifact_id=nil` | AC-1 |
| MEM-SCH-003 | P0 | Unit | Schema | Source validation accepts only `user`/`llm` | Invalid source input | Attempt insert/update with unsupported source | Rejected with safe validation error | AC-1, AC-8 |
| MEM-SCH-004 | P1 | Unit | Schema | Tags are lightweight string list | Valid/invalid tag payloads | Cast and validate tags | String-list accepted; unsafe/non-string payload rejected | FR-1 |
| MEM-SCP-001 | P0 | Integration | Scope | Cross-world list access blocked | Memories in two worlds | Query/list from world A for world B scope | World B memories hidden/rejected | AC-5 |
| MEM-SCP-002 | P0 | Integration | Scope | Sibling city access blocked | Two cities under one world | List/edit/delete sibling city memory | Action hidden or rejected safely | AC-5 |
| MEM-SCP-003 | P0 | Integration | Scope | Sibling department access blocked | Two departments in one city | List/edit/delete sibling dept memory | Action hidden or rejected safely | AC-5 |
| MEM-LIST-001 | P0 | Integration | Listing | Department effective list merges inherited + owned + lemming memories | World/city/department + lemming-scoped memories seeded | List department knowledge | Includes world+city+department+department lemmings only | AC-6 |
| MEM-LIST-002 | P0 | Integration | Listing | Department list excludes lemming memories from other departments | Lemming memories in unrelated department | List department knowledge | Unrelated lemming memories absent | AC-5, AC-6 |
| MEM-LIST-003 | P1 | Integration | Listing | Lemming page shows own + inherited parent memories | Lemming has own + parent scoped memories | List lemming knowledge | Own and inherited parent entries appear; siblings absent | FR-5 |
| MEM-LIST-004 | P1 | Integration | Filtering | Single text filter matches title and tags | Seed sentinel titles/tags | Query by title fragment and tag fragment | Matching rows returned only | FR-5, FR-6 |
| MEM-LIST-005 | P1 | Integration | Filtering | Source/status filters compose with text query | Mixed source/status data | Apply source/status + text filters | Intersection result only | FR-6 |
| MEM-LIST-006 | P0 | Integration | Pagination | Default page size is 25 with stable ordering/count | >30 rows in same effective scope | List page 1 then page 2 | 25 on page 1; stable continuation on page 2; total count correct | AC-6 |
| MEM-CRUD-001 | P0 | Integration | CRUD | User create stores memory and emits create event | Allowed scope context | Create memory via context | Row persisted with `source=user`; create event emitted | AC-2 |
| MEM-CRUD-002 | P0 | Integration | CRUD | User edit updates title/content/tags and emits update event | Existing accessible memory | Update memory | Data updated and visible in read model/list; update event emitted | AC-3 |
| MEM-CRUD-003 | P0 | Integration | CRUD | Invalid edit returns clear validation errors | Existing memory | Submit invalid title/content | No data change; errors returned | AC-3 |
| MEM-CRUD-004 | P0 | Integration | CRUD | Hard delete removes memory and emits delete event | Existing accessible memory | Delete memory | Row removed from active listings; delete event emitted | AC-4 |
| MEM-CRUD-005 | P1 | Integration | CRUD | Delete/edit blocked outside allowed scope | Existing memory in sibling/unrelated scope | Attempt delete/edit | Safe rejection and no mutation | AC-4, AC-5 |
| MEM-TOOL-001 | P0 | Integration | Tooling | `knowledge.store` happy path persists llm memory | Runtime instance with valid hierarchy | Execute tool with title/content/tags | Memory stored with `source=llm` and safe success payload | AC-7 |
| MEM-TOOL-002 | P0 | Integration | Tooling | `knowledge.store` captures creator metadata when available | Runtime has lemming + instance ids | Execute tool | Persisted row/event include creator lemming/instance metadata | AC-7, AC-10 |
| MEM-TOOL-003 | P0 | Integration | Tooling | `knowledge.store` defaults scope to current lemming | Omitted scope input | Execute tool | Stored with current `lemming_id` ancestry | AC-7 |
| MEM-TOOL-004 | P0 | Integration | Tooling | Unsupported fields rejected (`category`, `type`, `artifact_id`, file refs) | Tool call includes unsupported attrs | Execute tool | Structured safe error; no row created | AC-8 |
| MEM-TOOL-005 | P0 | Integration | Tooling | Missing/invalid title/content/tags rejected | Invalid payload permutations | Execute tool | Structured safe error; no row created | AC-8 |
| MEM-TOOL-006 | P0 | Integration | Tooling | Invalid scope path/cross-boundary scope rejected | Tool call asks sibling dept/world scope | Execute tool | Structured safe error; no row created | AC-8 |
| MEM-TOOL-007 | P1 | Integration | Tooling | Safe error envelope contains no internals | Force known tool rejection | Inspect error payload | No DB internals, paths, stack dumps, or unrelated runtime state | AC-8, AC-10 |
| MEM-NOTIF-001 | P0 | Integration | Notification | Successful llm store publishes best-effort chat notification | Active execution chat | Execute successful `knowledge.store` | Notification message emitted with title/summary and memory path/link hint | AC-9 |
| MEM-NOTIF-002 | P0 | Integration | Notification | Publish failure does not roll back stored memory | Simulate PubSub/message publish error | Execute successful store with forced publish failure | Memory remains persisted; tool call success; failure observable in safe logs/events | AC-9 |
| MEM-NOTIF-003 | P1 | Integration | Notification | Chat unavailable/missing subscriber still preserves memory | No active chat subscriber | Execute successful store | Memory persisted; no crash; optional safe diagnostic event/log | AC-9 |
| MEM-EVT-001 | P1 | Integration | Observability | Lifecycle events emitted for user create/update/delete | Event capture enabled | Execute each CRUD operation | Expected event names emitted with identifiers and scope metadata | AC-10 |
| MEM-EVT-002 | P1 | Integration | Observability | LLM-created memory emits dedicated create-by-llm event | Event capture enabled | Execute `knowledge.store` success | LLM create event emitted with creator metadata | AC-10 |
| MEM-EVT-003 | P0 | Integration | Observability | Event payload excludes unsafe/leaky content | Sentinel values seeded in content and runtime state | Inspect emitted payload/log metadata | No secrets, full content, raw runtime state, or unsafe file paths | AC-10 |
| MEM-UI-001 | P1 | LiveView | UI | Knowledge page renders empty state + create action | No memories in scope | Load page | Empty state visible with create CTA and stable selectors | FR-2, FR-5 |
| MEM-UI-002 | P1 | LiveView | UI | Create flow adds row in list with source/scope indicators | Scoped page loaded | Submit create form | Row appears in list with expected source/scope display | AC-2, NFR-5 |
| MEM-UI-003 | P1 | LiveView | UI | Edit flow persists and re-renders updated values | Existing memory | Submit edit form | Updated title/content/tags visible and persisted | AC-3 |
| MEM-UI-004 | P1 | LiveView | UI | Delete flow removes row from list | Existing memory | Trigger delete action | Row removed from rendered list | AC-4 |
| MEM-UI-005 | P1 | LiveView | UI | Department view shows inherited and owning-scope distinctions | Mixed world/city/dept/lemming memories | Load department knowledge view | Entries display inherited/owning scope metadata clearly | AC-6, NFR-5 |
| MEM-UI-006 | P1 | LiveView | UI | Search and pagination controls are selector-stable and deterministic | >25 rows and diverse tags | Filter then paginate | Correct filtered page contents and page counts | AC-6, FR-6 |
| MEM-UI-007 | P1 | LiveView | UI | Unauthorized scope deep link denied safely | URL points to forbidden scope/memory | Navigate to deep link | Redirect/not-found behavior without data leak | AC-5 |
| MEM-MAN-001 | P2 | Manual | UX | Notification copy is clear and actionable | Feature enabled in app | Trigger llm memory store manually | User can identify what was added and navigate to memory detail | AC-9 |

## FR/AC Traceability

| Requirement | Scenario IDs |
|---|---|
| FR-1 / AC-1 | MEM-SCH-001, MEM-SCH-002, MEM-SCH-003, MEM-SCH-004 |
| FR-2 / AC-2 | MEM-CRUD-001, MEM-UI-001, MEM-UI-002 |
| FR-3 / AC-3 | MEM-CRUD-002, MEM-CRUD-003, MEM-UI-003 |
| FR-4 / AC-4 | MEM-CRUD-004, MEM-CRUD-005, MEM-UI-004 |
| FR-5 / AC-5 | MEM-SCP-001, MEM-SCP-002, MEM-SCP-003, MEM-LIST-002, MEM-UI-007 |
| FR-5 + FR-6 / AC-6 | MEM-LIST-001, MEM-LIST-004, MEM-LIST-005, MEM-LIST-006, MEM-UI-005, MEM-UI-006 |
| FR-7 / AC-7 | MEM-TOOL-001, MEM-TOOL-002, MEM-TOOL-003 |
| FR-7 / AC-8 | MEM-TOOL-004, MEM-TOOL-005, MEM-TOOL-006, MEM-TOOL-007 |
| FR-8 / AC-9 | MEM-NOTIF-001, MEM-NOTIF-002, MEM-NOTIF-003, MEM-MAN-001 |
| FR-9 / AC-10 | MEM-EVT-001, MEM-EVT-002, MEM-EVT-003 |

## Required Fixtures And Sentinel Patterns
- Hierarchy fixtures: two worlds, sibling cities, sibling departments, lemmings across departments.
- Memory fixtures: world/city/department/lemming-scoped entries with deterministic timestamps for ordering.
- Runtime fixtures: lemming instance context with tool execution hooks and injectable publish failure path.
- Sentinel content for leak checks:
  - `SENTINEL_SECRET_TOKEN_MEMORY_001`
  - `SENTINEL_ABS_PATH_/var/lib/knowledge/private`
  - `SENTINEL_RUNTIME_DUMP_{"raw":"state"}`
- Validation fixtures: unsupported tool fields, invalid scope inputs, missing required attrs.

## Regression Checklist
- [ ] Cross-world and sibling-scope access is consistently denied across list/create/edit/delete/tool paths.
- [ ] Department effective listing includes inherited world/city + department + department lemming memories only.
- [ ] Default pagination remains 25 and ordering is stable across page transitions.
- [ ] Search/filter logic matches title/tags/source/status expectations.
- [ ] `knowledge.store` rejects unsupported fields and invalid scope with safe structured errors.
- [ ] LLM store defaults to current lemming scope when scope omitted.
- [ ] Notification publish failure never rolls back a successful memory persist.
- [ ] Events/log metadata stay safe and exclude secrets/full content/runtime dumps/unsafe paths.
- [ ] LiveView tests use stable selectors and avoid brittle raw-HTML assertions.

## Out-of-scope
- Semantic search, vector indexing, chunking, extraction, file/source/reference knowledge.
- Durable audit-row implementation requirements.
- Archive/unarchive lifecycle semantics.

## Execution Summary
### Work Performed
- Converted the memory-store plan into an implementation-ready scenario matrix with risk-ranked P0/P1/P2 coverage.
- Added explicit scenario coverage for AC-1 through AC-10, including scope safety, `knowledge.store`, notification resilience, event safety, and LiveView behavior.
- Added traceability mapping from FR/AC requirements to scenario IDs.
- Added fixture/sentinel guidance to support deterministic implementation in Tasks 09 and 10.

### Outputs Created
- Updated `llms/tasks/0013_memory_store/01_memory_store_test_scenarios.md` with completed scenario planning content.

### Assumptions Made
- Knowledge UI for this ticket is one LiveView surface with scope-aware listing and deep links.
- Event assertions target safe metadata in PubSub/log/telemetry style channels, not durable audit tables.
- Notification coverage uses failure injection/stubbing rather than external infrastructure.

### Blockers
- None.

### Ready for Next Task
- [x] Yes
- [ ] No

## Human Review
*[Filled by human reviewer]*
