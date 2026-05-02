# Task 07: HTML Asset Policy

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix adapter implementation, validation, and safe external service boundaries.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement conservative HTML and CSS asset policy enforcement before `documents.print_to_pdf` calls Gotenberg.

## Objective
Ensure generated/source HTML, headers, footers, and CSS are screened for blocked remote/local asset references before Gotenberg is called.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 06
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] Documents adapter from Tasks 04 through 06

## Expected Outputs
- [ ] Conservative guards reject `http://`, `https://`, `file://`, protocol-relative `//...`, and CSS `@import` in HTML/CSS inputs before Gotenberg calls.
- [ ] Markdown-generated HTML, text wrappers, image wrappers, explicit assets, conventional assets, fallback assets, and source HTML pass through the same policy before PDF conversion.
- [ ] Tests verify blocked asset references fail before the Bypass Gotenberg endpoint receives a request.
- [ ] Tests verify allowed local WorkArea documents still print when no blocked references are present.
- [ ] Error responses use structured namespaced errors and WorkArea-relative details only.

## Acceptance Criteria
- [ ] Remote asset support is not added.
- [ ] The asset guard is documented as conservative MVP string/pattern blocking, not a complete HTML/CSS parser.
- [ ] Validation failures happen before backend calls and are not retried.
- [ ] Asset policy applies consistently to source HTML, generated Markdown HTML, generated text/image wrappers, header/footer HTML, and CSS.

## Technical Notes
- This is backend/security behavior, not an observability task.
- Keep the MVP guard conservative and simple; do not introduce a full HTML or CSS parser unless the implementation already has one available.
- Safe logging/telemetry review is Task 08.

## Execution Instructions
1. Read the completed adapter implementation.
2. Add or tighten asset blocking before Gotenberg calls.
3. Add focused tests for blocked and allowed cases.
4. Run:
   ```text
   mix test test/lemmings_os/tools/adapters/documents_test.exs
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
Human reviewer confirms asset blocking behavior before Task 08 begins.
