# Task 13: Reference File Documentation And Tool Guidance

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent

`docs-feature-documentation-author` - Feature documentation writer aligned with actual application behavior.

## Agent Invocation

Act as `docs-feature-documentation-author`. Document reference-file behavior and update tool guidance after implementation matches the product plan.

## Objective

Make the Knowledge category boundaries clear for operators and Lemmings.

## Implementation Scope

- Update user-facing docs for Memories, Source Files, Reference Files, and Artifacts.
- Document when to use reference files: templates, models, examples, headers, footers, layout assets, styles, and fixed reusable inputs.
- Document upload/register, metadata, scope, archive behavior, descriptor safety, and optional Artifact provenance.
- Update runtime/tool guidance with the wording direction from `plan.md`.
- Explain that reference files are selected by metadata and availability, not primary RAG/vector search.
- Document known v1 limitations and follow-ups.

## Constraints

- Documentation must match implemented behavior exactly.
- Do not imply reference files are source-file chunks or RAG-indexed documents.
- Do not imply Artifacts are Knowledge unless explicitly promoted by the user.
- Do not expose or describe internal storage paths as user-facing identifiers.

## Expected Outputs

- Updated feature documentation and tool guidance.
- Clear operator-facing distinction between Knowledge categories.
- Lemming-facing guidance to inspect available reference files before generating structured outputs.

## Suggested Checks

- `mix format` if Elixir docs/tool strings changed
- Narrow tests for tool catalog/guidance if present

## Human Approval Gate

Human reviewer validates documentation accuracy and terminology, then approves Task 14.

## Completion Notes

- Updated feature docs to clearly distinguish Knowledge categories and reference
  file semantics:
  - `docs/features/knowledge.md`
  - `docs/features/tools.md`
  - `docs/features/artifacts.md`
- Documentation now reflects implemented behavior:
  - Knowledge families: `memory`, `source_file`, `reference_file`
  - Artifact is separate from Knowledge unless explicitly promoted
  - reference-file lifecycle (`active`/`archived`), metadata-first lookup, and bounded read behavior
  - optional Artifact provenance and no path/storage-ref exposure guarantees
  - no chunk/embedding/vector indexing for reference files
- Added release validation artifact:
  - release validation content captured in Task 19 notes
