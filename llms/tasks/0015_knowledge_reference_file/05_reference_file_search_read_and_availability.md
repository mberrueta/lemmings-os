# Task 05: Reference File Search, Read, And Availability

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for context APIs, retrieval behavior, and safe read models.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Implement metadata-first reference-file lookup, bounded read behavior, and scoped availability in the Knowledge context.

## Objective

Allow Lemmings and operator surfaces to discover, search, and read authorized reference files without using RAG chunks or exposing unsafe storage internals.

## Implementation Scope

- Add scoped availability API for active reference files in a caller's effective scope.
- Add metadata-first search API with filters for kind/category, type, tags, status, text query, and scope.
- Sort predictably, preferring nearer scope and stronger metadata matches.
- Add read API by `knowledge_item_id` and/or `reference_ref` with independent scope enforcement.
- Return bounded text for directly readable file types.
- Return a safe descriptor when content is unavailable, non-text, or unsafe to inline.
- Reuse the existing safe source-file extraction/conversion capability for supported non-text reference files so `knowledge.read` can return bounded converted text.
- Use MarkItDown for supported uploaded Office/PDF/document-like files.
- Use Trafilatura for supported URL/HTML/web-content references, if reference files support URL/HTML registration.
- Use existing PDF fallback tooling only if already available from the source-file implementation.
- Conversion is read-time/content-preview behavior only; it must not create source-file chunks, embeddings, vector indexes, or RAG records.
- If conversion is unsupported or fails, return a safe descriptor and non-leaking unreadable/conversion-failed status.

## Constraints

- Search/read must enforce scope independently; read cannot trust a prior search result.
- Archived, inaccessible, sibling-scope, and cross-World files must be excluded or reported with non-revealing not-found errors.
- Outputs must omit raw file paths, storage refs, provider responses, extracted full bodies, secrets, and internal runtime state.
- Reference files must not be indexed semantically or retrieved by vector similarity.

## Expected Outputs

- Context-level availability, search, and read APIs.
- Safe descriptor contract including `reference_ref`, `knowledge_item_id`, kind, type, title, tags, content type, and safe flags.
- Tests or test hooks for scope filtering, sorting, bounded content, and descriptor safety.

## Suggested Checks

- `mix format`
- Narrow Knowledge search/read tests
- Existing source-file search/read tests as regression reference

## Human Approval Gate

Human reviewer validates lookup/read semantics and no-RAG behavior, then approves Task 06.
