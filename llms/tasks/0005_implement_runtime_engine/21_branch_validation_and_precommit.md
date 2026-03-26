# Task 21: Branch Validation and Precommit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Elixir/Phoenix.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and validate the entire branch: fix all compiler warnings, ensure `mix test` passes with zero failures, ensure `mix precommit` passes, and generate a coverage report.

## Objective
Run the full quality gate suite on the branch and fix any issues found. This is the final implementation task before review -- every prior task's output must compile, pass tests, and meet the constitution's quality standards. Fix compiler warnings, failing tests, Credo issues, and any other precommit failures. Generate a coverage report via `mix coveralls.html`.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules (zero warnings, zero failures, precommit gate)
- [ ] All implementation and test outputs required before branch validation - The full branch state to validate at Task 21
- [ ] `mix.exs` - Aliases for `precommit`, `test`, `coveralls.html`

## Expected Outputs

- [ ] All compiler warnings resolved (modified source files as needed)
- [ ] All test failures resolved (modified test or source files as needed)
- [ ] All Credo issues resolved
- [ ] All Sobelow issues resolved or documented as acceptable
- [ ] Coverage report generated at `cover/excoveralls.html`
- [ ] Summary of all fixes applied

## Acceptance Criteria

### Compilation
- [ ] `mix compile --warnings-as-errors` passes with zero warnings
- [ ] No unused variables, unused imports, or missing function clauses

### Tests
- [ ] `mix test` passes with zero failures
- [ ] No flaky tests (all deterministic)
- [ ] No skipped tests without documented reason

### Precommit
- [ ] `mix precommit` passes (this runs: compile warnings check, Credo, formatter, tests, Sobelow)
- [ ] `mix format --check-formatted` passes
- [ ] `mix credo --strict` passes
- [ ] `mix sobelow --config` passes (or issues documented as false positives)

### Coverage
- [ ] `mix coveralls.html` generates a report
- [ ] Coverage for new modules is reasonable (no untested modules)
- [ ] Report path documented for PR inclusion

### No Regressions
- [ ] Existing tests (pre-runtime-engine) still pass
- [ ] No existing functionality is broken by the new code

## Technical Notes

### Relevant Code Locations
```
mix.exs                                    # Aliases, deps
lib/lemmings_os/lemming_instances/         # All new backend modules
lib/lemmings_os_web/live/instance_live.ex  # New LiveView
test/lemmings_os/lemming_instances/        # All new tests
test/lemmings_os_web/live/                 # LiveView tests
```

### Common Issues to Watch For
- Unused aliases from incremental development
- Missing `@impl true` annotations on GenServer callbacks
- Formatter inconsistencies from multiple agent authoring
- Credo warnings about module complexity or function length
- Sobelow warnings about SQL injection in dynamic queries (document as false positive if using Ecto parameterization)

### Constraints
- Do NOT skip any warnings or failures -- fix them
- Do NOT add `# credo:disable-for-this-file` without documented justification
- Do NOT modify test expectations to make failing tests pass -- fix the source code instead
- The human reviewer will run all commands to verify; document exactly what was fixed

## Execution Instructions

### For the Agent
1. Run `mix compile --warnings-as-errors` and fix all warnings.
2. Run `mix format` to ensure formatting.
3. Run `mix credo --strict` and fix issues.
4. Run `mix test` and fix failures.
5. Run `mix precommit` as the final gate.
6. Run `mix coveralls.html` to generate coverage report.
7. Document every fix in the Execution Summary.

### For the Human Reviewer
1. Run `mix compile --warnings-as-errors` independently.
2. Run `mix test` independently.
3. Run `mix precommit` independently.
4. Review the coverage report.
5. Verify no existing tests were broken.
6. Verify fixes are appropriate (not just suppressing warnings).

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
