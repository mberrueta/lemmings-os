# Task 05: PDF Backend And Atomic Output

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for HTTP integrations, adapter boundaries, and safe filesystem writes.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the core `documents.print_to_pdf` behavior using Req and Gotenberg.

## Objective
Print supported WorkArea source files to PDF through the configured Gotenberg HTML conversion endpoint, with validation before network calls and atomic final output.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 04
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] Documents config from Task 02
- [ ] Documents adapter from Task 04

## Expected Outputs
- [ ] `documents.print_to_pdf` validates `source_path`, `output_path`, supported source extension, optional paper/orientation/margin options, `print_raw_file`, and `overwrite`.
- [ ] `.html` and `.htm` sources print as HTML.
- [ ] `.md` sources render to HTML unless `print_raw_file: true`.
- [ ] `.txt` sources render through a raw text wrapper.
- [ ] `.png`, `.jpg`, `.jpeg`, and `.webp` sources render through a single-image wrapper.
- [ ] Gotenberg request uses `Req` multipart to `/forms/chromium/convert/html`.
- [ ] Non-2xx responses return `tool.documents.pdf_conversion_failed`.
- [ ] Timeouts and connection failures return `tool.documents.pdf_backend_unavailable`.
- [ ] Transient backend failures retry according to config; validation errors are not retried.
- [ ] PDF response body is written to a temp file in the target directory, size-checked, then atomically renamed.
- [ ] Failed conversion or size validation leaves no partial final PDF at `output_path`.

## Acceptance Criteria
- [ ] Agents never provide or override the Gotenberg URL.
- [ ] No shell execution or Chromium dependency inside the Phoenix app is introduced.
- [ ] Result details contain WorkArea-relative source/output paths, `application/pdf`, and byte size only.
- [ ] Backend response bodies and document contents are not logged or returned.
- [ ] Bypass tests cover success, non-2xx failure, timeout/unavailable failure, retry behavior, oversized PDF, output conflict, and atomic failure cleanup.

## Technical Notes
- Use deterministic multipart filenames such as `index.html` for the main body.
- Keep this task focused on core source-to-PDF behavior. Header/footer/CSS resolution is Task 06.
- Be explicit about which error classes are validation failures and must not retry.

## Execution Instructions
1. Read existing web adapter Req patterns and Bypass tests.
2. Implement core print behavior.
3. Expand `documents_test.exs` and runtime tests as needed.
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
Human reviewer confirms the Gotenberg request contract, retry behavior, and atomic PDF write behavior before Task 06 begins.
