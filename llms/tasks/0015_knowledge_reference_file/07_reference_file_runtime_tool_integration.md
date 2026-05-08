# Task 07: Reference File Runtime Tool Integration

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for runtime tool adapters and safe tool envelopes.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Extend runtime Knowledge tools for reference-file discovery/search/read while keeping mutation unavailable to Lemmings.

## Objective

Expose reference-file availability, search, and read behavior to Lemmings through governed tools and runtime guidance without allowing reference-file mutation.

## Implementation Scope

- Update `LemmingsOs.Tools.Adapters.Knowledge` so `knowledge.search` supports `kind: "reference_file"` metadata lookup.
- Update `knowledge.read` to read authorized reference files by `knowledge_item_id` or safe `reference_ref`, while preserving source-file chunk read support.
- Ensure `knowledge.read` returns bounded text for directly readable reference files and bounded converted text for supported binary/structured reference files using the existing safe conversion tools.
- Add or expose a compact scoped availability result if the existing tool shape needs a lightweight listing path.
- Keep `knowledge.store` memory-only and reject reference-file mutation fields.
- Update tool catalog/runtime guidance in `LemmingsOs.ModelRuntime` so Lemmings understand memories, source files, reference files, and artifacts.
- Maintain the existing standard success/error envelope.

## Constraints

- Tool outputs must not expose storage refs, raw paths, full unbounded content, raw extraction output, provider responses, or inaccessible resource hints.
- Do not return raw binary bytes to Lemmings. For unsupported binary files, return a safe descriptor and non-leaking status.
- Unsupported kind/field combinations should return safe structured errors.
- Do not add create/edit/archive/delete/promote tools for Lemmings.

## Expected Outputs

- Runtime tool support for reference-file search/read/availability.
- Updated tool descriptions/guidance.
- Regression coverage for existing source-file search/read and memory store behavior.

## Suggested Checks

- `mix format`
- `mix test test/lemmings_os/tools/adapters/knowledge_test.exs`
- Relevant model runtime/tool catalog tests if present

## Human Approval Gate

Human reviewer validates tool boundary and mutation restrictions, then approves Task 08.
