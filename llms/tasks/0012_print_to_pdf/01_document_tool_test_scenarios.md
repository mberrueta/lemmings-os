# Task 01: Document Tool Test Scenarios

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, regressions, and coverage planning.

## Agent Invocation
Act as `qa-test-scenarios`. Convert the print-to-PDF feature plan into a concrete scenario matrix before implementation starts.

## Objective
Define the complete test and acceptance scenario matrix for the two document tools: catalog registration, runtime dispatch, WorkArea path safety, Markdown rendering, PDF printing through Gotenberg, header/footer/CSS precedence, fallback assets, remote asset blocking, atomic writes, config parsing, observability, Docker Compose, and final validation.

## Scope & Assumptions
- This task defines what to test; it does not write ExUnit code or change production code.
- All Gotenberg coverage in tests uses `Bypass`; no test should depend on a real Gotenberg container or public network access.
- WorkArea tests use isolated temporary roots and restore Application env after each test.
- Config tests mutate env-backed runtime settings and must assert restoration and startup-failure behavior.
- Compose coverage is a static/manual review, not a runtime smoke test.
- Assertions should use sentinel values to prove document contents, absolute paths, fallback paths, and backend bodies do not leak.

## Risk Areas
- WorkArea escape, symlink traversal, and bad path normalization.
- Partial writes or clobbered outputs when conversion or backend calls fail.
- Remote asset fetches, `file://` references, and CSS `@import` leakage before PDF rendering.
- Fallback asset trust boundary violations and path/content leakage.
- Backend timeout, unavailable, and retry behavior.
- Runtime config parsing that silently weakens safety limits.
- Logging or telemetry that exposes file contents, absolute paths, or backend response bodies.

## P0/P1/P2 Coverage Recommendations

