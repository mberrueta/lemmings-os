# Task 13: Staff Elixir PR Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix correctness, design quality, security, performance, logging, and tests.

## Agent Invocation
Act as `audit-pr-elixir`. Perform a staff-level Elixir/Phoenix review of the full Artifact implementation and implement focused fixes for confirmed findings.

## Objective
Catch correctness, design, scope, performance, logging, and test-quality issues before release validation, explicitly checking constitution and Elixir style compliance.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-12 outputs
- [ ] Full implementation diff

## Expected Outputs
- [ ] Findings-first PR audit documented in this task file.
- [ ] Focused fixes for confirmed high/medium findings where safe to implement.
- [ ] Regression tests for fixes when executable logic changes.
- [ ] Explicit checklist result for constitution/style-guide compliance.

## Acceptance Criteria
- [ ] Verify `llms/constitution.md` MUST rules: explicit World scoping, tuple returns, `filter_query/2` for list APIs, `@doc` on important public functions, tests for executable logic, no hardcoded secrets, no unsafe atom creation.
- [ ] Verify `llms/coding_styles/elixir.md`: context boundaries, one module per file, grouped aliases, structs not map access, `with`/pattern matching where appropriate, no web-to-Repo/schema bypass, safe logging/telemetry metadata.
- [ ] Verify `llms/coding_styles/elixir_tests.md`: factories, deterministic data, no external network, stable selectors, no fixture-style helpers, no broad raw HTML assertions except leakage checks.
- [ ] Review migration/index performance and query plans at code level.
- [ ] Review storage and download failure modes.
- [ ] Review observability payloads and SecretBank audit results.
- [ ] Run narrow tests for any fixes made.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/artifacts*             # Backend implementation
lib/lemmings_os_web/controllers/       # Download implementation
lib/lemmings_os_web/live/instance_live* # UI integration
test/                                  # Test coverage
priv/repo/migrations/                  # Migration/index review
```

### Constraints
- Findings must be ordered by severity with file/line references.
- Do not perform git operations.
- Do not broaden the feature scope.

## Execution Instructions

### For the Agent
1. Read all inputs listed above before reviewing code.
2. Review implementation against source plan, constitution, and coding style docs.
3. Document findings first.
4. Implement focused fixes only for confirmed in-scope issues.
5. Run narrow tests for fixes.
6. Document residual risks, files changed, and commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Review findings and fixes.
2. Decide if additional implementation tasks are needed.
3. Approve before Task 14 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
