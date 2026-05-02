# Task 03: Catalog And Runtime Dispatch

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix runtime boundaries and adapter integration.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Register the document tools in the fixed catalog and dispatch them through `LemmingsOs.Tools.Runtime`.

## Objective
Expose `documents.markdown_to_html` and `documents.print_to_pdf` through the existing fixed catalog and runtime normalization envelope while preserving World/instance scope checks.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Task 02
- [ ] `lib/lemmings_os/tools/catalog.ex`
- [ ] `lib/lemmings_os/tools/runtime.ex`
- [ ] `test/lemmings_os/tools/catalog_test.exs`
- [ ] `test/lemmings_os/tools/runtime_test.exs`

## Expected Outputs
- [ ] Catalog includes both document tools with appropriate names, descriptions, icons, categories, and risk values.
- [ ] `Catalog.supported_tool?/1` returns true for both document tools.
- [ ] `Runtime.execute/5` dispatches both tool names to a documents adapter module.
- [ ] Runtime responses keep the existing normalized success and error shapes.
- [ ] Runtime metadata `work_area_ref` continues to be passed to adapters.
- [ ] Focused catalog and runtime dispatch tests.

## Acceptance Criteria
- [ ] No second result envelope such as `%{status: "ok"}` is introduced.
- [ ] Unsupported tool and invalid scope behavior remain unchanged.
- [ ] The dispatch layer does not perform document conversion or PDF backend logic.
- [ ] Tests cover both success normalization and safe error normalization for document tools.

## Technical Notes
- Expected new adapter target: `LemmingsOs.Tools.Adapters.Documents`.
- If the adapter does not exist yet, add only minimal placeholder functions needed for dispatch tests, returning structured `tool.validation.invalid_args` until later tasks implement behavior.
- Keep catalog doctests updated if the fixed list examples change.

## Execution Instructions
1. Read existing catalog/runtime modules and tests.
2. Add catalog entries and runtime dispatch clauses.
3. Add or update focused tests.
4. Run:
   ```text
   mix test test/lemmings_os/tools/catalog_test.exs
   mix test test/lemmings_os/tools/runtime_test.exs
   mix format
   ```
5. Record commands and results in this task file.

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
Human reviewer confirms the public tool IDs and runtime envelope before Task 04 begins.