| Subsystem | Priority | Recommendation |
|---|---|---|
| Catalog / runtime dispatch | P0 | Verify new tool IDs, normalized results, and unchanged unsupported/scope errors. |
| WorkArea / path safety | P0 | Reject absolute, traversal, Windows, backslash, and symlink paths before any I/O. |
| Markdown to HTML adapter | P0 | Cover render success, overwrite protection, source validation, and atomic failure cleanup. |
| PDF backend / atomic output | P0 | Use `Bypass` for success, non-2xx, timeout, connection failure, retry, and no-partial-file checks. |
| Remote asset blocking | P0 | Fail safely before backend calls when HTML/CSS contains blocked references. |
| Header/footer/CSS precedence | P1 | Cover explicit > conventional > fallback resolution and missing-asset handling. |
| Fallback asset trust rules | P1 | Cover `priv/documents/` constraint, symlink rejection, size checks, and safe logging. |
| Runtime config / Compose | P1 | Verify env defaults, overrides, invalid numeric envs, and private Gotenberg topology. |
| Observability | P1 | Assert safe event fields only; no content or absolute path leakage. |
| Compatibility cases | P2 | Cover alias formats such as `.htm`, `.jpeg`, and `.webp`, plus empty fallback env handling. |

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| CAT-001 | P0 | Unit | Catalog | Tool catalog exposes `documents.markdown_to_html` and `documents.print_to_pdf` alongside existing tools | Catalog module loaded | Call `Catalog.list_tools/0` and `supported_tool?/1` | Both document tools are present and supported; existing tools remain unchanged | Update doctest expectations too |
| RUN-001 | P0 | Integration | Runtime | Runtime dispatches `documents.markdown_to_html` through the normalized success envelope | Valid world/instance scope | Call `Runtime.execute/5` with markdown tool args | Success result preserves `tool_name`, `args`, `summary`, `preview`, and `result` | Adapter behavior can be stubbed or Bypass-backed |
| RUN-002 | P0 | Integration | Runtime | Runtime dispatches `documents.print_to_pdf` through the normalized success envelope | Valid world/instance scope | Call `Runtime.execute/5` with print args | Success result uses the existing envelope and does not add a second status wrapper | Ensure `Req`/adapter details stay hidden |
| RUN-003 | P0 | Integration | Runtime | Unsupported tool still returns `tool.unsupported` | Valid world/instance scope | Call `Runtime.execute/5` with `exec.run` or similar | Error shape is unchanged and safe | Regression guard for existing tools |
| RUN-004 | P0 | Integration | Runtime | World/instance scope mismatch still returns `tool.invalid_scope` | Mismatched world and instance | Call `Runtime.execute/5` with mismatched scope | Same invalid-scope error as before; no adapter call | Must remain unchanged by document tools |
| RUN-005 | P1 | Integration | Runtime | Runtime metadata is honored and merged for tool config / work area context | Runtime meta includes trusted config and `work_area_ref` | Pass runtime meta through `Runtime.execute/5` | Adapter sees the expected runtime metadata without losing world scope | Helps catch config/context regression |
| WA-001 | P0 | Unit | Validation | `WorkArea.resolve/2` rejects unsafe agent-controlled paths | Temporary WorkArea root exists | Resolve absolute, traversal, Windows drive, backslash, and symlink paths | Returns `{:error, :invalid_path}` and does not escape the WorkArea | Security boundary for all agent paths |
| MD-001 | P0 | Integration | Adapter | `documents.markdown_to_html` converts Markdown into HTML in the same WorkArea | Source `.md` exists; output absent | Convert a Markdown file to `.html` | Output file is written, preview is HTML, and result reports relative paths and byte count only | Use temp WorkArea and atomic-write assertions |
| MD-002 | P0 | Integration | Adapter | Markdown-to-HTML rejects invalid source, output conflict, and oversize cases | Source missing or too large; output may exist | Trigger each validation failure | Returns structured errors before any write; existing output protected unless overwrite is true | Covers missing source, extension checks, and size limit |
| MD-003 | P0 | Integration | Adapter | Markdown-to-HTML leaves no partial file after write/render failure | Source exists | Force a failure during render or write | Final output path is absent or unchanged; temp file cleaned best-effort | Atomic rename requirement |
| PDF-001 | P0 | Integration | Adapter | HTML source prints to PDF through Gotenberg | WorkArea HTML source exists; Bypass Gotenberg is running | Print `.html` and `.htm` sources | PDF file is written atomically and reports `application/pdf` plus byte size only | Use `Bypass` to avoid real network |
| PDF-002 | P0 | Integration | Adapter | Markdown source prints to PDF through internal Markdown-to-HTML conversion | WorkArea Markdown source exists | Print `.md` with default behavior and with `print_raw_file: true` | Default path renders Markdown first; raw-file mode prints source text wrapper | No template execution |
| PDF-003 | P0 | Integration | Adapter | Text and image sources print through printable wrappers | `.txt`, `.png`, `.jpg`, `.jpeg`, and `.webp` sources exist | Print each supported source type | Each source converts through the expected wrapper and produces a PDF | Grouped compatibility coverage |
| PDF-004 | P1 | Integration | Adapter | Explicit header/footer/CSS paths are resolved and included | Explicit WorkArea assets exist | Print with `header_path`, `footer_path`, and `style_paths` | Explicit assets are used; CSS is attached without requiring source HTML to reference generated multipart names | Tests should inspect the Bypass request shape |
| PDF-005 | P1 | Integration | Adapter | Conventional sibling header/footer/CSS files and fallback precedence work correctly | Sibling assets and fallback env assets are prepared | Print with no explicit assets, then with explicit overrides | Explicit > conventional > fallback; missing conventional/fallback assets are ignored safely | Covers precedence contract |
| PDF-006 | P1 | Integration | Adapter | Fallback assets obey trust and size constraints | `priv/documents/` assets configured | Use missing, invalid extension, symlink, outside-root, and oversized fallback files | Safe ignore/reject behavior with no path or content leakage | Fallback paths never appear in results/logs |
| PDF-007 | P0 | Integration | Adapter | Remote asset references and CSS `@import` are blocked before backend call | Source or assets contain blocked references | Try `http://`, `https://`, protocol-relative URLs, `file://`, or `@import` | Returns structured validation error and Bypass receives no request | Must fail safely before Gotenberg |
| PDF-008 | P0 | Integration | Adapter | Existing PDF output is protected unless overwrite is true, and failure leaves no partial file | Output path may already exist | Print with and without overwrite; induce backend/write failure | Conflict is rejected when overwrite is false; failures do not leave partial final output | Atomic write regression |
| PDF-009 | P0 | Integration | Adapter | Source and output size limits are enforced before or during conversion | Configured max sizes in place | Use source over limit and simulated oversized PDF response | Source limit fails early; oversized PDF fails safely and is not written | Prevents runaway files |
| PDF-010 | P0 | Integration | Adapter | Backend non-2xx, timeout, connection failure, and retry behavior are safe | Bypass returns controlled statuses or drops connection | Simulate 500, timeout, and retryable failures | Non-2xx returns `tool.documents.pdf_conversion_failed`; unavailable/timeouts return `tool.documents.pdf_backend_unavailable`; only transient backend failures retry | Validation failures must not retry |
| PDF-011 | P0 | Integration | Adapter | Invalid paths, unsupported extensions, and missing explicit assets return safe structured errors | Bad paths or unsupported source/output assets | Provide invalid source/output/header/footer/style inputs | Errors are namespaced, WorkArea-relative in details, and do not leak host paths | Covers source/output/header/footer/style validation |
| OBS-001 | P1 | Integration | Observability | Logs and telemetry stay safe for document tool operations | Log capture and event assertions available | Run success and failure paths with sentinel content | Logs/events include IDs, event names, and safe summaries only; no contents, absolute paths, or backend bodies | Check markdown/html/pdf/fallback leak surfaces |
| CONF-001 | P1 | Unit | Config | Runtime env defaults and overrides parse correctly | Test env can mutate application config | Load defaults, override values, and supply invalid numeric envs | Defaults are applied, overrides parsed, invalid numeric envs fail clearly, and empty fallback envs are treated as unset | Confirms deployment contract |
| COMP-001 | P1 | Manual | Compose | Docker Compose keeps Gotenberg private and reachable only on the internal network | Compose file available | Review service image, exposure, network, and comments | `gotenberg/gotenberg:8`, internal exposure only, no host `ports`, shared private network, and default URL documented | Manual/static review only |

