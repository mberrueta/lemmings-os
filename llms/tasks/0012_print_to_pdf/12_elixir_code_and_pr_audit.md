# Task 12: Elixir Code And PR Audit

## Status
- **Status**: COMPLETE
- **Approved**: [ ]

## Assigned Agent
`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends, correctness, design quality, security, performance, logging, and test coverage.

## Agent Invocation
Act as `audit-pr-elixir`. Review the completed implementation from an Elixir/Phoenix code-review stance.

## Objective
Audit production Elixir changes for correctness, runtime result shape consistency, path safety, config hygiene, retry behavior, atomic writes, logging safety, maintainability, and adherence to project Elixir style.

## Inputs Required
- [x] `llms/tasks/0012_print_to_pdf/plan.md`
- [x] Completed Tasks 02 through 11
- [x] `llms/coding_styles/elixir.md`
- [x] Diff of production Elixir/config/deployment/docs changes

## Expected Outputs
- [x] Findings written into this task file, ordered by severity.
- [x] Confirmation that existing runtime envelopes remain unchanged.
- [x] Confirmation that WorkArea and fallback trust boundaries are respected.
- [x] Confirmation that public functions added or materially changed have appropriate docs/specs.
- [x] Confirmation that no `String.to_atom/1`, shell execution, hardcoded secrets, or unsafe path logging was introduced.
- [x] Required fixes identified for follow-up implementation before final validation.

## Acceptance Criteria
- [x] Review findings include file/line references.
- [x] No implementation edits are made by this audit task unless the human explicitly requests a fix task.
- [x] Code style issues relevant to `llms/coding_styles/elixir.md` are covered.
- [x] Residual risks and test gaps are documented.

## Technical Notes
- This is a review task, not a development task.
- Pay special attention to safe handling of external HTTP failure modes and filesystem cleanup.

## Execution Instructions
1. Read the plan and style docs.
2. Inspect the implementation diff and relevant files.
3. Run read-only or validation commands as needed.
4. Write findings and recommendations in this task file.

## Review Findings (Ordered by Severity)

### MAJOR

1) Fallback asset path resolution is coupled to process current working directory and can silently disable configured fallback assets in release/service environments.
- **Where**: `lib/lemmings_os/tools/adapters/documents.ex:1074`, `lib/lemmings_os/tools/adapters/documents.ex:1075`
- **Why it matters**: `Path.expand(..., File.cwd!())` makes `priv/documents/...` resolution depend on startup CWD. In non-repo-root service starts, valid configured fallback paths can be treated as outside root or unreadable and get dropped silently.
- **Suggested fix**: Resolve against application paths (`:code.priv_dir(:lemmings_os)` / `Application.app_dir/2`) and enforce the `priv/documents` boundary from that canonical app root.

2) Failure and retry logs omit hierarchy metadata, reducing operability for distributed runtime incidents.
- **Where**: `lib/lemmings_os/tools/adapters/documents.ex:1342`, `lib/lemmings_os/tools/adapters/documents.ex:1352`, `lib/lemmings_os/tools/adapters/documents.ex:1367`, `lib/lemmings_os/tools/adapters/documents.ex:1398`
- **Why it matters**: backend retry/failure/unavailable events do not include `instance_id`, `world_id`, `city_id`, `department_id`, or `work_area_ref`, while this context is available in the caller. This weakens incident correlation and conflicts with the intended structured observability quality for runtime tools.
- **Suggested fix**: Thread `instance` + `runtime_meta` into retry/failure logging paths and merge `print_log_metadata/3` into these events.

## Post-Audit Resolution

- [x] Resolved MAJOR finding 1: fallback resolution now uses app-root/priv-root canonical paths instead of process CWD, and rejects symlinked path components for fallback files.
  - Evidence: `lib/lemmings_os/tools/adapters/documents.ex` fallback path resolution helpers and new symlinked-parent rejection test in `test/lemmings_os/tools/adapters/documents_test.exs`.
- [x] Resolved MAJOR finding 2: backend retry/failure/unavailable logs now include hierarchy metadata through threaded log metadata context.
  - Evidence: `lib/lemmings_os/tools/adapters/documents.ex` request/retry logging helpers now accept `log_metadata`.

## Confirmations

- Runtime envelope remains unchanged: `LemmingsOs.Tools.Runtime.normalize_tool_result/3` still emits `{:ok, %{tool_name, args, summary, preview, result}}` and `{:error, %{tool_name, code, message, details}}` (`lib/lemmings_os/tools/runtime.ex:168`).
- WorkArea and fallback trust boundaries are present: agent inputs resolve through `WorkArea.resolve/2` and fallback assets are separately constrained to `priv/documents` with symlink/extension/size checks (`lib/lemmings_os/tools/adapters/documents.ex:214`, `lib/lemmings_os/tools/adapters/documents.ex:1073`).
- Public APIs added/changed are documented and typed: `markdown_to_html/3` and `print_to_pdf/3` both have `@doc` and `@spec` (`lib/lemmings_os/tools/adapters/documents.ex:31`, `lib/lemmings_os/tools/adapters/documents.ex:77`).
- No `String.to_atom/1`, no shell execution, no hardcoded secrets, and no absolute-path leakage were introduced in reviewed scope.

## Residual Risks and Test Gaps

- No explicit assertion yet verifies every retry/failure backend log line contains full hierarchy metadata keys.
- `overwrite: false` remains best-effort under concurrent writer races (TOCTOU), which is acceptable for this MVP and documented for release notes.
- Compose/deployment docs and defaults were reviewed, but no end-to-end release smoke test was run in this audit task.

## Execution Summary

### Work Performed
- [x] Reviewed `plan.md`, style guidance, and Task 02–11 outputs relevant to documents runtime.
- [x] Audited production-scope files: documents adapter/runtime/catalog/config and deployment/docs updates.
- [x] Ran targeted validation tests:
  - `mix test test/lemmings_os/config/runtime_documents_config_test.exs test/lemmings_os/tools/adapters/documents_test.exs test/lemmings_os/tools/runtime_test.exs` (47 tests, 0 failures)
- [x] Recorded severity-ranked findings with concrete file/line references and fix recommendations.

### Outputs Created
- [x] Updated this file with audit findings, confirmations, and residual risk/test-gap notes.

### Assumptions Made
- [x] Review scope is the current Task 0012 documents implementation and associated deployment/docs changes present in the working tree.
- [x] Existing unrelated repository changes were not altered and were treated as read-only context.

### Decisions Made
- [x] Kept this as review-only (no production code edits).
- [x] Classified issues by merge risk/operational impact rather than style-only preference.

### Blockers
- [x] None.

### Questions for Human
- [x] None.

### Ready for Next Task
- [x] Yes
- [ ] No

## Human Review
Human reviewer resolves or waives audit findings before Task 13 begins.
