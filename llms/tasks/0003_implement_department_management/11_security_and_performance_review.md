# Task 11: Security and Performance Review

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 10
- **Blocks**: Task 12
- **Estimated Effort**: M

## Assigned Agent

audit-pr-elixir - staff-level Elixir/Phoenix reviewer for correctness, security, performance, and testing gaps.

## Agent Invocation

Act as audit-pr-elixir following llms/constitution.md and review the Department branch for security, performance, correctness, and coverage risks.

## Objective

Perform the formal Department feature review before ADR/doc work and final validation.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] outputs from Tasks 01-10
- [ ] relevant source and tests touched by the feature

## Expected Outputs

- [ ] review findings ordered by severity
- [ ] explicit callouts on security, performance, and testing gaps
- [ ] recommendation on whether the branch is ready for doc/update work

## Acceptance Criteria

- [ ] review covers preload/N+1 risk
- [ ] review covers delete guard honesty and failure modes
- [ ] review covers notes/XSS safety and input normalization
- [ ] review covers settings-scope overreach risk
- [ ] review explicitly states whether residual risks remain

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os/
lib/lemmings_os_web/
test/
```

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the full diff and touched architecture paths.
2. Prioritize correctness, security, and performance findings over style notes.
3. State clearly if there are no findings.

### For the Human Reviewer

1. Resolve or explicitly accept review findings before moving on.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- Reviewed the Department implementation across schema, context, resolver, page-data snapshots, LiveView surfaces, and tests.
- Audited the branch for correctness, security, performance, and coverage risks with emphasis on preload/N+1 behavior, delete guard honesty, notes/XSS safety, and settings-scope boundaries.
- Verified the current branch state against the full automated suite and `mix precommit`.

### Outputs Created

- Formal review findings captured in this task summary
- Branch readiness recommendation for Task 12+ follow-up work

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| The current repository state is the review target, even though individual task files still show blocked metadata | Tasks 01-10 are materially implemented and validated in the branch |
| Review findings should prioritize correctness, security, and performance over stylistic cleanup | That is the explicit scope of Task 11 |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Treated architecture boundary violations as review findings, not merely style notes | Ignoring them because behavior currently works | The project constitution explicitly requires the web layer to call through contexts rather than repos |
| Reported only actionable findings with user-visible or scaling impact | Exhaustive style audit | Keeps the review high-signal and aligned with the task objective |

### Blockers Encountered

- None. The branch is in a fully runnable/testable state for review.

### Questions for Human

1. Do you want the two findings below addressed before moving to Task 12, or should they be accepted as follow-up debt for a separate cleanup pass?

### Ready for Next Task

- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

### Review Findings

1. Medium: `HomeDashboardSnapshot.build_topology_card_meta/1` does an N+1 department scan per city.
   Location: `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`
   The function loads all cities for a world and then calls `Departments.list_departments/3` once per city, which turns the home dashboard topology card into `1 + city_count` queries. This is acceptable at toy scale but will degrade predictably as city count grows. The feature is functionally correct today, but the topology summary should eventually be backed by aggregate queries or a dedicated read model.

2. Medium: `DepartmentsLive` reaches into `Repo.preload/2` directly instead of going through a context-owned retrieval API.
   Location: `lib/lemmings_os_web/live/departments_live.ex`
   `preload_department_detail/1` calls `Repo.preload(department, [:world, city: [:world]])` from the LiveView. That violates the project rule that web layers call contexts rather than repos. It is not a user-visible bug right now, but it weakens the architecture boundary and makes future preload behavior easier to scatter across the web layer.

### Security / Correctness / Performance Notes

- Security: no direct XSS finding in the Department notes/tag surfaces.
  Notes are stored as plain strings and rendered through HEEx, so they remain escaped by default. Tag normalization happens on write via `Helpers.normalize_tags/1`, and there is no HTML rendering path for notes.
- Delete guard honesty: acceptable.
  The UI exposes delete, but both current denial modes are now covered and return honest operator-facing errors rather than pretending deletion succeeded.
- Settings-scope overreach: acceptable for V1.
  The settings UI is clearly bounded to a small editable subset and distinguishes effective config from local overrides without claiming per-field provenance tracing.
- Residual risk remains: yes.
  The two medium findings above are still open. Neither blocks local docs work mechanically, but both should be consciously accepted or fixed before final PR audit if we want the branch to be fully aligned with project architecture/performance expectations.

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] ✅ APPROVED - Proceed to next task
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