## Acceptance Criteria
- Tool catalog includes `documents.markdown_to_html` and `documents.print_to_pdf` (`CAT-001`).
- `documents.markdown_to_html` converts Markdown WorkArea files to HTML WorkArea files (`MD-001`, `MD-002`, `MD-003`).
- `documents.print_to_pdf` prints HTML WorkArea files to PDF WorkArea files (`PDF-001`).
- `documents.print_to_pdf` prints Markdown WorkArea files to PDF by internally converting Markdown to HTML (`PDF-002`).
- `documents.print_to_pdf` prints Markdown as raw text when `print_raw_file: true` (`PDF-002`).
- `documents.print_to_pdf` prints text WorkArea files to PDF (`PDF-003`).
- `documents.print_to_pdf` prints PNG, JPG, JPEG, and WEBP WorkArea files to PDF (`PDF-003`).
- Explicit `header_path`, `footer_path`, and `style_paths` are supported (`PDF-004`).
- Conventional sibling header/footer/CSS files are supported (`PDF-005`).
- Operator fallback header/footer/CSS env files are supported (`PDF-005`, `PDF-006`, `CONF-001`).
- Explicit paths override conventions, and conventions override env fallbacks (`PDF-005`).
- Operator fallback files are constrained to `priv/documents/`, regular files, valid extensions, and configured size limits (`PDF-006`).
- Remote asset references and CSS imports are blocked before calling Gotenberg (`PDF-007`).
- Absolute paths, traversal, Windows drive paths, and unsupported extensions are rejected (`WA-001`, `PDF-011`).
- Existing output files are protected unless `overwrite: true` (`PDF-008`).
- Generated HTML and PDF outputs use temp-file plus atomic rename and do not leave partial final files on failure (`MD-003`, `PDF-008`).
- Gotenberg is available in Docker Compose on a private internal network without a published host port (`COMP-001`).
- `documents.print_to_pdf` clearly returns `tool.documents.pdf_backend_unavailable` when Gotenberg is down (`PDF-010`).
- Gotenberg URL and limits are configurable through env-backed runtime config (`CONF-001`).
- Errors are structured, namespaced, and safe (`MD-002`, `PDF-007`, `PDF-010`, `PDF-011`).
- Logs/telemetry do not include document contents, unsafe paths, or backend response bodies (`OBS-001`).
- Tests cover catalog, adapter behavior, runtime dispatch, config parsing, Gotenberg success/failure, remote asset blocking, atomic writes, path safety, precedence, and size limits (`CAT-001`, `RUN-001` through `RUN-005`, `WA-001`, `MD-001` through `MD-003`, `PDF-001` through `PDF-011`, `CONF-001`, `OBS-001`).
- No artifact persistence or promotion is implemented in this ticket.

