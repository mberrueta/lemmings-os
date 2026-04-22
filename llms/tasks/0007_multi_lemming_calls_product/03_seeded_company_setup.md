# Task 03: Seeded Company Setup

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md`, `llms/project_context.md`, and `llms/coding_styles/elixir.md`.

## Objective
Provide the company setup for this slice with IT, Marketing, and Sales departments plus manager and worker lemming identities.

## Inputs Required
- [ ] Task 01 outputs
- [ ] Task 02 manager/capability rules
- [ ] `priv/default.world.yaml`
- [ ] World bootstrap loader/importer/validator modules

## Expected Outputs
- [ ] `priv/default.world.yaml` includes one city, three departments, and all product-plan lemming types.
- [ ] Bootstrap shape validation accepts department/lemming role metadata.
- [ ] Manager lemmings have `collaboration_role: manager`; specialists have `worker`.
- [ ] Each lemming has explicit name, slug, description, instructions, and relevant tool/model configuration.
- [ ] Marketing department supports the end-to-end showcase path.

## Seeded Departments
- IT: `it_manager`, `web_researcher`, `structured_writer`
- Marketing: `marketing_manager`, `local_competitor_researcher`, `maps_researcher`, `website_competitor_researcher`, `campaign_writer`, `email_writer`, `social_post_writer`
- Sales: `sales_manager`, `quote_builder`, `proposal_writer`

## Acceptance Criteria
- [ ] `mix setup`/bootstrap can create the seeded company setup from config.
- [ ] Re-running bootstrap remains idempotent.
- [ ] Seeded lemming identities are clear enough for UI and LLM context.
- [ ] No hardcoded secrets or hosted-provider dependency is introduced.

## Execution Instructions
1. Extend bootstrap config shape only as needed for lemmings and collaboration roles.
2. Keep seeded setup local-first and self-hosted.
3. Add minimal docs/comments in config where useful.

## Human Review
Confirm seeded roles and names match product intent before tests are written.
