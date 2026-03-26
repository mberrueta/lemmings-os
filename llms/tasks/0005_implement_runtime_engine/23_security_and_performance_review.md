# Task 23: Security and Performance Review

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir` - staff-level PR reviewer for Elixir/Phoenix backends focusing on correctness, security, performance, and OTP supervision.

## Agent Invocation
Act as `audit-pr-elixir` following `llms/constitution.md` and perform a security and performance review of the entire runtime engine implementation before the final PR audit.

## Objective
Review all new code introduced by the runtime engine feature for security vulnerabilities, performance concerns, OTP supervision correctness, and design quality. This is a pre-PR audit focused on catching issues before the final review. Produce a written report of findings with severity levels and recommended fixes.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Full spec and frozen contracts
- [ ] All new and modified files from Tasks 01-23
- [ ] `lib/lemmings_os/lemming_instances/` - All new backend modules
- [ ] `lib/lemmings_os_web/live/instance_live.ex` - New LiveView
- [ ] `lib/lemmings_os/application.ex` - Supervisor tree changes
- [ ] `test/` - All new tests
- [ ] `mix.exs` - Dependency changes

## Expected Outputs

- [ ] New `llms/tasks/0005_implement_runtime_engine/security_review.md` - Audit findings report

## Acceptance Criteria

### Security Review
- [ ] No secrets in code, config snapshots, or logs
- [ ] No user-supplied input used in atom creation (process names use UUIDs via Registry)
- [ ] No SQL injection vectors (all queries use Ecto parameterization)
- [ ] No raw provider error payloads exposed to the UI
- [ ] Config snapshots do not leak sensitive data (no API keys, no secrets)
- [ ] World scoping enforced on all context APIs (no cross-World data access)
- [ ] PubSub topics cannot be guessed to leak cross-World data
- [ ] No `Code.eval_string`, `apply/3` with user input, or other code injection vectors
- [ ] Req HTTP calls do not follow redirects to arbitrary hosts

### Performance Review
- [ ] ETS access patterns are efficient (no full table scans)
- [ ] No N+1 queries in context list functions (first user message preview uses join, not per-row query)
- [ ] Resource pool does not hold locks during model execution (slot acquired before, released after)
- [ ] PubSub broadcasts are targeted (specific topics, not global)
- [ ] No unbounded memory growth (conversation context accumulation has a reasonable future compaction seam)
- [ ] DETS snapshot is best-effort and does not block the executor
- [ ] LiveView assigns are minimal (no full conversation history stored as assigns if it can be streamed)

### OTP Supervision Correctness
- [ ] DynamicSupervisor strategy is appropriate for executor processes
- [ ] Executor crash does not cascade to other executors or the scheduler
- [ ] Scheduler crash does not terminate running executors
- [ ] ETS table ownership: table survives individual executor crashes
- [ ] Process registration via Registry, not dynamic atoms
- [ ] GenServer timeouts and idle timers use appropriate mechanisms (Process.send_after, not Process.sleep)
- [ ] No blocking calls in GenServer callbacks (model HTTP calls are async or handled correctly)

### Design Quality
- [ ] Context APIs follow the constitution's patterns (list_*, get_*, opts keyword list, World-scoped)
- [ ] Error tuples used consistently ({:ok, _} / {:error, _})
- [ ] Public functions have @doc documentation
- [ ] No direct Repo calls from LiveView (all through context)
- [ ] Testability gates do not leak into production paths

### Dependency Review
- [ ] `{:req, "~> 0.5"}` is a reputable, maintained dependency
- [ ] No unnecessary new dependencies introduced
- [ ] No known CVEs in new dependency versions

## Technical Notes

### Review Checklist Priorities
1. **Critical**: Atom creation from user input, cross-World data leaks, secret exposure
2. **High**: OTP supervision correctness, SQL injection, unbounded memory
3. **Medium**: N+1 queries, PubSub scope, error handling consistency
4. **Low**: Code style, documentation completeness

### Constraints
- This is a review task -- produce findings, do not fix code
- Findings must include severity (Critical/High/Medium/Low), location, and recommended fix
- If Critical findings exist, recommend blocking the PR until resolved

## Execution Instructions

### For the Agent
1. Read all new files in `lib/lemmings_os/lemming_instances/` and `lib/lemmings_os_web/live/instance_live.ex`.
2. Review `application.ex` changes for supervision correctness.
3. Review all context functions for World scoping.
4. Review ETS/DETS access patterns.
5. Review PubSub topic patterns for information leakage.
6. Review Req HTTP client usage for security.
7. Review config snapshot contents for secret leakage.
8. Review process naming for atom safety.
9. Produce the findings report.

### For the Human Reviewer
1. Review findings report for completeness.
2. Triage findings by severity.
3. Decide which findings must be fixed before PR (Critical/High).
4. Create follow-up tasks for Medium/Low findings if needed.

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
