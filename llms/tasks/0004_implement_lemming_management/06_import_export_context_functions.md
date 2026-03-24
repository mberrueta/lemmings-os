# Task 06: Import/Export Context Functions

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 04
- **Blocks**: Task 14
- **Estimated Effort**: M

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for context APIs, JSON serialization, and import validation.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement `export_lemming/1` and `import_lemmings/4` context functions in `LemmingsOs.Lemmings`.

## Objective
Add JSON export and import functions to the Lemmings context. Export produces a portable JSON-serializable map from a Lemming struct. Import accepts JSON data (single object or array) and creates new Lemming records in a target Department. Both functions must handle versioning via `schema_version`.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Frozen Contract #11 (Import/Export), US-9, US-10 acceptance criteria
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (context module)
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Task 03 output (schema)
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style

## Expected Outputs

- [ ] Updated `lib/lemmings_os/lemmings.ex` - Added `export_lemming/1` and `import_lemmings/4`
- [ ] `test/lemmings_os/lemmings_import_export_test.exs` - Import/export tests

## Acceptance Criteria

### Export
- [ ] `export_lemming/1` accepts a `%Lemming{}` and returns a JSON-serializable map
- [ ] Export map includes: `schema_version`, `name`, `slug`, `description`, `instructions`, `status`, and all five config buckets as nested maps
- [ ] `schema_version` is always `1`
- [ ] Export does NOT include: `id`, `world_id`, `city_id`, `department_id`, `inserted_at`, `updated_at`
- [ ] Empty config buckets are exported as empty maps `%{}`, not `nil`
- [ ] Config bucket values are plain maps (struct metadata stripped)

### Import
- [ ] `import_lemmings/4` accepts `(world_or_world_id, city_or_city_id, department_or_department_id, json_data)`
- [ ] `json_data` can be a single map (one definition) or a list of maps (batch)
- [ ] Import creates new records via `create_lemming/4` -- does NOT update existing records
- [ ] Import sets `world_id`, `city_id`, `department_id` from the target parameters, NOT from the JSON
- [ ] Import accepts `schema_version: 1` or missing `schema_version` (forward tolerance)
- [ ] Import rejects unknown `schema_version` values (e.g., `2`) with `{:error, :unsupported_schema_version}`
- [ ] Unknown extra keys in the JSON are ignored (forward compatibility)
- [ ] Missing required fields produce per-record changeset validation errors
- [ ] Batch import returns `{:ok, [%Lemming{}]}` on full success
- [ ] Batch import returns `{:error, errors}` with per-record errors on partial failure (no partial commit -- all or nothing)
- [ ] Empty list import returns `{:ok, []}`

### Tests
- [ ] Export produces correct map shape with all expected keys
- [ ] Export excludes identity and ownership fields
- [ ] Export handles nil and empty config buckets
- [ ] Import of valid single definition creates a Lemming
- [ ] Import of valid batch creates multiple Lemmings
- [ ] Import with slug conflict returns validation error
- [ ] Import with missing required fields returns validation error
- [ ] Import with unknown `schema_version` returns error
- [ ] Import with missing `schema_version` succeeds (tolerance)
- [ ] Import with extra keys succeeds (forward compatibility)
- [ ] Import of empty array returns `{:ok, []}`
- [ ] Roundtrip: export then import produces an equivalent record

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/lemmings.ex    # Add functions here
```

### Patterns to Follow
- Use `Ecto.Multi` for batch import (all-or-nothing semantics)
- Export should strip Ecto struct metadata using `Map.from_struct/1` and select only the portable keys
- Config bucket conversion: use `Map.from_struct/1` recursively for nested embeds (CostsConfig has Budgets)
- Keep the import pipeline simple: validate schema_version -> normalize to list -> create each via Ecto.Multi

### Constraints
- Do NOT add a full skill packaging system
- Do NOT add import preview, diff, or field mapping
- Import creates records -- it does NOT merge or update existing records
- JSON encoding/decoding (Jason) is NOT the context's responsibility -- the context works with Elixir maps; the LiveView/controller handles JSON string parsing
- All-or-nothing batch semantics via `Ecto.Multi` -- no partial success

## Execution Instructions

### For the Agent
1. Read the existing context module from Task 04.
2. Add `export_lemming/1` that extracts portable fields from a Lemming struct.
3. Add `import_lemmings/4` that accepts maps (not JSON strings) and creates records.
4. Use `Ecto.Multi` for batch import to ensure all-or-nothing.
5. Handle `schema_version` validation as the first step of import.
6. Write dedicated import/export tests in a separate test file.

### For the Human Reviewer
1. Verify export excludes identity fields (`id`, `world_id`, `city_id`, `department_id`).
2. Verify import uses the target scope parameters, not values from the JSON.
3. Verify batch import is all-or-nothing.
4. Verify `schema_version` handling (accept 1 or missing, reject others).
5. Reject if JSON string parsing is added to the context (that belongs in the web layer).

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review
*[Filled by human reviewer]*

### Review Date
[YYYY-MM-DD]

### Decision
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
