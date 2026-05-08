# Task 13: Source File Feature Documentation

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer.

## Agent Invocation
Act as `docs-feature-documentation-author`. Document source-file Knowledge behavior, defaults, and operational requirements.

## Objective
Produce docs for operators and developers covering scope, ingestion paths, indexing lifecycle, limits, provider config, and safe observability.

## Inputs Required
- [x] Tasks 01-12 approved
- [x] Implemented config/runtime docs locations

## Expected Outputs
- [x] Documentation updates for source-file Knowledge usage and constraints.
- [x] Env var/config docs for embedding provider, tools runner, and the `knowledge_indexing` queue if Oban is added.
- [x] Documentation for the lightweight `lemmings-os-tools-runner` image/container and its initial capabilities: Python runtime, MarkItDown CLI, Trafilatura CLI, and Poppler `pdftotext`.
- [x] Documentation explaining why Apache Tika is not part of v1.
- [x] Documentation explaining OCR is future work and image-only/scanned PDFs become `needs_ocr`.
- [x] Backup/operational notes for stored source-file bytes and DB metadata.

## Acceptance Criteria
- [x] Docs reflect defaults locked in plan section 13.
- [x] Docs state source files are Knowledge-managed and not required Artifacts.
- [x] Docs describe tools runner allowlisted capabilities, structured argv/specs, timeouts, output limits, and no arbitrary shell execution.
- [x] Docs describe out-of-scope and future work boundaries.

## Constraints
- Keep docs aligned with actual implementation behavior only.

## Approval Gate
Human reviewer must approve this task before Task 14 begins.

## Human Review
*[Filled by human reviewer]*

## Execution Summary
- Rewrote `docs/features/knowledge.md` from memory-only content to implemented Knowledge behavior covering:
  - memory + source-file scope and UI behavior,
  - source-file ingestion paths and lifecycle,
  - `knowledge.search` and `knowledge.read` runtime behavior/bounds,
  - config/env defaults for storage, chunking, tools runner, embeddings, and Oban queue,
  - tools runner sidecar image/capabilities and safety boundary,
  - explicit v1 boundaries for Apache Tika and OCR (`needs_ocr`),
  - backup and operational notes for storage bytes + DB metadata/chunks.
- Updated root README feature link text to point to the expanded Knowledge feature surface.