## Regression Checklist
- Use isolated temporary WorkAreas for every adapter and runtime test.
- Use `Bypass` for every Gotenberg interaction; do not depend on a real container.
- Assert that validation failures and blocked-asset failures make zero backend requests.
- Assert that output files are written atomically and cleaned up after forced failure paths.
- Assert that result payloads contain only WorkArea-relative paths and byte sizes.
- Assert that logs and telemetry do not contain fallback env file paths, absolute host paths, document contents, or backend response bodies.
- Run the narrow checks first: `mix test test/lemmings_os/tools/catalog_test.exs`, `mix test test/lemmings_os/tools/adapters/documents_test.exs`, and `mix test test/lemmings_os/tools/runtime_test.exs`.
- Then run config/compose review checks as applicable, followed by `mix format` and `mix precommit`.

## Out-of-scope
- UI or LiveView work.
- Artifact persistence, promotion, or download routes.
- Template execution, EEx, HEEx, Liquid, or any other executable document templating.
- Remote asset allowlisting or network access to third-party hosts.
- Pixel-perfect PDF visual comparison or browser automation.
- Public exposure of Gotenberg in default Compose.

## Execution Summary

### Work Performed
- Added a risk-ranked scenario matrix for the document tools feature.
- Mapped the plan acceptance criteria to concrete test layers and scenario IDs.
- Added explicit Bypass-only guidance for Gotenberg-backed tests.
- Added negative and security coverage for path traversal, symlinks, blocked assets, fallback constraints, size limits, and backend failures.

### Outputs Created
- Updated `llms/tasks/0012_print_to_pdf/01_document_tool_test_scenarios.md` with the completed scenario plan.

### Assumptions Made
- No PDF pixel-diff automation is required for this branch; success is validated through adapter/runtime behavior, output files, and safe metadata.
- Compose validation is a manual/static review rather than an executable test.
- Fallback env files are treated as deployment assets only and are never resolved through WorkArea logic.

### Decisions Made
- Grouped scenarios by risk and layer instead of by source file.
- Treated `Bypass` as mandatory for all Gotenberg coverage to keep tests deterministic and offline.
- Kept safety assertions focused on leaks, path boundaries, and atomicity rather than full HTML/CSS parsing correctness.

### Blockers
- None.

### Questions for Human
- Confirm whether the manual Compose review in `COMP-001` is sufficient, or whether you want a separate executable smoke test once Task 09 lands.

### Ready for Next Task
- [ ] Yes
- [x] No

## Human Review
Human reviewer confirms the scenario matrix is complete before Task 02 begins.
