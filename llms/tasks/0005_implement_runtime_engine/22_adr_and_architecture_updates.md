# Task 22: ADR and Architecture Updates

## Status
- **Status**: COMPLETED
- **Approved**: [ ] Human sign-off

## Assigned Agent
`tl-architect` - technical lead architect for ADR and architecture documentation updates.

## Agent Invocation
Act as `tl-architect` following `llms/constitution.md` and update ADR-0021 and architecture docs so they define the correct product and architecture contract for the target runtime phase. Create new ADR sections or documents for the runtime state split, DepartmentScheduler, and instance lifecycle decisions using contract-first language.

## Objective
Rewrite the project's ADR and architecture documentation to be contract-first for the target runtime phase rather than implementation-first. This includes: (1) updating ADR-0021 to define the target-phase runtime schema contract including `lemming_instance_messages`, (2) documenting the v1 status taxonomy as a deliberate Phase 1 subset of ADR-0004, (3) documenting the runtime state split (ETS/DETS/Postgres) as the intended persistence contract for this phase, (4) documenting the DepartmentScheduler as a formal runtime component with clear responsibility and namespace language, (5) documenting `ModelRuntime` as the dedicated model execution boundary with provider behaviour and `Providers.Ollama` as the first provider for this phase, and (6) updating `docs/architecture.md` to describe the runtime engine layer in stable architectural terms.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #1-#17, Terminology Alignment, all design decisions
- [ ] `docs/adr/0004-lemming-execution-model.md` - Richer execution state model (parent of v1 subset)
- [ ] `docs/adr/0008-*` - Lemming persistence model (ETS/DETS/Postgres split)
- [ ] `docs/adr/0019-llm-model-provider-execution-model.md` - Provider contract
- [ ] `docs/adr/0021-core-domain-schema.md` - Current schema ADR to update
- [ ] `docs/architecture.md` - Architecture overview to update
- [ ] Task 02 outputs (`lemming_instance.ex`, `message.ex`, `lemming_instances.ex`) - Useful for identifying temporary implementation divergence, not for defining the contract
- [ ] Task 03 output (`executor.ex`) - Useful for identifying temporary implementation divergence, not for defining the contract
- [ ] Task 04 output (`department_scheduler.ex`) - Useful for identifying temporary implementation divergence, not for defining the contract

## Expected Outputs

- [ ] Modified `docs/adr/0021-core-domain-schema.md` - Updated with `lemming_instance_messages`, updated `lemming_instances` shape, divergence documentation
- [ ] Modified `docs/architecture.md` - Runtime engine layer added
- [ ] Possibly new ADR document for runtime state split (or added as section to ADR-0008)
- [ ] Possibly new ADR document for DepartmentScheduler (or added as section to ADR-0004)

## Acceptance Criteria

### ADR-0021 Updates
- [ ] `lemming_instance_messages` table is documented as a new entity with full column listing
- [ ] `lemming_instances` table shape is updated to match the target Phase 1 contract (`config_snapshot`, `started_at`, `last_activity_at`, `stopped_at`)
- [ ] Deferred items from earlier schema drafts are explicitly marked as deferred or out of scope for this phase:
  - `instance_ref`
  - `parent_instance_id`
  - `last_checkpoint_at`
- [ ] `Message` `total_tokens` and `usage` jsonb fields documented with rationale (provider compatibility cushion)
- [ ] ADR-0021 is written as the schema contract for the target phase, not as a description of the current repo snapshot

### Status Taxonomy Documentation (CRITICAL)
- [ ] The v1 status taxonomy (`created`, `queued`, `processing`, `retrying`, `idle`, `failed`, `expired`) is documented as a **deliberate v1 operational subset** of ADR-0004's richer model
- [ ] This MUST be framed as a simplification, NOT a contradiction of ADR-0004
- [ ] The mapping between v1 statuses and ADR-0004's full taxonomy is explicit
- [ ] The document states that future milestones will expand toward the full ADR-0004 taxonomy

