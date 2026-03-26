# Task 02: Runtime Schemas and Context

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Ecto schemas, changesets, and domain modeling.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.LemmingInstance` schema, the `LemmingsOs.LemmingInstances.Message` schema, and the `LemmingsOs.LemmingInstances` context with status transitions, durable spawn persistence, and transcript persistence.

## Objective
Create the runtime domain layer at:

- `lib/lemmings_os/lemming_instances/lemming_instance.ex`
- `lib/lemmings_os/lemming_instances/message.ex`
- `lib/lemmings_os/lemming_instances.ex`

These modules own the runtime execution record, immutable transcript entries, and the context APIs that create instances, persist user messages, enqueue follow-up work through a public domain API, list runtime data, and update instance status. They do not own web-triggered runtime orchestration such as starting executors or waking schedulers.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #2, #3, #4, #12 and Terminology Alignment
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Schema and context pattern precedent
- [ ] `lib/lemmings_os/config/resolver.ex` - Config resolution for spawn-time snapshot
- [ ] Task 01 output (migration files) - Confirms column names and types

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/lemming_instance.ex`
- [ ] `lib/lemmings_os/lemming_instances/message.ex`
- [ ] `lib/lemmings_os/lemming_instances.ex`

## Acceptance Criteria

### `LemmingInstance` schema
- [ ] `@primary_key {:id, :binary_id, autogenerate: true}`
- [ ] `@foreign_key_type :binary_id`
- [ ] `belongs_to :lemming, LemmingsOs.Lemmings.Lemming`
- [ ] `belongs_to :world, LemmingsOs.Worlds.World`
- [ ] `belongs_to :city, LemmingsOs.Cities.City`
- [ ] `belongs_to :department, LemmingsOs.Departments.Department`
- [ ] `has_many :messages, LemmingsOs.LemmingInstances.Message`
- [ ] `field :status, :string, default: "created"`
- [ ] `field :config_snapshot, :map`
- [ ] `field :started_at, :utc_datetime`
- [ ] `field :stopped_at, :utc_datetime`
- [ ] `field :last_activity_at, :utc_datetime`
- [ ] `timestamps(type: :utc_datetime)`
- [ ] There is NO `initial_request` field
- [ ] `@statuses ~w(created queued processing retrying idle failed expired)`
- [ ] `create_changeset/2` requires `lemming_id`, `world_id`, `city_id`, `department_id`, `config_snapshot`
- [ ] `status_changeset/2` casts `status`, `started_at`, `stopped_at`, `last_activity_at`

### `Message` schema
- [ ] `@primary_key {:id, :binary_id, autogenerate: true}`
- [ ] `@foreign_key_type :binary_id`
- [ ] `belongs_to :lemming_instance, LemmingsOs.LemmingInstances.LemmingInstance`
- [ ] `belongs_to :world, LemmingsOs.Worlds.World`
- [ ] `field :role, :string` with values `"user"` and `"assistant"`
- [ ] `field :content, :string`
- [ ] `field :provider, :string`
- [ ] `field :model, :string`
- [ ] `field :input_tokens, :integer`
- [ ] `field :output_tokens, :integer`
- [ ] `field :total_tokens, :integer`
- [ ] `field :usage, :map`
- [ ] `timestamps(type: :utc_datetime, updated_at: false)`
- [ ] `@roles ~w(user assistant)`
- [ ] `changeset/2` requires `lemming_instance_id`, `world_id`, `role`, `content`

