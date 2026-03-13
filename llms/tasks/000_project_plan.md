# LemmingsOS — LLM Issue Execution Conventions

This file defines how LLM agents should execute work when asked to start GitHub issue `X`.

Project tracking lives in GitHub, not in this folder.

## Trigger

When the user asks: "start GH issue X", the agent must:

1. Read the issue title, body, labels, milestone, and project status.
2. Create a task folder and planning artifact:
   - `llms/tasks/xxx_issue_x/plan.md`
3. Generate that plan using:
   - `llms/agents/po_analyst.md`
4. Restate scope in 3-6 bullets before coding.
5. Execute only what is in scope for that issue.

## Required Workflow

### 1. Understand

- Confirm acceptance criteria from the issue body.
- Identify missing assumptions and resolve them from repository context first.
- Check whether the issue touches the agent hierarchy (World/City/Department/Lemming)
  and flag any World scoping or OTP supervision implications.

### 2. Plan

- Always create `llms/tasks/xxx_issue_x/plan.md`.
- Use `llms/agents/po_analyst.md` as the planning agent/instructions source.
- Keep the plan tied to issue acceptance criteria.
- If `po_analyst.md` is missing, state it explicitly and produce the best equivalent plan format.

### 3. Implement

- Make minimal, focused changes.
- Follow `llms/constitution.md` and `AGENTS.md`.
- All new context functions for World-scoped resources must accept `world_id` explicitly.
- OTP processes must be started via `DynamicSupervisor` or `start_supervised/1`; never raw `spawn`.

### 4. Validate

- Run relevant tests for changed areas.
- Run `mix precommit` before handoff.
- Report what was run and results.

### 5. Handoff

- Provide concise summary:
  - files changed
  - behavior delivered
  - tests run
  - any follow-up risks or TODOs (especially supervision or isolation edge cases)

## Non-Negotiable Constraints

- Do not duplicate roadmap/project tracking in repository docs unless explicitly requested.
- Do not perform git write actions:
  - `git add`
  - `git commit`
  - `git push`
  - `git stash`
  - `git revert`
- Leave version control actions to the user.

## Scope Rules

- If the issue is too broad, split it into a proposed checklist in the response and implement
  only the first safe slice.
- If issue scope conflicts with constitution/guidelines, follow the constitution and explain
  the conflict.
- Do not implement features outside the current issue unless explicitly requested.

## Definition of Done (per issue)

An issue is considered done for agent handoff when:

1. Acceptance criteria are satisfied.
2. Tests and `mix precommit` pass.
3. The user receives a clear change summary and next steps (if any).