### Runtime State Split
- [ ] The three-tier persistence model is documented: Postgres (durable), ETS (ephemeral active), DETS (best-effort snapshot)
- [ ] The boundary between each tier is explicit (what goes where and why)
- [ ] DETS snapshot semantics documented: write on idle, delete on expiry, failure-tolerant
- [ ] Rehydration is explicitly documented as out of scope for v1
- [ ] Main ADR sections describe the intended phase contract; any current implementation gaps are isolated to a short implementation note if needed

### DepartmentScheduler Documentation
- [ ] DepartmentScheduler is documented as a formal runtime component
- [ ] **Namespace clarification**: module lives at `LemmingsOs.LemmingInstances.DepartmentScheduler` (implementation namespace = `LemmingInstances`), organizational scope = Department
- [ ] This distinction vs `Department.Manager` (Department lifecycle management) is explicitly documented
- [ ] Resource pool keying by resource key (e.g., `ollama:llama3.2`) is documented, not by Department/City
- [ ] DepartmentScheduler language focuses on responsibility, lifecycle, and ownership rather than current wiring details

### Architecture.md Updates
- [ ] Runtime engine layer is added to the architecture overview
- [ ] Shows: Executor, DepartmentScheduler, ResourcePool, ModelRuntime, ETS/DETS as runtime components
- [ ] Shows relationship to existing layers (Contexts, LiveView, PubSub)
- [ ] Shows the Lemming (definition) -> LemmingInstance (runtime) relationship

### ModelRuntime Boundary
- [ ] `ModelRuntime` is documented as a dedicated runtime boundary parallel to future Tool Runtime concerns
- [ ] Executor responsibility is documented as orchestration only; provider-specific HTTP details are outside `LemmingInstances`
- [ ] Provider behaviour and `Providers.Ollama` are documented as the first model provider implementation
- [ ] ModelRuntime language describes the intended architecture for this phase, not a release-status snapshot

### First Input Persistence
- [ ] Documents that the first user input is stored as a `Message` with `role = "user"`, NOT as a column on `lemming_instances`
- [ ] Documents the rationale: single source of truth for transcript content

## Technical Notes

### Relevant Code Locations
```
docs/adr/0004-lemming-execution-model.md       # Parent execution model
docs/adr/0008-*                                 # Persistence model
docs/adr/0019-llm-model-provider-execution-model.md # Provider contract
docs/adr/0021-core-domain-schema.md             # Primary update target
docs/architecture.md                            # Architecture overview
```

### ADR Writing Standard
- ADRs define the product and architecture contract; they are not release notes or implementation status reports
- Main decision sections should describe intended responsibilities, boundaries, lifecycle, invariants, ownership, failure model, and extension points
- If the runtime slice is intentionally limited, describe that as the explicit target phase (`v1`, `Phase 1`, or similar)
- If the code currently diverges from the intended contract, note it only in a short implementation note or deferred-items section
- Update live docs only, not historical task artifacts

### Constraints
- Do NOT turn ADRs into implementation status reports
- Do NOT rewrite ADR-0004 wholesale -- add a clear target-phase section for the runtime slice
- Do NOT remove future-oriented content from ADRs -- mark items as deferred or out of scope for this phase where needed
- Use implementation artifacts only to detect divergence, not to define the architecture
- Temporal marker semantics must match plan.md exactly: `inserted_at` = record creation, `started_at` = process birth, `last_activity_at` = last runtime move, `stopped_at` = terminal only

## Execution Instructions

### For the Agent
1. Read all listed ADRs and architecture.md.
2. Read Task 02-04 outputs only to identify temporary divergence from the intended design.
3. Update ADR-0021 so it defines the target-phase runtime schema contract.
4. Document v1 status taxonomy as deliberate subset of ADR-0004.
5. Document runtime state split (ETS/DETS/Postgres) as a target-phase contract.
6. Document DepartmentScheduler with namespace clarification and stable responsibility language.
7. Update architecture.md with runtime engine layer using contract-first language.
8. If code diverges from the intended contract, isolate that to brief implementation notes or deferred sections.
9. Verify all temporal marker semantics match plan.md.

