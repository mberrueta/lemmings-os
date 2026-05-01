# Task 11: Security and SecretBank Audit

## Status
- **Status**: ✅ COMPLETE 
- **Approved**: [x] Human sign-off

## Assigned Agent
`audit-security` - Security reviewer for authorization, input validation, secrets management, OWASP risks, and data leakage.

## Agent Invocation
Act as `audit-security`. Review the implemented Artifact slice and implement focused fixes for security issues found.

## Objective
Verify the Artifact implementation preserves scope isolation, path safety, privacy, logging/event safety, LLM context safety, and Secret Bank boundaries.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-10 outputs
- [ ] Implemented code/tests/docs

## Expected Outputs
- [x] Security audit findings documented in this task file.
- [x] Focused fixes for confirmed high/medium findings where safe to implement in-scope.
- [x] Added/updated regression tests for security fixes.
- [x] Explicit SecretBank call-site inventory.

## Acceptance Criteria
- [x] Run and document `rg "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test`.
- [x] Confirm no Artifact implementation code calls `LemmingsOs.SecretBank` or resolves runtime secrets.
- [x] Confirm Artifact context does not inspect contents for secrets and does not integrate with Secret Bank.
- [x] Confirm download/open checks visible scope before resolving `storage_ref` to a path.
- [x] Confirm events/logs exclude file contents, storage refs, resolved paths, raw workspace paths, notes by default, full metadata dumps, and secret values.
- [x] Confirm artifact contents are not automatically added to LLM context.
- [x] Confirm all path inputs reject traversal/symlink escapes and fail closed.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/artifacts*             # Artifact backend implementation
lib/lemmings_os_web/controllers/       # Download/open route
lib/lemmings_os_web/live/instance_live* # Promotion UI
lib/lemmings_os/secret_bank*           # Approved Secret Bank boundary, should not be used by Artifacts
lib/lemmings_os/lemming_instances/executor/context_messages.ex # LLM context safety check
```

### Constraints
- Do not broaden scope into a general auth system.
- Do not add secret scanning.
- Do not call Secret Bank from Artifact code.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Audit code paths and run the required `rg` inventory.
3. Implement focused fixes for confirmed issues.
4. Add regression tests for fixes.
5. Run narrow security-related tests.
6. Document findings, fixes, residual risks, and commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Review any residual risk and decide whether follow-up tasks are needed.
2. Approve before Task 12 begins.

---

## Execution Summary
### SecretBank Inventory (`rg "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test`)
- Matches were found in Secret Bank modules, world/city/department/lemming secret UI surfaces, and connection/tool runtime adapters.
- No Artifact module matches:
  - No matches in `lib/lemmings_os/artifacts.ex`
  - No matches in `lib/lemmings_os/artifacts/*`
  - No matches in `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`
  - No matches in Artifact tests

### Findings
1. **Medium**: Artifact promotion failure logs leaked raw relative paths and raw inspected reasons.
   - Location: `lib/lemmings_os_web/live/instance_live.ex`
   - Risk: path disclosure in logs; accidental detail leakage from `inspect(reason)`.
   - Fix: replaced with reason token logging only (`reason_token=<token>`), removed raw relative path from message.
2. **Medium**: Filename control characters were accepted by local storage filename validation.
   - Location: `lib/lemmings_os/artifacts/local_storage.ex`
   - Risk: unsafe filename propagation into headers/logging/display.
   - Fix: reject ASCII control characters (`0x00-0x1F`, `0x7F`) in filenames.
3. **Medium**: Download `content-disposition` used basename + quote stripping only.
   - Location: `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`
   - Risk: malformed legacy filenames could cause unsafe header values.
   - Fix: strip control characters from filename before header composition.

### Confirmations Against Acceptance Criteria
- **Secret Bank boundary**: Artifact implementation does not call `LemmingsOs.SecretBank` and does not resolve runtime secrets.
- **No secret scanning integration**: Artifact flow does not inspect artifact file contents for secrets.
- **Scope-before-path ordering (download route)**:
  1. Resolve world + instance scope.
  2. `Artifacts.get_artifact_download(instance, artifact_id)` enforces visible scope + `ready` status.
  3. Only then `LocalStorage.resolve_storage_ref(storage_ref)` resolves path.
- **LLM context safety**:
  - `Executor.ContextMessages` and finalization payload include summarized metadata only.
  - Artifact file contents are not auto-loaded into model context.
- **Path safety fail-closed**:
  - Traversal, absolute paths, and symlink escapes are rejected in:
    - `LemmingsOs.LemmingInstances.artifact_absolute_path/2`
    - `LemmingsOs.Artifacts.LocalStorage.resolve_storage_ref/1`
    - `LemmingsOs.Artifacts.LocalStorage.store_copy/4`

### Regression Tests Added/Updated
- `test/lemmings_os_web/live/instance_live_test.exs`
  - `S08m2`: verifies promotion failure logs omit raw relative path and include only reason token.
- `test/lemmings_os/artifacts/local_storage_test.exs`
  - expanded unsafe filename set to include `\n` and `\r`.
- `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`
  - `DL01b`: verifies control chars are stripped from `content-disposition` filename.

### Commands Run
- `rg -n "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test`
- `mix format lib/lemmings_os_web/live/instance_live.ex lib/lemmings_os/artifacts/local_storage.ex lib/lemmings_os_web/controllers/instance_artifact_controller.ex test/lemmings_os/artifacts/local_storage_test.exs test/lemmings_os_web/controllers/instance_artifact_controller_test.exs test/lemmings_os_web/live/instance_live_test.exs`
- `mix test test/lemmings_os/artifacts/local_storage_test.exs`
- `mix test test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`
- `mix test test/lemmings_os_web/live/instance_live_test.exs`
- `MIX_ENV=test mix precommit`

### Validation Results
- All targeted tests passed.
- `MIX_ENV=test mix precommit` passed (Dialyzer + Credo clean).

### Residual Risks
- Existing generic executor/tool lifecycle logging still records tool relative paths for runtime observability (outside Artifact-specific code paths). If policy requires global path suppression, that should be a separate cross-cutting task.
