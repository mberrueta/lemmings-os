# LemmingsOS -- 0007 Multi-Lemming Calls

## Execution Metadata

- Spec / Plan: `llms/tasks/0007_multi_lemming_calls_product/plan.md`
- Created: `2026-04-21`
- Status: `PLANNING`
- Branch: `feat/0007_multi_lemming_calls_product`
- Document owner: Product / Functional definition
- Follow-up owner: Architecture / Implementation planning

## Goal

Deliver the first collaboration slice where a user can work with a department through a primary manager conversation, while that manager can delegate bounded work to specialist lemmings, collect results, continue partial work over time, and keep the full collaboration understandable.

This document defines the **functional product plan** only. It does not define technical design, implementation tasks, or code structure.

---

## Product Intent

LemmingsOS should prove a clear product idea:

- one request can be solved by **many narrow lemmings** instead of one broad one
- collaboration should be **explicit**, not hidden
- users should be able to understand **who did what**
- the system should feel useful for a real small company from day one

This slice should validate collaboration as a product capability, not as an internal technical experiment.

---

## Problem Statement

Today a single lemming can run a session, use tools, and produce results.

What is still missing is a collaboration model where:

- one lemming coordinates broader work
- specialist lemmings handle narrow tasks
- work may remain pending across long-lived sessions
- users can inspect the collaboration and continue it later
- departments feel like usable operating units rather than isolated demos

Without this, LemmingsOS still behaves mainly like a single-agent runtime.

---

## Product Outcome

A user should be able to:

1. open a department
2. ask the department manager for help through a primary chat
3. see that manager delegate work to specialist lemmings when needed
4. inspect delegated lemmings and their state
5. receive a final or partial answer from the manager
6. return later and continue the same collaboration over long-lived sessions

The experience should feel:

- clear
- bounded
- inspectable
- resilient enough for long-running work
- useful in a small-company context

---

## Scope

### In Scope

- multi-lemming collaboration inside the same World
- collaboration inside the same City only
- explicit department managers
- explicit specialist lemmings
- delegation, tracking, and refinement of delegated work
- result aggregation by the manager
- partial completion when some delegated work remains pending or fails
- dynamic capability visibility based on what is available and allowed
- long-lived sessions that may last days
- seeded company setup with three departments
- minimal UI expansion required to make the collaboration visible

### Out of Scope

- multi-node or cross-City execution
- cross-World communication
- free-form peer-to-peer conversation between arbitrary lemmings
- generalized skills marketplace or external skill import
- broad UI redesign
- prompt externalization or prompt templating in this slice
- technical architecture, implementation tasks, or code module planning

---

## Product Principles

### 1. Managers are normal lemmings

A manager is a lemming type, not a special runtime actor.

### 2. Manager designation is explicit

A manager must be identifiable by the system through explicit product metadata or configuration. It must not exist only as a prompt convention.

### 3. Coordination is explicit

Delegation should be visible in the product and understandable to the user.

### 4. Workers stay narrow

Each worker should receive the smallest useful scope and the least context necessary.

### 5. System-first, LLM-second

If the system can detect and perform something deterministically, it should do so directly rather than relying on the LLM to remember or infer it.

### 6. Context is intentionally limited

A lemming should know only what it needs to perform its own task.

### 7. Department boundaries matter

Departments define meaningful functional boundaries, capability boundaries, and practical operating limits.

### 8. Collaboration must remain inspectable over time

Sessions may last days. Delegation history, state, and outcomes must remain understandable.

---

## Functional Model

### Department manager

Each department has a manager lemming type.

The manager:

- is the recommended entry point for department work
- has the strongest model profile in the department
- has the broadest department-level capability visibility
- knows the tools available to its department
- knows the lemming types available in its department
- knows the departments available to it for cross-department requests
- tracks the live work it has spawned
- collects and synthesizes child results

A manager may have multiple runtime instances, like any other lemming.

Each manager instance only tracks the live threads that **it** spawned.

### Specialist lemmings

Specialist lemmings are narrow workers.

A specialist:

- focuses on a small task type
- receives only the minimum context needed
- may use its allowed tools
- cannot freely delegate to other workers
- if spawned by a manager, reports back to that manager instance
- if opened directly by the user, behaves as a user-managed lemming

