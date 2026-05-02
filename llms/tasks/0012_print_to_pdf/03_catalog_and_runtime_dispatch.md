# Task 03: Catalog And Runtime Dispatch

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix runtime boundaries and adapter integration.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Register the document tools in the fixed catalog and dispatch them through `LemmingsOs.Tools.Runtime`.

## Objective
Expose `documents.markdown_to_html` and `documents.print_to_pdf` through the existing fixed catalog and runtime normalization envelope while preserving World/instance scope checks.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Task 02
- [X] `lib/lemmings_os/tools/catalog.ex`
- [X] `lib/lemmings_os/tools/runtime.ex`
- [X] `test/lemmings_os/tools/catalog_test.exs`
- [X] `test/lemmings_os/tools/runtime_test.exs`

## Expected Outputs
- [X] Catalog includes both document tools with appropriate names, descriptions, icons, categories, and risk values.
- [X] `Catalog.supported_tool?/1` returns true for both document tools.
- [X] `Runtime.execute/5` dispatches both tool names to a documents adapter module.
- [X] Runtime responses keep the existing normalized success and error shapes.
- [X] Runtime metadata `work_area_ref` continues to be passed to adapters.
- [X] Focused catalog and runtime dispatch tests.

## Acceptance Criteria
- [X] No second result envelope such as `%{status: "ok"}` is introduced.
- [X] Unsupported tool and invalid scope behavior remain unchanged.
- [X] The dispatch layer does not perform document conversion or PDF backend logic.
- [X] Tests cover both success normalization and safe error normalization for document tools.

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
- [X] Added `documents.markdown_to_html` and `documents.print_to_pdf` entries to the fixed tool catalog.
- [X] Updated catalog doctest expectation to include both new document tool IDs.
- [X] Added runtime dispatch clauses for both document tools in `LemmingsOs.Tools.Runtime`.
- [X] Added `LemmingsOs.Tools.Adapters.Documents` as a minimal adapter boundary for dispatch integration tests (no conversion/PDF implementation).
- [X] Added focused catalog/runtime tests for supported IDs, normalized success, normalized error, and `work_area_ref` pass-through.

### Outputs Created
- [X] Updated `lib/lemmings_os/tools/catalog.ex`
- [X] Updated `lib/lemmings_os/tools/runtime.ex`
- [X] Added `lib/lemmings_os/tools/adapters/documents.ex`
- [X] Updated `test/lemmings_os/tools/catalog_test.exs`
- [X] Updated `test/lemmings_os/tools/runtime_test.exs`

### Assumptions Made
- [X] Task 03 should only wire catalog/dispatch contracts and defer real document conversion/backend behavior to later tasks.
- [X] Minimal adapter behavior is acceptable if it preserves runtime result envelope and returns namespaced validation errors for bad args.

### Decisions Made
- [X] Implemented placeholder adapter functions that validate required paths and return structured tuples, without filesystem/PDF side effects.
- [X] Preserved all existing scope/unsupported handling by only adding targeted dispatch clauses.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format lib/lemmings_os/tools/adapters/documents.ex lib/lemmings_os/tools/catalog.ex lib/lemmings_os/tools/runtime.ex test/lemmings_os/tools/catalog_test.exs test/lemmings_os/tools/runtime_test.exs llms/tasks/0012_print_to_pdf/03_catalog_and_runtime_dispatch.md` (success)
- [X] `mix test test/lemmings_os/tools/catalog_test.exs` (success; 3 tests, 0 failures)
- [X] `mix test test/lemmings_os/tools/runtime_test.exs` (success; 15 tests, 0 failures)

## Human Review
Human reviewer confirms the public tool IDs and runtime envelope before Task 04 begins.
