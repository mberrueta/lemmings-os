# Task 14: Source File Security Audit

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`audit-security` - Security reviewer for authz, input validation, secrets, and data safety.

## Agent Invocation
Act as `audit-security`. Audit source-file Knowledge implementation for security and privacy risks and apply focused fixes for confirmed findings.

## Objective
Verify no unauthorized scope access, no path/content leakage, and no unsafe provider/extraction data exposure.

## Inputs Required
- [x] Tasks 01-13 approved
- [x] Diff for source-file feature branch

## Expected Outputs
- [x] Security findings report with severity and file references.
- [x] Focused fixes for confirmed P0/P1 issues.
- [x] Audit notes for tools runner capability registration, argument validation, and path boundary enforcement.
- [x] Residual risk notes for human sign-off.

## Acceptance Criteria
- [x] Scope authorization for search/read is server-enforced.
- [x] Logs/events/tool outputs are free from forbidden sensitive fields.
- [x] Upload/extraction/indexing inputs are validated with safe failure paths.
- [x] Tools runner execution cannot call arbitrary shell commands or raw shell strings.
- [x] MarkItDown, Trafilatura, and `pdftotext` invocations use controlled file paths, timeouts, output caps, and safe error tokens.
- [x] Apache Tika is absent from runtime configuration and service exposure.

## Constraints
- Avoid speculative churn; prioritize confirmed exploitable issues.

## Approval Gate
Human reviewer must approve this task before Task 15 begins.

## Human Review
*[Filled by human reviewer]*

## Findings
- **P1 (confirmed): URL scheme validation gap for Trafilatura extraction**
  - File: `lib/lemmings_os/knowledge/source_files/extraction_service.ex`
  - Prior behavior: `extract_url/1` accepted any non-empty string and executed Trafilatura capability with that argument.
  - Risk: unsupported or local schemes (for example `file://`) could be forwarded to the extractor.
  - Fix: enforce URL validation (`http`/`https` only, host required) before capability execution; invalid URLs return safe `{:error, :unsupported}`.

## Implemented Fixes
- Added `validate_extract_url/1` and integrated it into `extract_url/1`:
  - `lib/lemmings_os/knowledge/source_files/extraction_service.ex`
- Added regression tests:
  - `test/lemmings_os/knowledge/source_files/extraction_service_test.exs`
  - Covers rejection of non-http(s) and hostless URLs.
  - Preserves timeout and empty-output handling through valid URL inputs.

## Audit Notes
- Scope authorization:
  - `knowledge.search` / `knowledge.read` resolve scope from runtime ancestry and enforce scope checks in `LemmingsOs.Knowledge`.
- Tools runner safety:
  - Allowlist-only capability map lookup.
  - Structured `System.cmd(command, argv)` execution (no raw shell string).
  - Argument type validation, timeout handling, and extracted-char cap enforcement.
- Path boundary:
  - Source-file storage refs resolve through validated local storage refs with root/symlink boundary checks.
- Apache Tika:
  - No Tika config/service/dependency exposure in `config/`, `docker/`, `lib/`, or `mix.exs` runtime paths.

## Residual Risks / Follow-up
- URL extraction currently validates scheme/host but does not apply network egress allowlisting or private-range blocking; treat as deployment-level control for now.
