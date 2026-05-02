# Task 04: Markdown To HTML Adapter

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix adapter implementation and WorkArea-safe file operations.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement `documents.markdown_to_html` inside the first-party documents adapter.

## Objective
Convert WorkArea-relative Markdown files into complete printable HTML documents inside the same WorkArea using Earmark, safe path validation, output conflict checks, source size checks, and atomic writes.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 03
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `lib/lemmings_os/tools/work_area.ex`
- [ ] `lib/lemmings_os/tools/adapters/filesystem.ex`
- [ ] `lib/lemmings_os/tools/adapters/documents.ex` if created by Task 03

## Expected Outputs
- [ ] `documents.markdown_to_html` validates `source_path`, `output_path`, and optional `overwrite`.
- [ ] Source path must be `.md`; output path must be `.html` or `.htm`.
- [ ] All agent-controlled paths resolve through `WorkArea.resolve/2`.
- [ ] Missing source, unsupported extension, invalid path, output conflict, oversized source, and write failures return structured errors from `plan.md`.
- [ ] Markdown is rendered with Earmark and wrapped in a minimal complete HTML document with UTF-8 charset and printable CSS.
- [ ] Generated HTML is written via temp file in the target directory plus atomic rename.
- [ ] Success result includes WorkArea-relative paths, content type, and byte size only.
- [ ] Preview contains a short HTML preview and does not expose host paths.

## Acceptance Criteria
- [ ] No EEx, HEEx, Liquid, or other executable template rendering is introduced.
- [ ] `overwrite: false` protects existing outputs.
- [ ] Failed writes do not leave a partial final output file.
- [ ] Logs and results do not include absolute paths, WorkArea roots, raw fallback paths, or unsafe content.
- [ ] Tests cover success, conflict, overwrite, missing source, invalid paths, extension validation, source size limit, and atomic failure behavior.

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
Human reviewer confirms Markdown rendering, path safety, output policy, and error shape before Task 05 begins.
