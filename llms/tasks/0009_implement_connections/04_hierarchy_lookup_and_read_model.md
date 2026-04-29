# Task 04: Hierarchy Lookup and Read Model

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-03, then implement hierarchy-aware lookup and safe read models.

## Objective
Implement Connection visibility across World, City, and Department scopes using the product rule: nearest visible scope wins.

## Expected Outputs
- Context APIs for listing visible Connections for a World, City, or Department scope.
- Context API for resolving a visible Connection record by caller scope and slug.
- Safe read model fields that identify source scope and whether a Connection is local or inherited.
- Query helpers that preserve explicit World scoping.
- Coverage of disabled and invalid records as inspectable but not usable by runtime-facing lookup.

## Lookup Rules
- Department lookup checks Department, then City, then World.
- City lookup checks City, then World.
- World lookup checks only World.
- Sibling Departments cannot see each other's Department scoped Connections.
- Different Worlds can never see each other's Connections.
- A child Connection with the same slug overrides the inherited parent Connection for that child scope.

## Acceptance Criteria
- Nearest visible scope wins for duplicate slugs.
- Visible list output does not duplicate shadowed parent Connections with the same slug.
- Read models include safe source-scope metadata.
- Department Connections are invisible to sibling Departments.
- Cross-World lookup fails safely.
- Disabled and invalid Connections remain inspectable in read models.
- No Secret Bank resolution or mock provider testing is implemented.

## Review Notes
Reject if hierarchy lookup bypasses explicit World scoping or if it exposes sibling or cross-World Connections.
