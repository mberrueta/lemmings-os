# Task 14: Source File Security Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-security` - Security reviewer for authz, input validation, secrets, and data safety.

## Agent Invocation
Act as `audit-security`. Audit source-file Knowledge implementation for security and privacy risks and apply focused fixes for confirmed findings.

## Objective
Verify no unauthorized scope access, no path/content leakage, and no unsafe provider/extraction data exposure.

## Inputs Required
- [ ] Tasks 01-13 approved
- [ ] Diff for source-file feature branch

## Expected Outputs
- [ ] Security findings report with severity and file references.
- [ ] Focused fixes for confirmed P0/P1 issues.
- [ ] Residual risk notes for human sign-off.

## Acceptance Criteria
- [ ] Scope authorization for search/read is server-enforced.
- [ ] Logs/events/tool outputs are free from forbidden sensitive fields.
- [ ] Upload/extraction/indexing inputs are validated with safe failure paths.

## Constraints
- Avoid speculative churn; prioritize confirmed exploitable issues.

## Approval Gate
Human reviewer must approve this task before Task 15 begins.

## Human Review
*[Filled by human reviewer]*
