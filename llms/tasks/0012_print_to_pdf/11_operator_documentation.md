# Task 11: Operator Documentation

## Status
- **Status**: COMPLETE
- **Approved**: [ ]

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer aligned with actual application behavior.

## Agent Invocation
Act as `docs-feature-documentation-author`. Document the document tools and Gotenberg deployment behavior after implementation is complete.

## Objective
Update operator/developer documentation for `documents.markdown_to_html`, `documents.print_to_pdf`, required Gotenberg configuration, supported formats, WorkArea boundaries, fallback assets, safety limits, and non-goals.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Tasks 02 through 10
- [X] Existing README/docs files relevant to tool runtime or deployment
- [X] `docker-compose.yml`
- [X] `.env.example`

## Expected Outputs
- [X] Documentation lists both document tools and their supported inputs.
- [X] Documentation explains that files must live in the instance WorkArea and outputs remain in the WorkArea.
- [X] Documentation explains Gotenberg URL/timeout/retry/size-limit env vars.
- [X] Documentation explains fallback header/footer/CSS env vars and `priv/documents/` constraints.
- [X] Documentation clearly states that Gotenberg must not be publicly exposed.
- [X] Documentation states remote assets, templates, artifact persistence, artifact promotion, email, signatures, and advanced layout are out of scope.

## Acceptance Criteria
- [X] Docs match actual implemented env names and defaults.
- [X] Docs do not imply generated PDFs are persisted or promoted as Artifacts.
- [X] Docs do not include secrets or generated credentials.
- [X] Any examples use WorkArea-relative paths only.

## Technical Notes
- Keep docs concise and operator-facing.
- If there is no central tool-runtime doc yet, add the smallest appropriate section to the nearest existing operational document.

## Execution Instructions
1. Read implementation and config before writing docs.
2. Update only relevant documentation files.
3. Run any docs-specific checks if available, otherwise include manual review notes.
4. Record changed docs and validation in this task file.

## Execution Summary

### Work Performed
- [X] Added `docs/features/documents.md` with operator/developer documentation for:
  - `documents.markdown_to_html` and `documents.print_to_pdf`
  - supported source/output formats and key args
  - WorkArea-relative path requirements and output boundary
  - fallback header/footer/CSS precedence and `priv/documents/` trust constraints
  - documents/Gotenberg env vars with defaults from `config/runtime.exs`
  - deployment safety requirement that Gotenberg must not be publicly exposed
  - full non-goals list from `plan.md`
- [X] Updated root README feature-doc list to include the new Documents Tools guide.

### Outputs Created
- [X] Updated `docs/features/documents.md`
- [X] Updated `README.md`
- [X] Updated this task file with completion and validation notes

### Assumptions Made
- [X] The most discoverable location for this feature documentation is `docs/features/` with a README link, instead of extending city/department operator guides.

### Decisions Made
- [X] Kept documentation scope limited to document tools and Gotenberg deployment behavior.
- [X] Documented actual shipped behavior only (including blocked remote asset references and no Artifact promotion).

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format` (success)
- [X] `mix precommit` (success; dialyzer and credo passed)

## Human Review
Human reviewer confirms documentation accuracy before Task 12 begins.

## Post-Completion Addendum (2026-05-03)

- Follow-up UI/runtime behavior now exposes workspace output links and manual Artifact promotion actions for successful tool outputs (including documents tools).
- Documentation intent is unchanged on core tool behavior: document outputs are created in the WorkArea first and are **not auto-promoted**.
- Acceptance wording should be interpreted as:
  - docs must not imply automatic Artifact persistence/promotion by the tools themselves
  - explicit/manual promotion remains a separate operator action
