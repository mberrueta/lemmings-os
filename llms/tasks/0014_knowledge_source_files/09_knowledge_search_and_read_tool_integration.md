# Task 09: Knowledge Search And Read Tool Integration

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add source-file support to `knowledge.search` and `knowledge.read` runtime tools.

## Objective
Integrate retrieval and read APIs into the tool runtime envelope with strict scope checks, bounded read output, and safe error handling.

## Inputs Required
- [x] Tasks 01-08 approved
- [x] Existing tool runtime adapter patterns
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [x] `knowledge.search` source-file retrieval support.
- [x] `knowledge.read` chunk-content retrieval support.
- [x] Ready-only enforcement and bounded read defaults.

## Acceptance Criteria
- [x] Tool outputs follow existing runtime success/error envelope.
- [x] Tool responses exclude storage refs, raw paths, vectors, and provider responses.
- [x] `knowledge.store` remains memory-only.

## Completed Implementation
- Added runtime dispatch wiring in [`lib/lemmings_os/tools/runtime.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/tools/runtime.ex):
  - `knowledge.search` -> `LemmingsOs.Tools.Adapters.Knowledge.search/3`
  - `knowledge.read` -> `LemmingsOs.Tools.Adapters.Knowledge.read/3`
- Added tool catalog entries in [`lib/lemmings_os/tools/catalog.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/tools/catalog.ex):
  - `knowledge.search`
  - `knowledge.read`
- Added tool argument contracts in [`lib/lemmings_os/model_runtime.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/model_runtime.ex) for:
  - `knowledge.search`
  - `knowledge.read`
  - explicit memory-only contract note for `knowledge.store`
- Extended Knowledge tool adapter in [`lib/lemmings_os/tools/adapters/knowledge.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/tools/adapters/knowledge.ex):
  - Implemented `search/3` with:
    - args validation (`query`, optional `kind=source_file`, `source_file_type`, `tags`, `scope`, `top_k`)
    - query embedding generation via embedding boundary
    - source-file vector retrieval via `Knowledge.search_source_file_chunks/3`
    - safe result envelope with snippet-ready metadata only
  - Implemented `read/3` with:
    - args validation (`chunk_ref`, optional `scope`, `max_chars`)
    - bounded content reads and not-found safe error mapping
- Added context read API in [`lib/lemmings_os/knowledge.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/knowledge.ex):
  - `read_source_file_chunk/3` with ready-only + scope enforcement and bounded content.

## Validation
- Updated tests:
  - [`test/lemmings_os/tools/catalog_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/tools/catalog_test.exs)
  - [`test/lemmings_os/tools/runtime_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/tools/runtime_test.exs)
- Verification commands run:
  - `mix test test/lemmings_os/tools/catalog_test.exs test/lemmings_os/tools/runtime_test.exs`
  - `mix test test/lemmings_os/tools/runtime_test.exs`
  - `mix precommit`

## Constraints
- No UI implementation in this task.

## Approval Gate
Human reviewer must approve this task before Task 10 begins.

## Human Review
*[Filled by human reviewer]*
