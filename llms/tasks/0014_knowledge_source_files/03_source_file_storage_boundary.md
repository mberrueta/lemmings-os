# Task 03: Source File Storage Boundary

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the Knowledge-managed storage boundary for source files.

## Objective
Create a safe source-file storage module and config contract that stores original bytes with opaque refs and no path leakage.

## Inputs Required
- [x] Task 02 approved migrations
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`
- [x] Existing artifact storage safety patterns for reference only

## Expected Outputs
- [x] Source-file storage module with safe `put/open_stream/read_private/with_temp_file` style operations.
- [x] Opaque storage refs (no absolute path exposure).
- [x] Enforced max file size default `10 MB`.
- [x] Checksum/size capture and safe error tokens.

## Acceptance Criteria
- [x] Storage refs and errors do not leak root paths or workspace paths.
- [x] Invalid filename/path inputs are safely rejected.
- [x] Internal paths, if needed for extraction, stay private to the storage boundary and never appear in UI, tools, logs, or events.
- [x] Storage API supports later extraction/indexing stages without coupling to Artifacts.

## Constraints
- Keep source-file storage separate from Artifact domain ownership.
- No retrieval logic in this task.

## Approval Gate
Human reviewer must approve this task before Task 04 begins.

## Execution Summary
### Work Performed
- Added dedicated storage boundary module [`source_file_storage.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/knowledge/source_file_storage.ex) under Knowledge domain (separate from Artifacts).
- Implemented safe APIs:
- `put/4` to copy original bytes into managed storage and return `%{storage_ref, checksum, size_bytes}`.
- `read_private/1` for private byte reads.
- `open_stream/2` for streaming access.
- `with_temp_file/2` for internal extractor-style access to private absolute path.
- Implemented opaque storage refs as `local://knowledge_source_files/<world_id>/<knowledge_item_id>/<filename>`.
- Enforced max file size via config-backed limit with default `10 * 1024 * 1024` bytes.
- Added source-file storage runtime/config contract:
- `config/config.exs` default `:knowledge_source_file_storage` root and max size.
- `config/test.exs` test root and max size defaults.
- `config/runtime.exs` runtime root override via `LEMMINGS_KNOWLEDGE_SOURCE_FILE_STORAGE_ROOT`.
- Added targeted tests:
- [`source_file_storage_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/knowledge/source_file_storage_test.exs)
- [`runtime_knowledge_source_file_storage_config_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/config/runtime_knowledge_source_file_storage_config_test.exs)

### Validation Run
- `mix test test/lemmings_os/knowledge/source_file_storage_test.exs test/lemmings_os/config/runtime_knowledge_source_file_storage_config_test.exs`
- `mix format`
- `mix precommit`

## Human Review
*[Filled by human reviewer]*
