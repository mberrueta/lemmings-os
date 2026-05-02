# Task 12: Elixir Code And PR Audit

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends, correctness, design quality, security, performance, logging, and test coverage.

## Agent Invocation
Act as `audit-pr-elixir`. Review the completed implementation from an Elixir/Phoenix code-review stance.

## Objective
Audit production Elixir changes for correctness, runtime result shape consistency, path safety, config hygiene, retry behavior, atomic writes, logging safety, maintainability, and adherence to project Elixir style.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 02 through 11
- [ ] `llms/coding_styles/elixir.md`
- [ ] Diff of production Elixir/config/deployment/docs changes

## Expected Outputs
- [ ] Findings written into this task file, ordered by severity.
- [ ] Confirmation that existing runtime envelopes remain unchanged.
- [ ] Confirmation that WorkArea and fallback trust boundaries are respected.
- [ ] Confirmation that public functions added or materially changed have appropriate docs/specs.
- [ ] Confirmation that no `String.to_atom/1`, shell execution, hardcoded secrets, or unsafe path logging was introduced.
- [ ] Required fixes identified for follow-up implementation before final validation.

## Acceptance Criteria
- [ ] Review findings include file/line references.
- [ ] No implementation edits are made by this audit task unless the human explicitly requests a fix task.
- [ ] Code style issues relevant to `llms/coding_styles/elixir.md` are covered.
- [ ] Residual risks and test gaps are documented.

## Technical Notes
- This is a review task, not a development task.
- Pay special attention to safe handling of external HTTP failure modes and filesystem cleanup.

## Execution Instructions
1. Read the plan and style docs.
2. Inspect the implementation diff and relevant files.
3. Run read-only or validation commands as needed.
4. Write findings and recommendations in this task file.

## Execution Summary

### Work Performed
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer resolves or waives audit findings before Task 13 begins.