### `LemmingInstances` context
- [ ] `spawn_instance(lemming, first_request_text, opts \\ [])`
- [ ] `list_instances(scope, opts \\ [])`
- [ ] `get_instance(id, opts \\ [])`
- [ ] `update_status(instance, status, attrs \\ %{})`
- [ ] `enqueue_work(instance, request_text, opts \\ [])`
- [ ] `list_messages(instance, opts \\ [])`
- [ ] `topology_summary(world_or_world_id)`
- [ ] `spawn_instance/3` creates the instance record and first `Message` atomically
- [ ] `spawn_instance/3` returns `{:ok, instance}` or `{:error, changeset | reason}`
- [ ] The first user request is persisted only as the first `Message`
- [ ] All public APIs are World-scoped
- [ ] `filter_query/2` uses multi-clause pattern matching for scope filters
- [ ] `get_instance/2` returns `{:ok, instance}` or `{:error, :not_found}`
- [ ] `list_instances/2` orders by `inserted_at desc`
- [ ] `list_instances/2` is read-only and returns a list of instances
- [ ] `list_messages/2` orders by `inserted_at asc`
- [ ] `list_messages/2` is read-only and returns a chronological list of messages
- [ ] `spawn_instance/3` validates the lemming is `"active"`
- [ ] `spawn_instance/3` snapshots resolved config via `Config.Resolver`
- [ ] `spawn_instance/3` is a persistence/domain function only; runtime orchestration is delegated to a higher-level runtime service
- [ ] `update_status/3` is the single generic public status mutation API; no status-specific wrapper methods are introduced
- [ ] `update_status/3` returns `{:ok, instance}` or `{:error, changeset | reason}`
- [ ] `enqueue_work/3` is the public API used by follow-up input flows to add new work to an existing instance
- [ ] `enqueue_work/3` persists the follow-up user request as a `Message` with `role = "user"`
- [ ] `enqueue_work/3` accepts work for non-terminal instances and rejects terminal instances (`failed`, `expired`)
- [ ] `enqueue_work/3` returns `{:ok, instance}` or `{:error, reason}`
- [ ] `enqueue_work/3` may hand work off to the runtime layer, but it does not directly start executors or notify schedulers itself
- [ ] `update_status/3` updates temporal markers but does not enforce transitions in v1
- [ ] `topology_summary/1` is read-only and returns topology data for the requested World

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/lemmings.ex                  # Context pattern precedent
lib/lemmings_os/config/resolver.ex           # Config resolution
lib/lemmings_os/lemmings/lemming.ex          # Lemming schema pattern
```

### Patterns to Follow
- Mirror `LemmingsOs.Lemmings` structure for the context
- Mirror the existing `Lemming` schema module pattern for both schemas
- Use `Ecto.Multi` for `spawn_instance/3`
- Use `Gettext`, `Ecto.Schema`, and `Ecto.Changeset` consistently
- Expose `statuses/0` and `roles/0` for external consumers

### Constraints
- The first user request is never stored on `LemmingInstance`
- `config_snapshot` is a plain `:map`
- `usage` is a plain `:map`
- No virtual runtime state fields belong in the schemas
- No update changeset is required for `Message`
- Public APIs must avoid bang (`!`) variants and use explicit result contracts instead
- Do not introduce duplicate `get_*` and `fetch_*` variants with overlapping meaning
- Do not introduce redundant public wrappers whose only purpose is to restate a target status or generic mutation
- `enqueue_work/3` is a public context API, but direct runtime orchestration remains outside `LemmingsOs.LemmingInstances`
- Do not start executors or notify schedulers from `LemmingsOs.LemmingInstances`

## Execution Instructions

### For the Agent
1. Read the Lemming schema and context for exact module structure.
2. Create the three runtime domain files listed above.
3. Implement the schema fields, changesets, and context APIs from the acceptance criteria.
4. Verify the first request is persisted only as a `Message`.
5. Add `@doc` and `@spec` to public functions where appropriate.

### For the Human Reviewer
1. Confirm the schema fields match the migration contracts.
2. Confirm `spawn_instance/3` creates both the instance and first message atomically.
3. Confirm no `initial_request` field exists anywhere in the runtime domain layer.
4. Confirm world scoping is explicit on public context functions.
5. Confirm the status taxonomy and role values are exactly the v1 sets.

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