### Manager-to-manager collaboration

Cross-department work is allowed only through managers.

If a manager needs work from another department, it requests an instance of that department's manager and asks for the required result.

That remote manager may:

- answer directly
- use its own workers
- call other departments if needed and allowed

### User-managed lemmings

A user may open and use a lemming directly.

If the user starts a lemming directly:

- that lemming has no manager-lemming above it
- the user is its logical manager
- it may use its own tools
- it does not gain delegation rights just because it is user-opened

---

## Delegation Rules

### Rule 1 -- Department crossing

Only manager lemmings may speak across departments.

### Rule 2 -- Internal escalation

Inside a department, a worker that needs something outside its task must ask its own manager instance.

### Rule 3 -- Worker delegation

Workers do not delegate directly to other workers or departments.

### Rule 4 -- Manager hierarchy for this slice

Each department has its own manager. There is no city-wide or company-wide super-manager in this slice.

### Rule 5 -- Partial completion

A manager may answer with a partial result while some delegated work remains pending.

### Rule 6 -- Pending work awareness

The manager must keep explicit track of:

- which lemming it asked
- what task it asked for
- current state
- whether the work remains pending
- a result summary when available

### Rule 7 -- Parallel work

A manager may launch multiple delegated tasks in parallel, subject to existing World, City, and Department limits for lemmings and tasks.

### Rule 8 -- Refinement vs new task

If a manager wants to refine or continue work previously requested from a lemming, it should use the same instance when that makes sense.

If the manager wants a different task, even from the same lemming type, it should spawn a new instance.

### Rule 9 -- Multiple instances of the same type

A single manager may have multiple live instances of the same lemming type at the same time.

### Rule 10 -- Cross-department request path

A manager requests another department through a manager instance of that department, never through its workers directly.

### Rule 11 -- World and City boundary

Delegation and capability visibility remain bounded to the same World and the same City in this slice.

---

## Lemming Calls

Lemming-to-lemming interaction should follow the same product philosophy as tool calling.

A lemming call is a structured invocation, not free-form chat.

The manager should see both of these as available capability families:

- tools
- lemming calls

The LLM may choose the most suitable path to achieve the requested outcome.

### Functional expectations for lemming calls

- a lemming call is a structured request
- the caller targets a capability or lemming type first
- if the caller has already spawned a suitable instance, it may continue work there
- if the work is new, it may spawn a new instance
- the system preserves the relationship between caller and callee
- the collaboration itself leaves a durable trace

### Minimum collaboration call states

- `accepted`
- `running`
- `needs_more_context`
- `partial_result`
- `completed`
- `failed`

These are **user-visible collaboration states**, not a technical replacement for existing runtime status fields.

The technical mapping between collaboration states and runtime persistence states is defined later by architecture.

These collaboration call states are distinct from UI summary states. They may overlap in wording, but they do not need to map one-to-one.

### Durable collaboration record

Delegation must leave a durable collaboration record separate from the base lemming session status model.

At minimum, that record must preserve:

- caller
- callee
- requested work
- current collaboration state
- result summary
- error summary when relevant
- key timestamps
- recovery outcome when recovery is attempted

---

## Capability Visibility

### What a manager can see

A manager dynamically sees:

- the tools available to its department
- the lemming types available in its department
- the departments available to it for cross-department work

In addition, a manager instance should see the work it has already spawned, including:

- which lemmings it launched
- what it asked them to do
- their current state

### What a worker can see

If a worker was spawned by a manager, it sees:

- its allowed tools
- the ability to respond or escalate to that manager instance

If a worker was opened directly by the user, it sees:

- only its allowed tools

### Dynamic visibility principle

Capability visibility should be dynamic and based on what is currently available and allowed, not on a fully hardcoded static list.

Visibility must remain bounded by:

- World isolation
- same-City scope for this slice
- department-level capability boundaries
- the effective permissions and configuration available to the caller

---

## Context Rules

### Rule 1 -- Minimal context

Each lemming receives the smallest useful amount of context.

### Rule 2 -- No full parent thread by default

A worker does not receive the full manager thread.

### Rule 3 -- No global map for workers

A worker does not receive a system-wide map of departments or lemmings.

