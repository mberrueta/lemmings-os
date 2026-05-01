# Task 11: Security and SecretBank Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

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
- [ ] Security audit findings documented in this task file.
- [ ] Focused fixes for confirmed high/medium findings where safe to implement in-scope.
- [ ] Added/updated regression tests for security fixes.
- [ ] Explicit SecretBank call-site inventory.

## Acceptance Criteria
- [ ] Run and document `rg "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test`.
- [ ] Confirm no Artifact implementation code calls `LemmingsOs.SecretBank` or resolves runtime secrets.
- [ ] Confirm Artifact context does not inspect contents for secrets and does not integrate with Secret Bank.
- [ ] Confirm download/open checks visible scope before resolving `storage_ref` to a path.
- [ ] Confirm events/logs exclude file contents, storage refs, resolved paths, raw workspace paths, notes by default, full metadata dumps, and secret values.
- [ ] Confirm artifact contents are not automatically added to LLM context.
- [ ] Confirm all path inputs reject traversal/symlink escapes and fail closed.

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
*[Filled by executing agent after completion]*
