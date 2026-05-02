# Task 14: Security Audit

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`audit-security` - Security reviewer for authentication, authorization, input validation, secrets, OWASP risks, and PII safety.

## Agent Invocation
Act as `audit-security`. Audit the document tools for path, content, network, backend, and logging risks.

## Objective
Verify that document tools cannot escape WorkAreas, leak host paths or content, fetch remote assets, expose Gotenberg publicly by default, accept agent-controlled backend URLs, or leave partial unsafe outputs.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 02 through 13
- [ ] Source diff, tests, runtime config, and Docker Compose changes

## Expected Outputs
- [ ] Security findings written into this task file, ordered by severity.
- [ ] Path traversal, absolute path, Windows path, backslash path, symlink, fallback file, and output overwrite behavior reviewed.
- [ ] Remote asset and CSS import blocking reviewed.
- [ ] Gotenberg URL control and private exposure reviewed.
- [ ] Logs, telemetry, results, and errors reviewed for document content, host path, fallback path, backend body, and secret leakage.
- [ ] Size-limit and atomic-write behavior reviewed.

## Acceptance Criteria
- [ ] No critical/high findings remain unresolved or unwaived.
- [ ] Validation errors happen before Gotenberg calls.
- [ ] Operator fallback files cannot escape `priv/documents/` or follow symlinks.
- [ ] Gotenberg is not published to the host in default Compose.
- [ ] Security residual risks are documented for release notes.

## Technical Notes
- Treat Gotenberg as an internal rendering backend that should not be directly reachable by agents or public users.
- This audit should include both code and tests.

## Execution Instructions
1. Read the plan and completed implementation.
2. Inspect source, tests, config, and Compose changes.
3. Run security-relevant targeted tests or static checks if useful.
4. Write findings and required fixes in this task file.

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
Human reviewer resolves or waives security findings before Task 15 begins.