### Rule 4 -- Manager as context owner

The manager remains the main owner of the broader coordination context.

### Rule 5 -- Identity in context

Each lemming type must have a clear identity that can be surfaced in context and capability descriptions.

That identity should make it easy for the LLM and the user to understand:

- what the lemming does
- what it does not do
- which tools it may use
- when it should be called

---

## Session and Interaction Rules

### Primary department entry

Each department should provide:

- one main ask box for asking the department for help
- a visible list of lemming types available in the department

The manager is the recommended primary entry point, but the user may open other lemming types directly.

### Child sessions

If the manager spawns a specialist lemming, the user may open that lemming's own session if desired.

### Direct user input to a child

If a child was spawned by a manager and later receives additional user input or changed requirements:

- that input should remain visible in the child session as part of its normal conversation history
- the parent collaboration record should also be updated so the manager remains informed
- this should be system-driven wherever it can be detected deterministically

### Long-lived sessions

A session may last days.

Delegated work may remain active, pending, completed, or recoverable across that timeline.

---

## Reuse, Expiry, and Recovery

### Short idle reuse window

A lemming that has completed work may remain alive for a short time so that it can receive immediate follow-up or refinement.

### Eventual expiry

Completed child instances should not remain alive indefinitely. They may expire after an idle period.

### Reusable logical work

If a completed child still represents meaningful logical work, the manager may continue work on the same child instance when that instance is still reusable.

If an expired child still represents meaningful logical work, the manager may continue the logical collaboration by spawning a successor instance and linking it back to the same collaboration record. Expiry should not imply the old runtime instance itself can be reused.

### Recovery after restart

Recovery is best effort.

After restart, a thread may appear as:

- `recovery_pending`
- unknown / pending verification

If it can be recovered, it should continue.

If it cannot be recovered, the thread becomes `dead`, meaning closed as unrecoverable while remaining visible in collaboration history.

---

## UI Expectations

This slice should change the UI only as much as needed to make collaboration understandable.

### Main session model

The primary user experience remains a chat/session with the manager.

### Delegated work visibility

Delegated lemmings or delegated tasks should appear in a way that makes it possible to understand:

- what was launched
- what is still running
- what completed
- what failed
- what is pending recovery

### Existing identification model

Current lightweight instance identification may continue, using:

- lemming type
- state
- first characters of the request or result

### Expandable detail

The department list should remain lightweight, with additional detail available only when needed.

### Historical visibility

The user should be able to:

- see completed work
- see dead or failed work
- reopen past sessions or threads if desired

### Minimum user-visible collaboration states

The UI should support at least these user-visible collaboration states:

- `queued`
- `running`
- `retrying`
- `completed`
- `failed`
- `dead`
- `recovery_pending`

These are product-facing states. Their technical mapping to runtime persistence states is defined later by architecture.

For this plan, `dead` means a delegated thread or runtime could not be recovered and has been closed as unrecoverable.

---

## Seeded Company Setup

The plan requires a useful seeded environment:

- `1 World`
- `1 City`
- `3 Departments`

### Department: IT

Purpose:

- web research
- structured transformation
- output in formats such as markdown, JSON, or YAML

Lemming types:

- `it_manager`
- `web_researcher`
- `structured_writer`

### Department: Marketing

This is the primary functional showcase department for this slice.

Purpose:

- local market research
- competitor research
- website review
- campaign drafting
- email drafting
- social post drafting

Lemming types:

- `marketing_manager`
- `local_competitor_researcher`
- `maps_researcher`
- `website_competitor_researcher`
- `campaign_writer`
- `email_writer`
- `social_post_writer`

The product should demonstrate an end-to-end flow where the manager can:

- research local competitors
- research maps or local presence
- inspect competitor websites
- synthesize the findings
- turn them into campaign, email, or social outputs

### Department: Sales

Purpose:

- quotation support
- proposal drafting
- simple commercial response support

Lemming types:

- `sales_manager`
- `quote_builder`
- `proposal_writer`

### Seed mechanism

The architecture follow-up must define where this seeded company setup lives operationally.

This plan intentionally does not choose between bootstrap config seeding and repository seed scripts.

---

## Acceptance Criteria

### Collaboration criteria

