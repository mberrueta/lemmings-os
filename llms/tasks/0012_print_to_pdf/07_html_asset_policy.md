# Task 07: HTML Asset Policy

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix adapter implementation, validation, and safe external service boundaries.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement conservative HTML and CSS asset policy enforcement before `documents.print_to_pdf` calls Gotenberg.

## Objective
Ensure generated/source HTML, headers, footers, and CSS are screened for blocked remote/local asset references before Gotenberg is called.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Tasks 01 through 06
- [X] `llms/coding_styles/elixir.md`
- [X] `llms/coding_styles/elixir_tests.md`
- [X] Documents adapter from Tasks 04 through 06

## Expected Outputs
- [X] Conservative guards reject `http://`, `https://`, `file://`, protocol-relative `//...`, and CSS `@import` in HTML/CSS inputs before Gotenberg calls.
- [X] Markdown-generated HTML, text wrappers, image wrappers, explicit assets, conventional assets, fallback assets, and source HTML pass through the same policy before PDF conversion.
- [X] Tests verify blocked asset references fail before the Bypass Gotenberg endpoint receives a request.
- [X] Tests verify allowed local WorkArea documents still print when no blocked references are present.
- [X] Error responses use structured namespaced errors and WorkArea-relative details only.

## Acceptance Criteria
- [X] Remote asset support is not added.
- [X] The asset guard is documented as conservative MVP string/pattern blocking, not a complete HTML/CSS parser.
- [X] Validation failures happen before backend calls and are not retried.
- [X] Asset policy applies consistently to source HTML, generated Markdown HTML, generated text/image wrappers, header/footer HTML, and CSS.

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
- [X] Added asset policy enforcement in `documents.print_to_pdf` before Gotenberg calls.
- [X] Implemented conservative blockers for:
  - `http://` / `https://`
  - `file://`
  - protocol-relative `//...`
  - CSS `@import`
- [X] Applied checks across source HTML and resolved print assets (header/footer/styles), covering explicit, conventional, and fallback assets.
- [X] Added structured namespaced error:
  - `tool.documents.blocked_asset_reference`
  - includes safe details with relative field/path references and reason code only.
- [X] Added fail-fast tests that assert backend is never called when policy blocks input.

### Outputs Created
- [X] Updated `lib/lemmings_os/tools/adapters/documents.ex`
- [X] Updated `test/lemmings_os/tools/adapters/documents_test.exs`

### Assumptions Made
- [X] Conservatively matching obvious blocked references is acceptable for MVP and intentionally not a full parser.
- [X] Existing successful print flows from Tasks 05/06 remain the allowed local-path baseline when blocked patterns are absent.

### Decisions Made
- [X] Enforced policy as a dedicated validation step before `convert_html_to_pdf/3` so blocked inputs never reach retry/network paths.
- [X] Kept error details minimal and relative (`field`, relative path or fallback marker, reason) to avoid path/content leakage.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format lib/lemmings_os/tools/adapters/documents.ex test/lemmings_os/tools/adapters/documents_test.exs llms/tasks/0012_print_to_pdf/07_html_asset_policy.md` (success)
- [X] `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success; 22 tests, 0 failures)
- [X] `mix test test/lemmings_os/tools/runtime_test.exs` (success; 15 tests, 0 failures)

## Human Review
Human reviewer confirms asset blocking behavior before Task 08 begins.
