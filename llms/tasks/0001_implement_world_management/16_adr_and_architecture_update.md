# Task 16: ADR and Architecture Update

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: None
- **Blocks**: Task 17

## Assigned Agent

`tl-architect` - Technical lead architect.

## Agent Invocation

Use `tl-architect` to update the relevant ADRs and architecture docs based on the implemented branch.

## Objective

Update the relevant ADRs and architecture docs so they accurately reflect the implemented persisted-World + bootstrap ingestion design, especially the shift away from a single `config_jsonb` column on `worlds`.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Tasks 01 through 15 outputs
- [ ] `docs/adr/0002-agent-hierarchy-model.md`
- [ ] `docs/adr/0012-tool-policy-authorization-model.md`
- [ ] `docs/adr/0020-hierarchical-configuration-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `docs/adr/0022-deployment-and-packaging-model.md`
- [ ] `docs/architecture.md`

## Expected Outputs

- [ ] ADR and/or architecture doc updates reflecting the implemented design
- [ ] explicit rationale for why the split JSONB design was chosen over the previously considered single `config_jsonb` option
- [ ] concise note on what was considered before and why the new approach is better

## Acceptance Criteria

- [ ] the updates preserve the distinction between persisted domain and bootstrap ingestion
- [ ] the updates explicitly explain the divergence from prior ADR/doc wording
- [ ] the updates include `docs/architecture.md` if it still shows a single config column model
- [ ] the updates explain what was considered before and why the new approach is preferred
- [ ] no speculative ADR churn outside the implemented scope is introduced

## Technical Notes

### Constraints

- Keep updates grounded in the implemented diff
- Explain the `config_jsonb` divergence clearly, not implicitly
- Include `docs/architecture.md` if it still reflects the older single-config-column model
- Prefer targeted ADR/doc updates over unrelated architectural rewrites

## Execution Instructions

### For the Agent

1. Compare the implemented branch to the listed ADRs/docs.
2. Update the relevant docs where the implemented design now differs.
3. Explicitly document why split JSONB columns on `worlds` are better than the previously considered single `config_jsonb` approach for this system direction.

### For the Human Reviewer

1. Review the ADR/doc wording carefully.
2. Confirm the rationale is explicit and technically defensible.
3. Approve before Task 17 begins.
