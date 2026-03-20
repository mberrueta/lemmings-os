# Task 14: ADR and Architecture Update

## Status

- **Status**: COMPLETE
- **Approved**: [X]
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

## Execution Summary

### Work Performed

- **`docs/adr/0017-runtime-topology-city-execution-model.md`**:
  - Added section 5.1 "Shipped City Runtime Model" documenting startup self-registration, heartbeat-backed liveness, runtime identity contract (`node_name` as full BEAM `name@host`), and explicit enumeration of all deferred capabilities.
  - Updated section 12 (Non-Goals) to include distributed Erlang clustering, automatic discovery, secure remote onboarding, and Erlang cookie storage as explicitly out of scope.
  - Updated section 13 (Future Extensions) to note that clustering, secure remote attachment, and remote health polling require future ADRs.
  - Updated status line to "Accepted (narrowed 2026-03-19)".

- **`docs/adr/0020-hierarchical-configuration-model.md`**:
  - Updated section 5 (Configuration Storage) to document that both `worlds` and `cities` use four split JSONB columns with shared Ecto embedded schema modules, replacing the prior `config_jsonb` description.
  - Replaced section 7 (Configuration Resolver) with 7.1 (Shipped resolver interface) documenting the pure in-memory `resolve/1` pattern accepting preloaded structs, and 7.2 (Deferred resolver capabilities) listing deny-dominant merge, Department/Lemming Type scopes, ID-based interface, ETS caching, and `Config.Validator` as not yet implemented.
  - Updated section 8 (Runtime Caching) to note it is not yet implemented.
  - Updated status line to "Accepted (narrowed 2026-03-19)".

- **`docs/adr/0021-core-domain-schema.md`**:
  - Updated the CITIES entity in the Mermaid diagram to match the shipped schema: added `slug`, `host`, `distribution_port`, `epmd_port`, `last_seen_at`, and four split config columns; removed `config_jsonb` and `last_heartbeat_at`.
  - Expanded the City entity responsibility section with "Shipped schema" subsection documenting all columns, "Runtime identity" documenting `node_name` as canonical identity, and "Status vs liveness" documenting the separation.
  - Updated the note about split JSONB to cover both worlds and cities.
  - Added note that Department and Lemming persistence remain deferred.
  - Updated Implementation Notes to show shipped module names (`LemmingsOs.Worlds.World`, `LemmingsOs.Cities.City`) and explain divergence from prior `LemmingsOs.Schema.*` naming.
  - Updated status line to "Accepted (narrowed 2026-03-19)".

- **`docs/adr/0022-deployment-and-packaging-model.md`**:
  - Replaced the Clustering Model section to state that distributed Erlang clustering is not shipped; documented the self-registration and heartbeat model; listed deferred clustering capabilities.
  - Updated the Deployment Architecture section to replace "Cities join the World cluster using Erlang distribution" with the actual self-registration model.
  - Replaced the Multi-City Deployment section with the shipped compose demo topology, including env var identity contract and stale detection behavior.
  - Updated the Implementation Notes compose description to match the shipped `docker-compose.yml`.
  - Updated status line to "Accepted (narrowed 2026-03-19)".

- **`docs/architecture.md`**:
  - Updated City hierarchy description to mention real persistence, heartbeat-backed liveness, and that clustering is not yet shipped.
  - Replaced `World Registry` section with `World Context` and `Config Resolver` sections matching shipped modules.
  - Replaced `City Supervisor` section with `City Runtime`, `City Heartbeat`, and planned `City Supervisor` sections.
  - Updated City node failure model to describe heartbeat-staleness detection instead of distributed Erlang `:DOWN` monitoring.
  - Updated Data Model section with full shipped `worlds` and `cities` column lists; separated persisted hierarchy from target (not yet persisted) hierarchy.
  - Extended Key Design Decisions table with ADR 0017, 0020, 0021, 0022.
  - Extended Future Work section with deferred items: clustering, secure attachment, Department/Lemming persistence, config cache, deny-dominant merge.

### Deferred Items Documented

Each deferred item is noted in the relevant ADR and in `docs/architecture.md`:

- Distributed Erlang clustering (ADR 0017 section 5.1, 12, 13; ADR 0022 Clustering Model)
- Automatic City discovery / membership protocol (ADR 0017 section 5.1, 12)
- Remote health polling (ADR 0017 section 5.1, 13)
- Failover and Lemming migration (ADR 0017 section 5.1)
- Secure remote City attachment and secret distribution (ADR 0017 section 5.1; ADR 0022 Clustering Model; architecture.md Future Work)
- Erlang cookie management in cities table (ADR 0017 section 5.1, 12)
- Deny-dominant merge semantics in resolver (ADR 0020 section 7.2; architecture.md Future Work)
- ETS config cache (ADR 0020 section 8; architecture.md Future Work)
- Config.Validator module (ADR 0020 section 7.2)
- Department and Lemming persistence (ADR 0021; architecture.md)

### Wording Still Needing Later ADR Work

- ADR 0017 sections 6-10 (Isolation Boundary through Execution Flow) still describe the Secret Bank, Tool Runtime isolation, and cross-City communication in aspirational terms. These are architecturally sound but reference components not yet implemented. A future pass should narrow these once the Tool Runtime and Secret Bank ship.
- ADR 0020 sections 6, 9, 10, 11 (Merge Semantics, Propagation, Scope Matrix, Versioning) describe deny-dominant merge, cluster-wide cache invalidation, config propagation, and scope matrix enforcement that are not yet implemented. These are correct architectural targets but will need narrowing once Department/Lemming config and deny-dominant merge ship.
- ADR 0022 still references DETS persistent volumes and the Secret Bank in the container model; these are valid architectural targets but the DETS idle snapshot store and Secret Bank are not yet implemented.

### Ready for Next Task

- [x] All outputs complete
- [x] Summary documented
