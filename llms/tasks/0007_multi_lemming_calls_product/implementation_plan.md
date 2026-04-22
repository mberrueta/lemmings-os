# Execution Plan: 0007 Multi-Lemming Calls

## Metadata
- **Spec**: `llms/tasks/0007_multi_lemming_calls_product/plan.md`
- **Created**: 2026-04-22
- **Status**: PLANNING
- **Branch**: `feat/0007_multi_lemming_calls_product`

## Overview
Implement durable lemming-to-lemming collaboration for same-World, same-City department work. The slice adds explicit manager designation, persisted call records, backend orchestration, seeded departments/lemmings, observability, UI visibility, tests, ADR updates, and final review.

## Technical Summary
- **New persistence**: add explicit `lemmings.collaboration_role` and durable lemming call records.
- **Backend**: add a `LemmingsOs.LemmingCalls` context and wire structured `lemming_call` actions into the existing model/runtime loop.
- **UI**: keep manager chat primary and add lightweight delegated-work visibility on department/instance surfaces.
- **External dependencies**: none.

## Core Technical Decisions
- Manager designation is stored as `lemmings.collaboration_role`, values `manager` or `worker`, default `worker`.
- Durable calls live in a new `lemming_instance_calls` table. Runtime instance status remains unchanged.
- Collaboration call states are `accepted`, `running`, `needs_more_context`, `partial_result`, `completed`, and `failed`.
- UI summary states are derived from collaboration state plus runtime state: `queued`, `running`, `retrying`, `completed`, `failed`, `dead`, and `recovery_pending`.
- Successor work after child expiry is represented by `root_call_id` and `previous_call_id` self-references on call records; UI groups by `root_call_id || id`.
- Seeded company setup is delivered through `priv/default.world.yaml` so `mix setup`/bootstrap creates the product demo world consistently.

## Roles

### Human Reviewer
- Approves each task before the next begins.
- Owns all git operations.
- Confirms product behavior remains in slice.

### Executing Agents
| Task | Agent | Description |
|------|-------|-------------|
| 01 | `dev-backend-elixir-engineer` | Migrations, schemas, and context APIs |
| 02 | `dev-backend-elixir-engineer` | Runtime orchestration and lemming-call execution |
| 03 | `dev-backend-elixir-engineer` | Seeded company setup |
| 04 | `dev-logging-daily-guardian` | Observability and telemetry |
| 05 | `qa-elixir-test-author` | Backend tests |
| 06 | `dev-frontend-ui-engineer` | UI changes |
| 07 | `qa-elixir-test-author` | UI tests |
| 08 | `docs-feature-documentation-author` | ADR/docs updates |
| 09 | `audit-pr-elixir` | Final review |

## Task Sequence
| # | Task | Status | Approved |
|---|------|--------|----------|
| 01 | Persistence, Schemas, Contexts | PENDING | [ ] |
| 02 | Backend Collaboration Runtime | PENDING | [ ] |
| 03 | Seeded Company Setup | PENDING | [ ] |
| 04 | Observability | PENDING | [ ] |
| 05 | Backend Tests | PENDING | [ ] |
| 06 | UI Changes | PENDING | [ ] |
| 07 | UI Tests | PENDING | [ ] |
| 08 | ADR Updates | PENDING | [ ] |
| 09 | Final Review | PENDING | [ ] |

## Assumptions
1. Same-World and same-City boundaries are mandatory for this slice.
2. Existing `LemmingInstances` runtime statuses are preserved and not overloaded.
3. Workers may escalate only to their parent manager instance through system-enforced call APIs.
4. Manager-to-manager cross-department calls are allowed only inside the same city.
5. No prompt externalization, skill marketplace, cross-city, or cross-world behavior is included.

## Approval Gate
Each task must be completed, summarized, tested as applicable, and approved by the human reviewer before the next task starts.

## Change Log
| Date | Task | Change | Reason |
|------|------|--------|--------|
| 2026-04-22 | Plan | Initial execution plan | Split product plan into concise implementation tasks |
