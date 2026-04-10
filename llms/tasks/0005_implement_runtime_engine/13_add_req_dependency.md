# Task 13: Add Req Dependency

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Elixir/Phoenix.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and add the `Req` HTTP client dependency to `mix.exs`.

## Objective
Add `{:req, "~> 0.5"}` to the project dependencies in `mix.exs`. This is a prerequisite for the `ModelRuntime` / Ollama provider integration (Task 08). The constitution mandates `Req` for all HTTP client operations.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `mix.exs` - Current dependency list
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #15 (ModelRuntime / Ollama provider integration specifies Req)

## Expected Outputs

- [ ] Modified `mix.exs` - Added `{:req, "~> 0.5"}` to deps

## Acceptance Criteria

- [ ] `{:req, "~> 0.5"}` is added to the `deps/0` function in `mix.exs`
- [ ] Placement is in the main (non-dev, non-test) dependency section, since Req is a production dependency
- [ ] No other dependencies are added or modified
- [ ] The version spec is `"~> 0.5"` as specified in plan.md Frozen Contract #15

## Technical Notes

### Relevant Code Locations
```
mix.exs    # Lines 59-103, deps/0 function
```

### Placement Guidance
Add `{:req, "~> 0.5"}` in the production dependencies section (after `{:bandit, "~> 1.5"}` and before the dev tooling section comment). Example placement:

```elixir
{:bandit, "~> 1.5"},
{:req, "~> 0.5"},
```

### Constraints
- Do not run `mix deps.get` -- the human reviewer will do that
- Do not modify any other dependencies
- Do not add Req to `:only` options -- it is a production dependency

## Execution Instructions

### For the Agent
1. Read `mix.exs` to find the correct insertion point.
2. Add `{:req, "~> 0.5"}` in the production dependencies section.
3. Verify no duplicate or conflicting entry exists.

### For the Human Reviewer
1. Verify `{:req, "~> 0.5"}` is in the production deps section.
2. Run `mix deps.get` to fetch the dependency.
3. Verify no version conflicts.

---

## Execution Summary
Task completed. The required production dependency was already present in the branch, so no `mix.exs` code edit was necessary.

### Work Performed
- Verified `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, the task contract, and the runtime engine plan requirements.
- Inspected [mix.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/mix.exs) and confirmed `{:req, "~> 0.5"}` is already declared in the main production dependency block directly after `{:bandit, "~> 1.5"}`.
- Confirmed there is no duplicate `Req` dependency entry and no other dependency changes were required.

### Outputs Created
- Updated [llms/tasks/0005_implement_runtime_engine/13_add_req_dependency.md](/mnt/data4/matt/code/personal_stuffs/lemmings-os/llms/tasks/0005_implement_runtime_engine/13_add_req_dependency.md)

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
- Task 13 should be considered satisfied when the repository already contains the exact required dependency entry. | The acceptance criteria are about the final state of `mix.exs`, not whether this turn introduces a new code diff. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
- Marked the task artifact complete without modifying `mix.exs`. | Re-adding or touching the existing dependency entry. | The repo already satisfies the contract exactly, and unnecessary edits would create noise. |

### Blockers Encountered
- None.

### Questions for Human
1. None.

### Ready for Next Task
- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

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
