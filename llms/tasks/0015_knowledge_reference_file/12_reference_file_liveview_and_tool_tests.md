# Task 12: Reference File LiveView And Tool Tests

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer for LiveView, tool runtime, and integration behavior.

## Agent Invocation

Act as `qa-elixir-test-author`. Add LiveView and runtime tool tests for reference files.

## Objective

Verify the user-facing and Lemming-facing behavior for reference files using stable selectors and outcome-based assertions.

## Implementation Scope

- Add LiveView tests for Reference Files tab selection, empty state, upload/register, list, filters, edit, archive, detail, unreadable preview, unavailable provenance, and promotion UI.
- Add tool adapter tests for `knowledge.search` with `kind: "reference_file"`, `knowledge.read` for reference files, availability/list behavior if exposed, unsupported fields, invalid kind combinations, and mutation rejection.
- Add tool tests proving `knowledge.read` gives Lemmings bounded text for text references, bounded converted text for supported non-text references, and safe descriptor-only output for unsupported files.
- Add regression tests for existing source-file search/read and memory `knowledge.store`.
- Use stable DOM IDs from templates and `Phoenix.LiveViewTest` helpers such as `element/2`, `render_click/1`, `render_change/1`, and `has_element?/2`.

## Constraints

- Do not assert against large raw HTML.
- Use upload helpers and controlled temp files consistent with existing Knowledge LiveView tests.
- Do not rely on source-file chunks or embeddings for reference-file tests.
- Keep tool outputs checked for no raw path, no storage ref, no unbounded content, and no inaccessible resource hints.

## Expected Outputs

- LiveView tests covering operator workflows and UI states.
- Tool adapter tests covering reference-file search/read and mutation boundaries.
- Regression coverage for existing Knowledge tabs and tool behavior.

## Suggested Checks

- `mix format`
- `mix test test/lemmings_os/tools/adapters/knowledge_test.exs test/lemmings_os_web/live/knowledge_live_test.exs`

## Human Approval Gate

Human reviewer validates UI/tool coverage and regression assertions, then approves Task 13.

## Completion Notes

- Added and validated LiveView and tool adapter coverage for reference-file
  behavior in:
  - `test/lemmings_os_web/live/knowledge_live_test.exs`
  - `test/lemmings_os/tools/adapters/knowledge_test.exs`
- LiveView coverage includes:
  - Reference Files tab deep-link behavior
  - upload/create flow
  - metadata edit flow
  - archive flow and archived filtering
  - detail/provenance unreadable/unavailable states
  - stable DOM IDs and selector-driven assertions
- Tool adapter coverage includes:
  - `knowledge.search` for `kind: "reference_file"` metadata lookup
  - `knowledge.read` direct bounded text + descriptor-only unreadable output
  - mixed-kind/unsupported field rejection
  - `knowledge.store` memory-only boundary regression
  - safe event payload behavior
- Validation run:
  - `mix test test/lemmings_os/tools/adapters/knowledge_test.exs test/lemmings_os_web/live/knowledge_live_test.exs`
  - Result: pass
