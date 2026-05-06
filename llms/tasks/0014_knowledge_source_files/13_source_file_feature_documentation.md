# Task 13: Source File Feature Documentation

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer.

## Agent Invocation
Act as `docs-feature-documentation-author`. Document source-file Knowledge behavior, defaults, and operational requirements.

## Objective
Produce docs for operators and developers covering scope, ingestion paths, indexing lifecycle, limits, provider config, and safe observability.

## Inputs Required
- [ ] Tasks 01-12 approved
- [ ] Implemented config/runtime docs locations

## Expected Outputs
- [ ] Documentation updates for source-file Knowledge usage and constraints.
- [ ] Env var/config docs for embedding provider, tools runner, and the `knowledge_indexing` queue if Oban is added.
- [ ] Documentation for the lightweight `lemmings-os-tools-runner` image/container and its initial capabilities: Python runtime, MarkItDown CLI, Trafilatura CLI, and Poppler `pdftotext`.
- [ ] Documentation explaining why Apache Tika is not part of v1.
- [ ] Documentation explaining OCR is future work and image-only/scanned PDFs become `needs_ocr`.
- [ ] Backup/operational notes for stored source-file bytes and DB metadata.

## Acceptance Criteria
- [ ] Docs reflect defaults locked in plan section 13.
- [ ] Docs state source files are Knowledge-managed and not required Artifacts.
- [ ] Docs describe tools runner allowlisted capabilities, structured argv/specs, timeouts, output limits, and no arbitrary shell execution.
- [ ] Docs describe out-of-scope and future work boundaries.

## Constraints
- Keep docs aligned with actual implementation behavior only.

## Approval Gate
Human reviewer must approve this task before Task 14 begins.

## Human Review
*[Filled by human reviewer]*
