# Task 14: ADR and Architecture Update

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 13
- **Blocks**: Task 15

## Assigned Agent

`tl-architect` - Technical lead architect.

## Agent Invocation

Use `tl-architect` to update the relevant ADRs and architecture docs based on the implemented City branch.

## Objective

Reconcile the ADRs and architecture docs with the shipped City model, including full BEAM `node_name`, split City config buckets, heartbeat-backed liveness, and the explicitly deferred remote-attachment security design.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 13 outputs
- [ ] `docs/architecture.md`
- [ ] `docs/adr/0017-runtime-topology-city-execution-model.md`
- [ ] `docs/adr/0020-hierarchical-configuration-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `docs/adr/0022-deployment-and-packaging-model.md`

## Expected Outputs

- [ ] targeted ADR/doc updates reflecting the implemented City design
- [ ] explicit rationale where implementation narrows prior ADR wording
- [ ] explicit note that secure remote city attachment and secret distribution remain deferred to a later ADR/security design
- [ ] optional note that future attachment may require persisted encrypted secret material, but no mechanism is decided in this issue

## Acceptance Criteria

- [ ] docs match the implemented branch rather than earlier broader ADR wording
- [ ] the distinction between admin status and heartbeat liveness is explicit
- [ ] the docs freeze `node_name` as full BEAM identity
- [ ] the docs do not imply secure remote onboarding is solved or architecturally finalized in this issue
- [ ] no unrelated ADR churn is introduced

## Technical Notes

### Constraints

- Keep updates grounded in the actual implementation
- Explain divergences explicitly, not implicitly
- Preserve the repo’s architecture-first style

## Execution Instructions

### For the Agent

1. Compare the implemented branch to the listed ADRs/docs.
2. Update only the docs needed to match the shipped City design.
3. Make the future security direction explicit without broadening current scope.
4. Record any wording that still needs later ADR work.

### For the Human Reviewer

1. Review the wording carefully for architectural precision.
2. Confirm the future security direction is explicit but still deferred.
3. Confirm the docs no longer leave `node_name` or liveness semantics ambiguous.
4. Approve before Task 15 begins.
