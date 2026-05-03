# Task 16: Release Validation

## Status
- **Status**: COMPLETE
- **Approved**: [ ]

## Assigned Agent
`rm-release-manager` - Release manager for final validation, release notes, rollback, and operational readiness.

## Agent Invocation
Act as `rm-release-manager`. Perform final release validation for the document tools after implementation and audits are complete.

## Objective
Run or verify the final validation sequence, capture operational notes for Gotenberg, and confirm all approval gates and audits are complete before merge.

## Inputs Required
- [x] `llms/tasks/0012_print_to_pdf/plan.md`
- [x] Completed Tasks 01 through 15
- [x] Audit findings and resolutions
- [x] Final source/test/docs/deployment diff

## Expected Outputs
- [x] Final validation results recorded in this task file.
- [x] Targeted test command results recorded.
- [x] `mix format` result recorded.
- [x] `mix precommit` result recorded.
- [x] Compose/deployment validation notes recorded.
- [x] Release notes covering env vars, Gotenberg dependency, private exposure, rollback, and known non-goals.

## Acceptance Criteria
- [x] Narrow tool/config tests pass:
  ```text
  mix test test/lemmings_os/tools/catalog_test.exs
  mix test test/lemmings_os/tools/adapters/documents_test.exs
  mix test test/lemmings_os/tools/runtime_test.exs
  ```
- [x] `mix format` passes/applies expected formatting.
- [x] `mix precommit` passes with zero warnings/errors.
- [x] Security, code review, test style, and accessibility gates are approved or explicitly waived.
- [x] Release notes do not claim artifact persistence, artifact promotion, remote asset support, templates, email, signatures, or advanced layout support.

## Technical Notes
- If `mix precommit` is expensive or blocked by the environment, record the blocker and the narrower passing checks.
- Human owns git operations.

## Execution Instructions
1. Verify all prior task approvals.
2. Run targeted tests, then `mix format`, then `mix precommit`.
3. Review Compose/deployment notes for Gotenberg.
4. Write final release/rollback notes in this task file.

## Execution Summary

### Work Performed
- [x] Completed Tasks 10 through 15 artifacts and reconciled audit outputs.
- [x] Closed coverage gaps from Task 10 with additional runtime/adapter tests.
- [x] Remediated post-audit code findings:
  - fallback path resolution now app-root based and hardened against symlinked parent-path escapes
  - backend retry/failure/unavailable logs now include hierarchy metadata context
  - removed `String.to_atom/1` argument parsing from documents adapter
  - restored runtime config contract for numeric env validation and empty fallback-path handling
- [x] Added operator docs for document tools and deployment behavior.
- [x] Re-ran focused and final validation commands.

### Outputs Created
- [x] Updated implementation and tests:
  - `lib/lemmings_os/tools/adapters/documents.ex`
  - `config/runtime.exs`
  - `test/lemmings_os/tools/adapters/documents_test.exs`
  - `test/lemmings_os/tools/runtime_test.exs`
  - `test/lemmings_os/config/runtime_documents_config_test.exs`
- [x] Added docs:
  - `docs/features/documents.md`
  - `README.md` (feature-doc link)
- [x] Completed task records:
  - `llms/tasks/0012_print_to_pdf/10_documents_exunit_coverage_closure.md`
  - `llms/tasks/0012_print_to_pdf/11_operator_documentation.md`
  - `llms/tasks/0012_print_to_pdf/12_elixir_code_and_pr_audit.md`
  - `llms/tasks/0012_print_to_pdf/13_elixir_test_style_audit.md`
  - `llms/tasks/0012_print_to_pdf/14_security_audit.md`
  - `llms/tasks/0012_print_to_pdf/15_accessibility_scope_review.md`
  - `llms/tasks/0012_print_to_pdf/16_release_validation.md`

### Assumptions Made
- [x] Default Compose topology is the deployment baseline for this feature.
- [x] `overwrite: false` remains best-effort under concurrent host-writer races for MVP.
- [x] Accessibility impact is no-op because no operator-facing UI templates/components changed.

