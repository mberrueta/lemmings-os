# Task 11: Operator Documentation

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer aligned with actual application behavior.

## Agent Invocation
Act as `docs-feature-documentation-author`. Document the document tools and Gotenberg deployment behavior after implementation is complete.

## Objective
Update operator/developer documentation for `documents.markdown_to_html`, `documents.print_to_pdf`, required Gotenberg configuration, supported formats, WorkArea boundaries, fallback assets, safety limits, and non-goals.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 02 through 10
- [ ] Existing README/docs files relevant to tool runtime or deployment
- [ ] `docker-compose.yml`
- [ ] `.env.example`

## Expected Outputs
- [ ] Documentation lists both document tools and their supported inputs.
- [ ] Documentation explains that files must live in the instance WorkArea and outputs remain in the WorkArea.
- [ ] Documentation explains Gotenberg URL/timeout/retry/size-limit env vars.
- [ ] Documentation explains fallback header/footer/CSS env vars and `priv/documents/` constraints.
- [ ] Documentation clearly states that Gotenberg must not be publicly exposed.
- [ ] Documentation states remote assets, templates, artifact persistence, artifact promotion, email, signatures, and advanced layout are out of scope.

## Acceptance Criteria
- [ ] Docs match actual implemented env names and defaults.
- [ ] Docs do not imply generated PDFs are persisted or promoted as Artifacts.
- [ ] Docs do not include secrets or generated credentials.
- [ ] Any examples use WorkArea-relative paths only.

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
Human reviewer confirms documentation accuracy before Task 12 begins.
