# Task 20: Factory Additions

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Elixir/Phoenix.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and add `:lemming_instance` and `:lemming_instance_message` factories to `test/support/factory.ex`.

## Objective
Add two new ExMachina factories to the project's `LemmingsOs.Factory` module: `:lemming_instance` for creating `LemmingInstance` records and `:lemming_instance_message` for creating `Message` records. These factories are prerequisites for all test tasks (Task 18, Task 19).

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/coding_styles/elixir_tests.md` - Test coding style (factory conventions)
- [ ] `test/support/factory.ex` - Existing factory file with world, city, department, lemming factories
- [ ] Task 02 outputs (`lemming_instance.ex`, `message.ex`, `lemming_instances.ex`) - Schema fields, required attrs, role values, context associations

## Expected Outputs

- [ ] Modified `test/support/factory.ex` - Added `lemming_instance_factory/0` and `lemming_instance_message_factory/0`

## Acceptance Criteria

### `:lemming_instance` Factory
- [ ] Builds a `LemmingsOs.LemmingInstances.LemmingInstance` struct
- [ ] Auto-builds parent `:lemming` (which cascades to department, city, world)
- [ ] Sets `world`, `city`, `department` from the built lemming's associations (same hierarchy)
- [ ] Sets `status` to `"created"` (default)
- [ ] Sets `config_snapshot` to a valid JSON-serializable map (e.g., `%{"models" => %{}, "runtime" => %{}}`)
- [ ] Leaves `started_at`, `stopped_at`, `last_activity_at` as `nil` (matching the `created` status semantics)
- [ ] Does NOT include an `initial_request` field (no such column exists)

### `:lemming_instance_message` Factory
- [ ] Builds a `LemmingsOs.LemmingInstances.Message` struct
- [ ] Auto-builds parent `:lemming_instance` (which cascades to lemming, department, city, world)
- [ ] Sets `world` from the built instance's world association
- [ ] Sets `role` to `"user"` (default; overridable)
- [ ] Sets `content` to a Faker-generated sentence
- [ ] Leaves `provider`, `model`, `input_tokens`, `output_tokens` as `nil` for user messages
- [ ] Leaves `total_tokens` as `nil` (nullable integer)
- [ ] Leaves `usage` as `nil` (nullable jsonb)
- [ ] For assistant messages, tests can override: `role: "assistant"`, `provider: "ollama"`, `model: "llama3.2"`, `input_tokens: 100`, `output_tokens: 50`, `total_tokens: 150`, `usage: %{"eval_duration" => 123}`

### Alias and Import
- [ ] Adds `alias LemmingsOs.LemmingInstances.LemmingInstance` to the module
- [ ] Adds `alias LemmingsOs.LemmingInstances.Message` to the module (or uses full path in factory)

### Consistency
- [ ] Factory pattern matches existing factories (`:world`, `:city`, `:department`, `:lemming`)
- [ ] Uses `build/1` for associations (not `insert/1`) -- ExMachina handles insertion
- [ ] Uses `sequence/2` where uniqueness is needed

## Technical Notes

### Relevant Code Locations
```
test/support/factory.ex    # File to modify
lib/lemmings_os/lemming_instances/lemming_instance.ex  # Task 02 output (schema)
lib/lemmings_os/lemming_instances/message.ex           # Task 02 output (schema)
```

### Existing Pattern to Follow
The `:lemming` factory demonstrates the cascade pattern:
```elixir
def lemming_factory do
  department = build(:department)
  %Lemming{
    world: department.world,
    city: department.city,
    department: department,
    ...
  }
end
```

The `:lemming_instance` factory should follow the same pattern:
```elixir
def lemming_instance_factory do
  lemming = build(:lemming)
  %LemmingInstance{
    world: lemming.world,
    city: lemming.city,
    department: lemming.department,
    lemming: lemming,
    status: "created",
    config_snapshot: %{"models" => %{}, "runtime" => %{}},
    ...
  }
end
```

### Constraints
- Do not add any field that does not exist on the schema (no `initial_request`)
- `config_snapshot` must be a map (not a string) -- Ecto handles JSON serialization
- Factories must work with both `build/1` (in-memory) and `insert/1` (persisted)

## Execution Instructions

### For the Agent
1. Read `test/support/factory.ex` to understand existing patterns.
2. Read Task 02 runtime domain outputs for field names and types.
3. Add aliases for the new schemas.
4. Add `lemming_instance_factory/0` following the cascade pattern.
5. Add `lemming_instance_message_factory/0` following the cascade pattern.
6. Verify factories compile (request human to run `mix compile`).

### For the Human Reviewer
1. Verify factory fields match schema fields exactly.
2. Verify no `initial_request` field on the instance factory.
3. Verify `total_tokens` and `usage` are nil by default on message factory.
4. Verify hierarchy cascade (instance -> lemming -> department -> city -> world).
5. Verify `config_snapshot` is a valid map.
6. Run `mix compile` to verify factory compiles.

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
