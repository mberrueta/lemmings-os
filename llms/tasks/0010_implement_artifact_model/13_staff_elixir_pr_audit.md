# Task 13: Staff Elixir PR Audit

## Status
- **Status**: ✅ COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent
`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix correctness, design quality, security, performance, logging, and tests.

## Agent Invocation
Act as `audit-pr-elixir`. Perform a staff-level Elixir/Phoenix review of the full Artifact implementation and implement focused fixes for confirmed findings.

## Objective
Catch correctness, design, scope, performance, logging, and test-quality issues before release validation, explicitly checking constitution and Elixir style compliance.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0010_implement_artifact_model/plan.md`
- [x] Tasks 01-12 outputs
- [x] Full implementation diff

## Expected Outputs
- [x] Findings-first PR audit documented in this task file.
- [x] Focused fixes for confirmed high/medium findings where safe to implement.
- [x] Regression tests for fixes when executable logic changes.
- [x] Explicit checklist result for constitution/style-guide compliance.

## Acceptance Criteria
- [x] Verify `llms/constitution.md` MUST rules: explicit World scoping, tuple returns, `filter_query/2` for list APIs, `@doc` on important public functions, tests for executable logic, no hardcoded secrets, no unsafe atom creation.
- [x] Verify `llms/coding_styles/elixir.md`: context boundaries, one module per file, grouped aliases, structs not map access, `with`/pattern matching where appropriate, no web-to-Repo/schema bypass, safe logging/telemetry metadata.
- [x] Verify `llms/coding_styles/elixir_tests.md`: factories, deterministic data, no external network, stable selectors, no fixture-style helpers, no broad raw HTML assertions except leakage checks.
- [x] Review migration/index performance and query plans at code level.
- [x] Review storage and download failure modes.
- [x] Review observability payloads and SecretBank audit results.
- [x] Run narrow tests for any fixes made.

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
### Summary
- Staff-level audit completed across Artifact context, promotion/storage, download controller, LiveView integration, migration, and artifact-specific tests.
- One **medium** issue was confirmed and fixed in-scope.
- No blockers were found after fixes; all relevant checks are green.
- Merge recommendation for this task scope: **APPROVE**.

### Risk Assessment
- **Low** after fixes: explicit world/scope boundaries, tuple-return APIs, no unsafe atom creation, and passing targeted tests + `mix precommit`.

### Findings
1. **MAJOR (fixed)**: HEEx template used raw EEx blocks (`<%= ... %>`) in Artifact tool cards, violating project HEEx rules and risking further template drift.
   - Where: `lib/lemmings_os_web/components/instance_components.ex` around `tool-execution-summary` and payload `<pre>` blocks (`tool-execution-args/result/error` IDs near lines 276, 514, 524, 534).
   - Why it matters: constitution/style explicitly require HEEx interpolation and `:if/:for`, not EEx blocks in templates.
   - Fix: replaced EEx `if/else` with HEEx `:if` spans and replaced EEx payload interpolation with HEEx `{...}` interpolation.

### Compliance Checklist Results
- Constitution MUST checks: **PASS**
  - Explicit world/scope boundaries: context/controller calls are scope-gated (`Artifacts.get_artifact_download(instance, artifact_id)` and scoped query filters).
  - Tuple return contracts: Artifact context/promotion/storage APIs return tuples for failure paths.
  - `filter_query/2` present for list/get query composition.
  - Important public functions are documented with `@doc`.
  - No hardcoded secrets found in Artifact implementation.
  - No `String.to_atom/1` on user input found.
- `llms/coding_styles/elixir.md`: **PASS**
  - Context boundaries respected; web layer calls contexts.
  - One-module-per-file respected.
  - Logging metadata is structured and scope-aware in Artifact promotion failure path.
- `llms/coding_styles/elixir_tests.md`: **PASS**
  - Factory-driven setup retained.
  - Deterministic tests; no external network.
  - LiveView tests use stable selectors and outcome assertions.

### Migration/Performance Notes
- Migration indexes cover dominant lookups:
  - world scope
  - hierarchy scope
  - instance/provenance references
  - scope+filename collision checks
- Residual performance concern (not changed in this task): durable download currently reads full file into memory before response in `InstanceArtifactController` (`File.read/1`), which can pressure memory for large artifacts.

### Storage/Download Failure Mode Notes
- Path traversal and invalid refs are fail-closed in `LocalStorage` + controller behavior.
- Status gating (`ready` only) and scope checks happen before durable file resolution.

### Observability/SecretBank Notes
- Promotion failure logging now uses reason tokens and avoids raw path leakage.
- Security task output (Task 11) findings remain addressed; no SecretBank coupling added in Artifact flow.

### Files Changed
- `lib/lemmings_os_web/components/instance_components.ex`

### Validation Commands
- `mix format lib/lemmings_os_web/components/instance_components.ex`
- `mix test test/lemmings_os_web/live/instance_live_test.exs`
- `mix test test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`
- `mix precommit`

### Validation Results
- `test/lemmings_os_web/live/instance_live_test.exs`: pass
- `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`: pass
- `mix precommit`: pass (Dialyzer + Credo clean)

### Residual Risks
- Durable download path still uses `File.read/1` + `send_resp/3`; consider a follow-up to stream/sendfile for large artifact safety.
