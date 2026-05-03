# Task 05: PDF Backend And Atomic Output

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for HTTP integrations, adapter boundaries, and safe filesystem writes.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the core `documents.print_to_pdf` behavior using Req and Gotenberg.

## Objective
Print supported WorkArea source files to PDF through the configured Gotenberg HTML conversion endpoint, with validation before network calls and atomic final output.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Tasks 01 through 04
- [X] `llms/coding_styles/elixir.md`
- [X] `llms/coding_styles/elixir_tests.md`
- [X] Documents config from Task 02
- [X] Documents adapter from Task 04

## Expected Outputs
- [X] `documents.print_to_pdf` validates `source_path`, `output_path`, supported source extension, optional paper/orientation/margin options, `print_raw_file`, and `overwrite`.
- [X] `.html` and `.htm` sources print as HTML.
- [X] `.md` sources render to HTML unless `print_raw_file: true`.
- [X] `.txt` sources render through a raw text wrapper.
- [X] `.png`, `.jpg`, `.jpeg`, and `.webp` sources render through a single-image wrapper.
- [X] Gotenberg request uses `Req` multipart to `/forms/chromium/convert/html`.
- [X] Non-2xx responses return `tool.documents.pdf_conversion_failed`.
- [X] Timeouts and connection failures return `tool.documents.pdf_backend_unavailable`.
- [X] Transient backend failures retry according to config; validation errors are not retried.
- [X] PDF response body is written to a temp file in the target directory, size-checked, then atomically renamed.
- [X] Failed conversion or size validation leaves no partial final PDF at `output_path`.

## Acceptance Criteria
- [X] Agents never provide or override the Gotenberg URL.
- [X] No shell execution or Chromium dependency inside the Phoenix app is introduced.
- [X] Result details contain WorkArea-relative source/output paths, `application/pdf`, and byte size only.
- [X] Backend response bodies and document contents are not logged or returned.
- [X] Bypass tests cover success, non-2xx failure, timeout/unavailable failure, retry behavior, oversized PDF, output conflict, and atomic failure cleanup.

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
- [X] Implemented full `documents.print_to_pdf` flow in `LemmingsOs.Tools.Adapters.Documents`.
- [X] Added strict argument validation for source/output paths and print options (`overwrite`, `print_raw_file`, `landscape`, optional paper/margins).
- [X] Added supported source type handling: `.html/.htm`, `.md`, `.txt`, `.png/.jpg/.jpeg/.webp`.
- [X] Added source-to-HTML normalization (markdown render, raw text wrapper, image data-URI wrapper).
- [X] Added Gotenberg integration via `Req` multipart POST to `/forms/chromium/convert/html`.
- [X] Added transient backend retry handling (`429/502/503/504`) controlled by `pdf_retries`.
- [X] Added transport error mapping to `tool.documents.pdf_backend_unavailable`.
- [X] Added non-2xx mapping to `tool.documents.pdf_conversion_failed`.
- [X] Added PDF max-size enforcement (`tool.documents.pdf_too_large`).
- [X] Added atomic PDF output write (temp file + rename + cleanup on failure).
- [X] Added focused adapter tests for success/failure matrix.

### Outputs Created
- [X] Updated `lib/lemmings_os/tools/adapters/documents.ex`
- [X] Updated `test/lemmings_os/tools/adapters/documents_test.exs`

### Assumptions Made
- [X] Task 05 excludes header/footer/CSS multipart files and their precedence logic (covered in Task 06).
- [X] Unknown `paper_size` values are ignored in Task 05 and do not fail conversion.

### Decisions Made
- [X] Kept document adapter responsible for parsing env-sourced numeric config values (string/integer) with safe defaults.
- [X] Chose retryable status set `[429, 502, 503, 504]` and transport failures as transient retry candidates.
- [X] Kept preview `nil` for PDF results and excluded response/body content from result details.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format lib/lemmings_os/tools/adapters/documents.ex test/lemmings_os/tools/adapters/documents_test.exs test/lemmings_os/tools/runtime_test.exs llms/tasks/0012_print_to_pdf/05_pdf_backend_and_atomic_output.md` (success)
- [X] `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success; 15 tests, 0 failures)
- [X] `mix test test/lemmings_os/tools/runtime_test.exs` (success; 15 tests, 0 failures)

## Human Review
Human reviewer confirms the Gotenberg request contract, retry behavior, and atomic PDF write behavior before Task 06 begins.
