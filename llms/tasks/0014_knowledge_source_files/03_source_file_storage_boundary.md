# Task 03: Source File Storage Boundary

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the Knowledge-managed storage boundary for source files.

## Objective
Create a safe source-file storage module and config contract that stores original bytes with opaque refs and no path leakage.

## Inputs Required
- [ ] Task 02 approved migrations
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`
- [ ] Existing artifact storage safety patterns for reference only

## Expected Outputs
- [ ] Source-file storage module with safe `put/open_stream/read_private/with_temp_file` style operations.
- [ ] Opaque storage refs (no absolute path exposure).
- [ ] Enforced max file size default `10 MB`.
- [ ] Checksum/size capture and safe error tokens.

## Acceptance Criteria
- [ ] Storage refs and errors do not leak root paths or workspace paths.
- [ ] Invalid filename/path inputs are safely rejected.
- [ ] Internal paths, if needed for extraction, stay private to the storage boundary and never appear in UI, tools, logs, or events.
- [ ] Storage API supports later extraction/indexing stages without coupling to Artifacts.

## Constraints
- Keep source-file storage separate from Artifact domain ownership.
- No retrieval logic in this task.

## Approval Gate
Human reviewer must approve this task before Task 04 begins.

## Human Review
*[Filled by human reviewer]*
