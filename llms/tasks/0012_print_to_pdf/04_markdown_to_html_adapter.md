# Task 04: Markdown To HTML Adapter

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix adapter implementation and WorkArea-safe file operations.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement `documents.markdown_to_html` inside the first-party documents adapter.

## Objective
Convert WorkArea-relative Markdown files into complete printable HTML documents inside the same WorkArea using Earmark, safe path validation, output conflict checks, source size checks, and atomic writes.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Tasks 01 through 03
- [X] `llms/coding_styles/elixir.md`
- [X] `llms/coding_styles/elixir_tests.md`
- [X] `lib/lemmings_os/tools/work_area.ex`
- [X] `lib/lemmings_os/tools/adapters/filesystem.ex`
- [X] `lib/lemmings_os/tools/adapters/documents.ex` if created by Task 03

## Expected Outputs
- [X] `documents.markdown_to_html` validates `source_path`, `output_path`, and optional `overwrite`.
- [X] Source path must be `.md`; output path must be `.html` or `.htm`.
- [X] All agent-controlled paths resolve through `WorkArea.resolve/2`.
- [X] Missing source, unsupported extension, invalid path, output conflict, oversized source, and write failures return structured errors from `plan.md`.
- [X] Markdown is rendered with Earmark and wrapped in a minimal complete HTML document with UTF-8 charset and printable CSS.
- [X] Generated HTML is written via temp file in the target directory plus atomic rename.
- [X] Success result includes WorkArea-relative paths, content type, and byte size only.
- [X] Preview contains a short HTML preview and does not expose host paths.

## Acceptance Criteria
- [X] No EEx, HEEx, Liquid, or other executable template rendering is introduced.
- [X] `overwrite: false` protects existing outputs.
- [X] Failed writes do not leave a partial final output file.
- [X] Logs and results do not include absolute paths, WorkArea roots, raw fallback paths, or unsafe content.
- [X] Tests cover success, conflict, overwrite, missing source, invalid paths, extension validation, source size limit, and atomic failure behavior.

## Technical Notes
- Preserve the adapter result shape before runtime normalization:
  `{:ok, %{summary: binary(), preview: binary() | nil, result: map()}}`.
- Follow existing filesystem adapter patterns for runtime metadata and WorkArea ref selection.
- Prefer small private helpers and pattern-matched validation clauses.

## Execution Instructions
1. Read style docs and existing filesystem adapter tests.
2. Implement Markdown conversion behavior.
3. Add focused adapter tests in `test/lemmings_os/tools/adapters/documents_test.exs`.
4. Run:
   ```text
   mix test test/lemmings_os/tools/adapters/documents_test.exs
   mix test test/lemmings_os/tools/runtime_test.exs
   mix format
   ```
5. Record commands and results in this task file.

## Execution Summary

### Work Performed
- [X] Replaced the Task 03 placeholder logic for `documents.markdown_to_html` with full WorkArea-backed conversion flow.
- [X] Added args validation for `source_path`, `output_path`, and `overwrite`.
- [X] Added WorkArea path resolution for all agent-controlled paths using `WorkArea.resolve/2`.
- [X] Added source/output extension checks (`.md` source, `.html`/`.htm` output).
- [X] Added output conflict handling (`tool.documents.output_exists`) and overwrite support.
- [X] Added source existence checks and source size limit enforcement (`tool.documents.file_too_large`) using `:documents` config.
- [X] Added Earmark markdown rendering and wrapping into full printable HTML document.
- [X] Added atomic output write flow (temp file + rename) with cleanup on error.
- [X] Kept result payload safe with WorkArea-relative paths, content type, and byte size only.
- [X] Added focused adapter tests for success and failure matrix.

### Outputs Created
- [X] Updated `lib/lemmings_os/tools/adapters/documents.ex`
- [X] Added `test/lemmings_os/tools/adapters/documents_test.exs`
- [X] Updated `test/lemmings_os/tools/runtime_test.exs`

### Assumptions Made
- [X] `max_source_bytes` may be configured as integer or numeric string; adapter parses both and falls back to task default when invalid.
- [X] Earmark parse warnings do not fail conversion for MVP and still produce HTML output.

### Decisions Made
- [X] Reused filesystem adapter WorkArea resolution pattern and error normalization for path safety consistency.
- [X] Mapped markdown rendering failures and output write failures to `tool.documents.write_failed`.
- [X] Implemented output directory creation before temp write to keep final write atomic and explicit.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format lib/lemmings_os/tools/adapters/documents.ex test/lemmings_os/tools/adapters/documents_test.exs test/lemmings_os/tools/runtime_test.exs` (success)
- [X] `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success; 9 tests, 0 failures)
- [X] `mix test test/lemmings_os/tools/runtime_test.exs` (success; 15 tests, 0 failures)

## Human Review
Human reviewer confirms Markdown rendering, path safety, output policy, and error shape before Task 05 begins.