### Decisions Made
- [x] Accepted review-first workflow for Tasks 12–15 and applied follow-up code remediations before final release validation.
- [x] Kept all document-tool behavior within existing runtime envelope and WorkArea safety boundaries.
- [x] Retained conservative blocked-reference policy (`http(s)://`, `file://`, protocol-relative URLs, `@import`) as MVP scope.

### Blockers
- [x] None.

### Questions for Human
- [x] None.

### Ready for Next Task
- [x] Yes
- [ ] No

### Commands Run And Results
- [x] `mix test test/lemmings_os/tools/catalog_test.exs` (success)
- [x] `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success)
- [x] `mix test test/lemmings_os/tools/runtime_test.exs` (success)
- [x] `mix test test/lemmings_os/config/runtime_documents_config_test.exs` (success)
- [x] `mix format` (success)
- [x] `mix precommit` (success; dialyzer + credo clean)

## Compose / Deployment Validation Notes
- Gotenberg is configured as `gotenberg/gotenberg:8`.
- Default compose keeps Gotenberg private (`expose: "3000"`, no host `ports`).
- App services call internal URL `http://gotenberg:3000`.
- Dev-only host override remains documented through `LEMMINGS_GOTENBERG_URL` and `host.docker.internal`.

## Release Notes (Operator-Facing)
- New tools:
  - `documents.markdown_to_html`
  - `documents.print_to_pdf`
- Required backend: Gotenberg reachable from app services (default internal compose service `gotenberg`).
- Runtime env vars:
  - `LEMMINGS_GOTENBERG_URL`
  - `LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS`
  - `LEMMINGS_DOCUMENTS_PDF_CONNECT_TIMEOUT_MS`
  - `LEMMINGS_DOCUMENTS_PDF_RETRIES`
  - `LEMMINGS_DOCUMENTS_MAX_SOURCE_BYTES`
  - `LEMMINGS_DOCUMENTS_MAX_PDF_BYTES`
  - `LEMMINGS_DOCUMENTS_MAX_FALLBACK_BYTES`
  - `LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH`
  - `LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH`
  - `LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH`
- Safety guarantees:
  - WorkArea-relative path enforcement via `WorkArea.resolve/2`
  - fallback assets constrained to `priv/documents`, regular files, extension checks, size checks, and symlink-component rejection
  - blocked remote/unsafe asset references before backend call
  - atomic output writes (temp file + rename) with cleanup on failure
- Known MVP limitations:
  - no artifact persistence/promotion
  - no remote asset support/network allowlist
  - no templates (EEx/HEEx/Liquid), no email/signature flow, no advanced image layout
  - `overwrite: false` is best-effort under concurrent writer races

## Rollback Notes
- To roll back the feature, revert document-tool catalog/runtime/adapter/docs changes and keep Compose without public Gotenberg exposure.
- If fallback env vars are configured, remove them or unset to return to no-fallback behavior.

## Human Review
Human reviewer gives final sign-off and performs any git operations.

## Post-Completion Addendum (2026-05-03)

### Additional Validated Outputs
- Follow-up implementation/test updates included:
  - `lib/lemmings_os/tools/tool_execution_outputs.ex`
  - `lib/lemmings_os_web/components/instance_components.ex`
  - `lib/lemmings_os_web/live/instance_live.ex`
  - `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`
  - `lib/lemmings_os_web/router.ex`
  - `test/lemmings_os/tools/tool_execution_outputs_test.exs`
  - `test/lemmings_os_web/live/instance_live_test.exs`
  - `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`

### Behavior Alignment Notes
- Workspace output links now use canonical route:
  - `/lemmings/instances/:instance_id/workspace_files/*path`
- Legacy workspace route compatibility remains available:
  - `/lemmings/instances/:instance_id/artifacts/*path`
- Tool cards for successful output-producing tools can expose:
  - workspace download link
  - manual "Promote to Artifact" action

### Release Notes Wording Correction
- Replace "no artifact persistence/promotion" with:
  - document tools write outputs to workspace files first
  - no automatic artifact promotion
  - artifact persistence is available only through explicit/manual promotion flow