- Each department manager can delegate bounded work to specialist lemmings.
- Workers never become free-form coordinators.
- Cross-department collaboration happens only through managers.
- Managers may run multiple delegated tasks in parallel within existing hierarchical limits.
- Managers may answer with partial results when some delegated work remains pending or fails.

### Boundary criteria

- Collaboration remains inside the same World.
- Cross-department requests remain inside the same City for this slice.
- Workers cannot bypass department boundaries through direct delegation.
- The manager-to-other-manager path is enforced by the system.

### Context and control criteria

- Workers receive only the minimum context required for their task.
- Workers do not receive the full parent thread by default.
- Workers do not receive a global system map.
- Managers remain the primary owners of the broader coordination context.
- System-detectable synchronization events are handled by the system, not left to the LLM.
- Manager designation is explicit at the product/system level, not prompt-only.

### Session criteria

- A department offers a primary ask entry plus access to its lemming types.
- Users may open lemmings directly.
- Users may inspect a spawned child session if they want.
- If a child with a manager relationship receives additional user input, the child session preserves that input and the parent collaboration record is also updated.
- Sessions may remain useful across long-lived timelines.

### Reuse and lifecycle criteria

- Refinement uses the same instance when possible.
- A distinct new task creates a distinct new instance.
- A manager may keep multiple live instances of the same type.
- Completed instances may remain briefly reusable and then expire.
- Recovery after restart is best effort.
- If a thread cannot be recovered, it closes cleanly.
- Partial aggregation remains visible even when one or more child threads fail or remain pending.

### Seed criteria

- The seeded environment includes IT, Marketing, and Sales.
- Marketing is the strongest end-to-end showcase.
- Marketing includes multiple web research specialists, not only one generic researcher.
- Every lemming type has an explicit identity suitable for both user understanding and LLM context.

### UI criteria

- The primary experience remains manager-centered.
- Delegated work is visible and understandable.
- The minimum user-visible collaboration states are present.
- Historical work remains visible and reopenable.
- UI changes remain intentionally small for this slice.

---

## Non-Functional Requirements

### Auditability

The collaboration model must preserve clear traceability of:

- who launched whom
- what task was requested
- what state it reached
- what result summary exists
- whether recovery succeeded or failed

### Observability

The product must make delegated work operationally understandable.

At a product level, this means users and operators should not lose visibility into:

- active work
- pending work
- failed work
- dead work
- recovery-pending work

### Deterministic system behavior

Any behavior that can be detected and enforced by the system should be implemented as a system rule rather than delegated to prompt obedience.

### Boundary clarity

Department boundaries must remain understandable and meaningful.

### Long-lived usability

Sessions should remain usable over time, including when work stays pending, is refined later, or requires best-effort recovery.

### Minimal UI disturbance

This slice should add the minimum necessary product surface to support the new capability.

---

## Architecture Handoff Required Before Execution

Before implementation starts, the architecture plan must define:

- the durable collaboration model for lemming-to-lemming calls
- how collaboration records relate to, but do not overload, the base lemming session status model
- the explicit manager designation model
- the structured invocation model for lemming calls alongside tools
- the mapping between user-visible collaboration states and runtime persistence states
- the mapping between collaboration call states and UI summary states
- the source of dynamic capability visibility
- the exact behavior for child-to-parent synchronization after direct user input
- the successor-link behavior for continuing logical work after a child instance expires
- the operational seed delivery mechanism

This functional plan is intentionally complete on product rules and intentionally incomplete on technical design.

---

## Assumptions

1. Existing World, City, Department, and Lemming concepts remain the core product hierarchy.
2. Existing hierarchical limits for lemmings and tasks continue to apply.
3. Prompt experimentation and prompt externalization are follow-up work, not part of this slice.
4. Architecture and implementation planning will be handled separately after this functional plan is approved.

---

## Explicit Follow-Ups (Not In This Slice)

- externalized prompts or editable prompt templates
- broader provider expansion
- larger UI redesign
- cross-City or multi-node collaboration
- higher-level company or city super-manager concepts

---

## Change Log

| Date | Change | Reason |
|------|--------|--------|
| 2026-04-21 | Functional plan revised | Align product plan with latest review, clarify boundaries, and add architecture handoff requirements |
