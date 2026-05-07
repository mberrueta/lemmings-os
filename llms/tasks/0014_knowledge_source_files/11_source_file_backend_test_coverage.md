# Task 11: Source File Backend Test Coverage

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit author for backend and integration coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement backend-focused ExUnit coverage for source-file Knowledge flows.

## Objective
Add deterministic tests for schema/context/storage/extraction/chunking/embedding/retrieval/tool-facing backend behavior.

## Inputs Required
- [x] Tasks 01-10 approved
- [x] Task 01 scenario matrix
- [x] `llms/coding_styles/elixir_tests.md`

## Expected Outputs
- [x] Backend tests for lifecycle, limits, scope enforcement, and ready-only retrieval.
- [x] Backend tests for tools runner extraction fakes, registered capabilities, PDF fallback, and `needs_ocr`.
- [x] If Oban is added, deterministic worker/job tests using direct execution or Oban testing helpers.
- [x] Tests for leakage prevention (paths, vectors, provider payloads, extracted full text).
- [x] Regression protection for existing memory behavior.

## Acceptance Criteria
- [x] Tests are deterministic and sandbox-safe.
- [x] Tests cover default limits: size/time/chars/chunk count.
- [x] Tests verify MarkItDown upload extraction, Trafilatura URL/HTML extraction, and `pdftotext` fallback behavior.
- [x] Tests verify no Apache Tika service/client/dependency is required.
- [x] Tests verify `knowledge.store` remains memory-only.

## Constraints
- Use factories and existing test patterns.
- Do not rely on sleeps for background indexing assertions.

## Approval Gate
Human reviewer must approve this task before Task 12 begins.

## Human Review
*[Filled by human reviewer]*

## Execution Summary
- Added deterministic extraction backend coverage for PDF fallback and OCR gate behavior in `test/lemmings_os/knowledge/source_files/extraction_service_test.exs`.
- Added extraction max-char clamp assertion to validate configured `max_extracted_chars` enforcement.
- Existing backend coverage already validated lifecycle transitions, scope enforcement, ready-only retrieval, Oban indexing worker behavior, storage/path safety, and `knowledge.store` memory-only regression constraints across:
  - `test/lemmings_os/knowledge/source_files_context_test.exs`
  - `test/lemmings_os/knowledge/source_files/indexing_worker_test.exs`
  - `test/lemmings_os/knowledge/source_file_storage_test.exs`
  - `test/lemmings_os/tools/runtime_test.exs`
- Targeted test run passed:
  - `mix test test/lemmings_os/knowledge/source_files/extraction_service_test.exs test/lemmings_os/knowledge/source_files/indexing_worker_test.exs`
