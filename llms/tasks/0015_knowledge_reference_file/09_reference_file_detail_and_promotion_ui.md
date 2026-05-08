# Task 09: Reference File Detail And Promotion UI

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView, detail states, and accessible interaction flows.

## Agent Invocation

Act as `dev-frontend-ui-engineer`. Add reference-file detail states and the explicit Artifact promotion UI path.

## Objective

Complete the operator-facing detail and provenance flows for reference files, including safe preview/descriptor display and explicit Artifact promotion.

## Implementation Scope

- Add reference-file detail view or inline expansion consistent with the current Knowledge UI style.
- Display metadata, descriptor, status, scope, optional preview, and provenance state.
- Display unreadable content and unavailable provenance states safely.
- Add explicit operator-approved promotion flow from an Artifact where the product surface supports it.
- Require operator-selected type, scope, title, description, and tags before promotion.
- Show safe errors for inaccessible scopes or Artifacts without revealing hidden resource details.

## Constraints

- Do not add automatic promotion.
- Do not expose raw Artifact or Knowledge storage refs.
- Do not add a hard-delete or recover/restore UI in this task.
- Keep UI copy concise and product-semantic: reference files are models/templates/layout assets/examples, not source-file RAG content.

## Expected Outputs

- Detail/provenance UI states for active, archived, unreadable, and provenance-unavailable reference files.
- Explicit promotion UI integrated with the backend promotion API from Task 06.
- Stable DOM IDs for tests.

## Suggested Checks

- `mix format`
- Narrow LiveView tests for detail and promotion flows once added
- Existing Artifact UI/controller tests as regression reference

## Human Approval Gate

Human reviewer validates detail/provenance behavior and explicit promotion UX, then approves Task 10.
