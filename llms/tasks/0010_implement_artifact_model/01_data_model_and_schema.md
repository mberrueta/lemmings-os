# Task 01: Data Model and Schema

## Status
- **Status**: ⏳ COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for schema design, indexes, migrations, and query performance.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement only the durable Artifact data model and schema foundation.

## Objective
Add the `artifacts` table, `LemmingsOs.Artifacts.Artifact` schema, changeset validations, associations, factory support, and focused schema/migration tests.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Existing schemas under `lib/lemmings_os/**`
- [ ] Existing migrations under `priv/repo/migrations/`
- [ ] `test/support/factory.ex`

## Expected Outputs
- [ ] Migration creating `artifacts` with required fields, nullable provenance, timestamps, and explicit indexes for scope, provenance, and update lookup.
- [ ] `LemmingsOs.Artifacts.Artifact` schema with `@required`, `@optional`, `changeset/2`, allowed type/status validation, metadata default, metadata contract validation, and associations.
- [ ] Factory support for valid Artifact test data.
- [ ] Focused tests for required fields, allowed `type`, allowed `status`, metadata default, metadata contract validation, and scope shape validation.

## Acceptance Criteria
- [ ] `world_id`, `filename`, `type`, `content_type`, `storage_ref`, `size_bytes`, `checksum`, `status`, and `metadata` are validated.
- [ ] `metadata` is not used as arbitrary free-form tool output.
- [ ] `metadata` is validated through a small embedded/schema-like contract.
- [ ] Initial allowed metadata may be limited to `source: "manual_promotion"`.
- [ ] `metadata` must not contain raw prompts, model output, tool output, file contents, debug dumps, or secrets.
- [ ] `type` accepts only `markdown | pdf | json | csv | email | html | image | text | other`.
- [ ] `status` accepts only `ready | archived | deleted | error`.
- [ ] Provenance FKs to instance/tool execution nilify on delete; owning hierarchy uses the safest behavior consistent with the source plan.
- [ ] Add an index on `world_id`.
- [ ] Add an index on `(world_id, city_id, department_id)`.
- [ ] Add an index on `lemming_instance_id`.
- [ ] Add an index on `created_by_tool_execution_id`.
- [ ] Add a non-unique update lookup index on `(world_id, city_id, department_id, lemming_id, filename)`.
- [ ] Do not make the filename lookup index unique because `Promote as New Artifact` must remain possible.
- [ ] No DB enums are introduced.
- [ ] Validation messages use `dgettext("errors", ...)`.
- [ ] Tests pass with the narrowest relevant command.

## Technical Notes
### Relevant Code Locations
```
priv/repo/migrations/                 # Migration patterns
test/support/factory.ex               # Factory patterns
lib/lemmings_os/lemming_instances/    # Existing instance/tool associations
lib/lemmings_os/events/               # Existing generic event schema style
```

### Constraints
- Do not implement storage copying, context APIs, download routes, or UI in this task.
- Do not add dependencies.
- Do not use map access syntax on structs.
- Do not add Secret Bank access.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Create the migration and schema with tests.
3. Keep the changes narrowly scoped to persistence/schema/factory.
4. Run the narrowest relevant tests for the schema/migration changes.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Review migration rollback risk and FK behavior.
2. Verify scope/provenance fields match the source plan.
3. Confirm tests cover schema validation, metadata default, and metadata contract rejection cases.
4. If approved: mark `[x]` on Approved.

---

## Execution Summary
*[Filled by executing agent after completion]*
