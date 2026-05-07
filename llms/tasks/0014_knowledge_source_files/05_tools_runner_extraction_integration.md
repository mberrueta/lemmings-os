# Task 05: Tools Runner Extraction Integration

## Status
- **Status**: ✅ COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Integrate source-file extraction through a controlled CLI tools runner.

## Objective
Implement the extraction adapter boundary and initial tools runner capabilities for source files, with timeout/size limits, PDF fallback behavior, `needs_ocr` detection, and safe failure handling.

## Inputs Required
- [x] Tasks 01-04 approved
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`
- [x] Docker Compose and runtime config patterns
- [x] Task 04 indexing worker/job boundary

## Expected Outputs
- [x] Generic lightweight `lemmings-os-tools-runner` image/container documented or wired as the controlled CLI runtime.
- [x] Extraction adapter boundary callable by the Task 04 indexing worker/job.
- [x] MarkItDown adapter/capability for uploaded files.
- [x] Trafilatura adapter/capability for URL/HTML sources; this task makes extraction adapter-ready and does not require user-facing URL registration unless Task 04/10 explicitly includes it.
- [x] Poppler `pdftotext` fallback adapter/capability for PDFs when MarkItDown output is empty or insufficient.
- [x] Image-only/scanned PDF detection that marks the source file `needs_ocr`.
- [x] Extraction timeout default `30s`.
- [x] Max extracted characters enforcement default `500,000`.
- [x] Lifecycle updates + safe failure reason tokens.

## Acceptance Criteria
- [x] Extraction success/failure transitions are visible to downstream indexing flow.
- [x] Uploaded files use MarkItDown where supported.
- [x] URL/HTML sources use Trafilatura when URL/HTML source registration exists.
- [x] PDFs fall back to `pdftotext` when MarkItDown output is empty or insufficient.
- [x] Image-only/scanned PDFs are marked `needs_ocr`, are excluded from retrieval, and do not attempt OCR.
- [x] Unsupported, empty, timed-out, or failed extraction output is handled safely.
- [x] The Phoenix app invokes only named/registered capabilities with validated arguments.
- [x] Command execution uses argument lists or structured command specs, never raw shell strings.
- [x] File paths are controlled by the Knowledge storage/workspace boundary and never exposed to UI, tools, logs, or events.
- [x] Timeouts, output size limits, safe error tokens, and no path/content leakage are enforced.
- [x] No full extracted content is logged or emitted in durable events.
- [x] No Apache Tika dependency, service, endpoint, or client is introduced in this PR.

## Constraints
- No chunking or embedding implementation in this task unless existing Task 04 orchestration requires a no-op handoff point.
- No OCR implementation in this task or PR.
- The tools runner must not become arbitrary shell execution.
- Future CLI tools must require explicit allowlisted capability catalog entries.

## Approval Gate
Human reviewer must approve this task before Task 06 begins.

## Human Review
*[Filled by human reviewer]*
