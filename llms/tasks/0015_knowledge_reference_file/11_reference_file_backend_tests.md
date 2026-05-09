# Task 11: Reference File Backend Tests

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer for ExUnit, DataCase, integration, and OTP-safe tests.

## Agent Invocation

Act as `qa-elixir-test-author`. Add backend tests for reference-file schemas, storage, context lifecycle, scope enforcement, search/read, Artifact promotion, and observability.

## Objective

Convert the Task 01 scenario matrix into focused ExUnit coverage for backend behavior.

## Implementation Scope

- Add schema/changeset tests for `reference_file` kind, statuses, type validation, optional `artifact_id`, descriptor fields, and memory/source-file regressions.
- Add storage tests for opaque refs, checksum/size, filename/path rejection, root confinement, and no-path-leak behavior.
- Add context tests for create/register/upload, update metadata, archive, list, availability, search, read, and descriptor output.
- Add read tests for text reference files returning bounded direct content.
- Add read tests for supported binary/structured reference files using a fake converter boundary and returning bounded converted text.
- Add read tests for unsupported binary files returning a safe descriptor without raw bytes, paths, or storage refs.
- Add scope tests for World, City, Department, Lemming, sibling denial, and cross-World denial.
- Add Artifact promotion tests for explicit approval path, optional provenance, and later Artifact unavailability.
- Add observability payload safety tests where practical.

## Constraints

- Use factories as the default test data mechanism.
- Do not introduce fixture-style helpers or `*_fixture` naming.
- Keep tests deterministic; no external network.
- Avoid large raw HTML assertions because this task is backend-focused.
- Use sentinel path/content values to prove they do not appear in public outputs/events.
- Business-rule validation tests should target Ecto changesets/context behavior, not DB `CHECK` constraints.
- DB-level tests should be limited to references, unique guarantees, and migration/index expectations where appropriate.

## Expected Outputs

- Backend ExUnit coverage for reference-file behavior.
- Factory/test support needed by later UI/tool tests.
- Regression assertions for memories, source files, and `knowledge.store` boundaries where backend-visible.

## Suggested Checks

- `mix format`
- Narrow backend test files created by this task
- `mix test test/lemmings_os/knowledge_test.exs test/lemmings_os/knowledge/knowledge_item_test.exs`

## Human Approval Gate

Human reviewer validates backend coverage and deterministic test style, then approves Task 12.

## Completion Notes

- Added and validated backend coverage for reference-file lifecycle, scope,
  search/read behavior, promotion path, and event payload safety in:
  - `test/lemmings_os/knowledge_test.exs`
  - `test/lemmings_os/knowledge/knowledge_item_test.exs`
  - `test/lemmings_os/knowledge/reference_file_test.exs`
  - `test/lemmings_os/knowledge/reference_file_storage_test.exs`
- Coverage includes:
  - optional `artifact_id` provenance for reference files
  - active/archived lifecycle validation
  - scope enforcement across world/city/department/lemming and sibling/cross-world denial
  - bounded reads (direct + converted) and descriptor-only unreadable behavior
  - no chunk/embedding side effects for reference-file reads
  - safe event payload assertions (no path/content/storage-ref leakage)
- Validation run:
  - `mix test test/lemmings_os/knowledge/knowledge_item_test.exs test/lemmings_os/knowledge/reference_file_test.exs test/lemmings_os/knowledge/reference_file_storage_test.exs test/lemmings_os/knowledge_test.exs`
  - Result: pass
