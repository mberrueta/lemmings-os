# Task 11: Source File Backend Test Coverage

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit author for backend and integration coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement backend-focused ExUnit coverage for source-file Knowledge flows.

## Objective
Add deterministic tests for schema/context/storage/extraction/chunking/embedding/retrieval/tool-facing backend behavior.

## Inputs Required
- [ ] Tasks 01-10 approved
- [ ] Task 01 scenario matrix
- [ ] `llms/coding_styles/elixir_tests.md`

## Expected Outputs
- [ ] Backend tests for lifecycle, limits, scope enforcement, and ready-only retrieval.
- [ ] Backend tests for tools runner extraction fakes, registered capabilities, PDF fallback, and `needs_ocr`.
- [ ] If Oban is added, deterministic worker/job tests using direct execution or Oban testing helpers.
- [ ] Tests for leakage prevention (paths, vectors, provider payloads, extracted full text).
- [ ] Regression protection for existing memory behavior.

## Acceptance Criteria
- [ ] Tests are deterministic and sandbox-safe.
- [ ] Tests cover default limits: size/time/chars/chunk count.
- [ ] Tests verify MarkItDown upload extraction, Trafilatura URL/HTML extraction, and `pdftotext` fallback behavior.
- [ ] Tests verify no Apache Tika service/client/dependency is required.
- [ ] Tests verify `knowledge.store` remains memory-only.

## Constraints
- Use factories and existing test patterns.
- Do not rely on sleeps for background indexing assertions.

## Approval Gate
Human reviewer must approve this task before Task 12 begins.

## Human Review
*[Filled by human reviewer]*