### For the Human Reviewer
1. Verify v1 status taxonomy is framed as simplification, not contradiction.
2. Verify DepartmentScheduler namespace distinction is documented.
3. Verify divergences from ADR-0021 are explicit.
4. Verify `total_tokens` and `usage` fields are documented.
5. Verify first input persistence rationale is documented.
6. Verify resource pool keying by resource key is documented.
7. Verify architecture.md reflects the runtime layer accurately.

---

## Execution Summary
Updated the runtime architecture documents to align the Phase 1 runtime-engine contract across ADR-0004, ADR-0008, ADR-0021, and `docs/architecture.md`.

### Work Performed
- Updated ADR-0004 to make the v1 status taxonomy an explicit subset of the richer execution model and to document the Phase 1 runtime control components (`Executor`, `DepartmentScheduler`, `ResourcePool`, `ModelRuntime`).
- Updated ADR-0008 to describe the runtime persistence split in concrete Phase 1 runtime terms: durable `LemmingInstance` and transcript rows in Postgres, active coordination state in ETS, and best-effort idle snapshots in DETS.
- Updated ADR-0019 to make the active model-selection contract explicit so scheduler admission and `ModelRuntime` execution consume the same normalized snapshot contract.
- Updated ADR-0021 to define the Phase 1 runtime table contract explicitly, including the `lemming_instance_messages` shape, deferred runtime columns, and the rationale for `total_tokens` and `usage`.
- Rewrote `docs/architecture.md` so the architecture overview reflects the runtime engine layer, the `Lemming` to `LemmingInstance` relationship, the three-tier persistence split, and the `LemmingsOs.Runtime.spawn_session/3` orchestration boundary.
- Updated `docs/adr/0023-error-handling-and-degradation-model.md` and `docs/roadmap.md` to remove stale pre-runtime-engine module references so the broader documentation set stays aligned with the branch terminology.

### Outputs Created
- Modified `docs/adr/0004-lemming-execution-model.md`
- Modified `docs/adr/0008-lemming-persistence-model.md`
- Modified `docs/adr/0019-llm-model-provider-execution-model.md`
- Modified `docs/adr/0023-error-handling-and-degradation-model.md`
- Modified `docs/adr/0021-core-domain-schema.md`
- Modified `docs/architecture.md`
- Modified `docs/roadmap.md`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
- Existing ADR-0019 language for `ModelRuntime` and `Providers.Ollama` was already aligned with the Phase 1 contract | No additional update was needed there once ADR-0004 and `docs/architecture.md` referenced the boundary consistently |
- The runtime state split belongs in ADR-0008 rather than a brand-new ADR for this task | ADR-0008 already owns the persistence-tier contract and was the narrowest place to document the Phase 1 split without scattering the decision |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
- Documented DepartmentScheduler in ADR-0004 instead of creating a new ADR | New standalone ADR for scheduler responsibilities | ADR-0004 is the parent execution-model ADR and already owns the runtime lifecycle contract |
- Kept runtime-state persistence updates inside ADR-0008 instead of introducing another persistence ADR | New standalone ADR for ETS/DETS/Postgres split | ADR-0008 already defines the persistence model, so extending its Phase 1 section keeps the contract centralized |
- Rewrote `docs/architecture.md` rather than patching isolated outdated paragraphs | Minimal point fixes to the existing architecture overview | The old document described a pre-runtime-engine model and would have remained internally inconsistent with smaller edits |

### Blockers Encountered
- None

### Questions for Human
1. None

### Ready for Next Task
- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

---

## Human Review
*[Filled by human reviewer]*

### Review Date
[YYYY-MM-DD]

### Decision
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
