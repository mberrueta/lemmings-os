# Task 13: Add Req Dependency

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

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
