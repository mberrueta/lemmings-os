# Task 07: DETS Snapshot

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for persistent storage and fault tolerance.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.DetsStore` module for best-effort DETS snapshots of idle instance state.

## Objective
Create the DETS store module at `lib/lemmings_os/lemming_instances/dets_store.ex`. This module provides best-effort persistence of ETS runtime state when instances transition to idle. Snapshot failure must NEVER fail the instance -- it is logged and telemetry is emitted, but the instance continues normally. DETS snapshots are written for future rehydration (out of scope for this issue -- snapshots are write-only in v1).

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #10 (DETS snapshot semantics), #9 (Persistence split)
- [ ] Task 06 output (ETS module) - State shape to snapshot

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/dets_store.ex` - DETS store module

## Acceptance Criteria

### Snapshot Trigger
- [ ] Snapshot is triggered on `processing -> idle` and `retrying -> idle` transitions (called by Executor)
- [ ] Captures the full ETS value for the instance

### API Surface
- [ ] `snapshot/2` -- Takes `instance_id` and `state_map`, writes to DETS; returns `:ok` or `{:error, reason}`
- [ ] `delete/1` -- Removes DETS entry for an instance (called on expiry)
- [ ] `read/1` -- Reads a snapshot (for future rehydration); returns `{:ok, state_map}` or `{:error, :not_found}`
- [ ] `init_store/0` -- Opens/creates the DETS file; called at application startup

### Failure Tolerance (Critical)
- [ ] Snapshot failure must NOT propagate -- all errors are caught and logged
- [ ] `snapshot/2` wraps DETS operations in try/rescue
- [ ] On failure: log structured error with `instance_id`, emit telemetry event
- [ ] The calling Executor still transitions to `idle` regardless of snapshot outcome

### File Management
- [ ] File location: configurable via application config, defaults to `priv/runtime/dets/`
- [ ] Directory is created at startup if it does not exist
- [ ] One DETS file globally in v1: `lemming_instance_snapshots.dets`
- [ ] DETS file is opened with `type: :set`

### Cleanup
- [ ] On instance expiry: DETS entry is deleted (best-effort, failure is logged)
- [ ] On instance failure: DETS entry is preserved (may be useful for debugging)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/lemming_instances/ets_store.ex  # Task 06 ETS module (state shape)
```

### Patterns to Follow
- Module-based API wrapping raw DETS operations
- Defensive programming: every DETS call is wrapped in error handling
- Structured logging with hierarchy metadata on failures

### Constraints
- DETS is write-only in v1 -- no rehydration reads happen during normal operation
- DETS state shape must match ETS state shape exactly (same map structure)
- Erlang DETS has a 2GB file size limit -- acceptable for v1
- DETS operations are synchronous and can block -- keep writes minimal
- Do not store secrets in DETS (per ADR-0008)

## Execution Instructions

### For the Agent
1. Read plan.md Frozen Contract #10 for snapshot semantics.
2. Read Task 06 output for the ETS state shape that will be snapshotted.
3. Create `lib/lemmings_os/lemming_instances/dets_store.ex`.
4. Implement `snapshot/2` with full error wrapping.
5. Implement `delete/1` for expiry cleanup.
6. Implement `init_store/0` for startup initialization.
7. Ensure all error paths log and emit telemetry without propagating.
8. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify snapshot failure never propagates to caller.
2. Verify structured logging on failure with instance_id.
3. Verify telemetry event emission on snapshot failure.
4. Verify DETS file path is configurable.
5. Verify cleanup on expiry.
6. Verify state shape matches ETS contract from Frozen Contract #5.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

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
