# Task 06: Header Footer CSS Resolution

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for adapter behavior, filesystem validation, and safe configuration handling.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add header, footer, CSS, conventional sibling, and operator fallback resolution to `documents.print_to_pdf`.

## Objective
Implement the precedence model for explicit WorkArea assets, conventional WorkArea siblings, and operator-configured fallback files under `priv/documents/`.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Completed Tasks 01 through 05
- [X] Documents config from Task 02
- [X] Documents adapter tests from Tasks 04 and 05

## Expected Outputs
- [X] Explicit `header_path`, `footer_path`, and `style_paths` resolve through `WorkArea.resolve/2`.
- [X] Conventional sibling files are discovered by source basename when explicit paths are absent.
- [X] Operator fallback header/footer/CSS files are used only when explicit and conventional files are absent.
- [X] Fallback files must live under `priv/documents/`, be regular files, reject symlinks, pass extension checks, and pass size checks.
- [X] Missing explicit assets fail with `tool.documents.asset_not_found`.
- [X] Missing conventional and fallback assets are ignored safely.
- [X] Invalid fallback extensions, oversized fallback files, and fallback symlinks are ignored safely with safe logs.
- [X] Explicit assets override conventional assets; conventional assets override fallback assets.
- [X] CSS files are included in the Gotenberg request or injected into generated print HTML without requiring source HTML to reference generated multipart names.

## Acceptance Criteria
- [X] Fallback paths and contents are absent from tool results.
- [X] Logs do not include fallback env file paths, absolute paths, or file contents.
- [X] Header/footer files must be `.html` or `.htm`; CSS files must be `.css`.
- [X] Tests cover each precedence branch and each rejected fallback condition.

## Technical Notes
- Agent-controlled WorkArea assets and operator fallback files have different trust boundaries. Keep their resolution paths separate.
- Fallback env files are deployment assets and must not go through `WorkArea.resolve/2`.
- Use regular file checks that do not follow symlinks for fallback rejection.

## Execution Instructions
1. Read Tasks 04 and 05 implementation before modifying adapter behavior.
2. Implement resolution in small helpers with clear precedence.
3. Add focused tests for explicit, conventional, fallback, missing, invalid, symlink, oversized, and precedence cases.
4. Run:
   ```text
   mix test test/lemmings_os/tools/adapters/documents_test.exs
   mix format
   ```
5. Record commands and results in this task file.

## Execution Summary

### Work Performed
- [X] Extended `documents.print_to_pdf` argument contract with `header_path`, `footer_path`, and `style_paths`.
- [X] Implemented explicit WorkArea asset resolution for header/footer/style files via `WorkArea.resolve/2`.
- [X] Implemented conventional sibling discovery:
  - `<basename>_pdf_header.html`
  - `<basename>_pdf_footer.html`
  - `<basename>_pdf.css`
- [X] Implemented operator fallback asset resolution using `:documents` config values, with trust-boundary checks:
  - must resolve under `priv/documents/`
  - must be regular files via `File.lstat/1`
  - symlinks rejected
  - extension checks (`.html`/`.htm` for header/footer, `.css` for styles)
  - size check against `max_fallback_bytes`
- [X] Added safe fallback rejection logging without exposing fallback file paths or contents.
- [X] Implemented precedence:
  - explicit > conventional > fallback
- [X] Included resolved assets in Gotenberg multipart (`header.html`, `footer.html`, `style-N.css`).
- [X] Injected resolved CSS content into main HTML so source HTML does not need to reference generated multipart style filenames.

### Outputs Created
- [X] Updated `lib/lemmings_os/tools/adapters/documents.ex`
- [X] Updated `test/lemmings_os/tools/adapters/documents_test.exs`

### Assumptions Made
- [X] For Task 06, conventional/fallback missing assets are non-fatal and silently skipped (except safe warning logs for invalid fallback files).
- [X] If header/footer content is not a full HTML document, adapter wraps it conservatively for Gotenberg compatibility.

### Decisions Made
- [X] Used `tool.documents.asset_not_found` only for explicit missing assets to preserve strict agent-input failure behavior.
- [X] Kept fallback trust-boundary checks entirely separate from WorkArea path resolution.
- [X] Kept fallback rejection logs reason-only (`outside_root`, `invalid_extension`, `symlink`, `not_regular`, `too_large`, `unreadable`) with no path/content leakage.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- [X] `mix format lib/lemmings_os/tools/adapters/documents.ex test/lemmings_os/tools/adapters/documents_test.exs llms/tasks/0012_print_to_pdf/06_header_footer_css_resolution.md` (success)
- [X] `mix test test/lemmings_os/tools/adapters/documents_test.exs` (success; 20 tests, 0 failures)
- [X] `mix test test/lemmings_os/tools/runtime_test.exs` (success; 15 tests, 0 failures)

## Human Review
Human reviewer confirms asset precedence and fallback trust boundaries before Task 07 begins.
