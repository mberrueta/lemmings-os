# Task 06: Header Footer CSS Resolution

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for adapter behavior, filesystem validation, and safe configuration handling.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add header, footer, CSS, conventional sibling, and operator fallback resolution to `documents.print_to_pdf`.

## Objective
Implement the precedence model for explicit WorkArea assets, conventional WorkArea siblings, and operator-configured fallback files under `priv/documents/`.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 05
- [ ] Documents config from Task 02
- [ ] Documents adapter tests from Tasks 04 and 05

## Expected Outputs
- [ ] Explicit `header_path`, `footer_path`, and `style_paths` resolve through `WorkArea.resolve/2`.
- [ ] Conventional sibling files are discovered by source basename when explicit paths are absent.
- [ ] Operator fallback header/footer/CSS files are used only when explicit and conventional files are absent.
- [ ] Fallback files must live under `priv/documents/`, be regular files, reject symlinks, pass extension checks, and pass size checks.
- [ ] Missing explicit assets fail with `tool.documents.asset_not_found`.
- [ ] Missing conventional and fallback assets are ignored safely.
- [ ] Invalid fallback extensions, oversized fallback files, and fallback symlinks are ignored safely with safe logs.
- [ ] Explicit assets override conventional assets; conventional assets override fallback assets.
- [ ] CSS files are included in the Gotenberg request or injected into generated print HTML without requiring source HTML to reference generated multipart names.

## Acceptance Criteria
- [ ] Fallback paths and contents are absent from tool results.
- [ ] Logs do not include fallback env file paths, absolute paths, or file contents.
- [ ] Header/footer files must be `.html` or `.htm`; CSS files must be `.css`.
- [ ] Tests cover each precedence branch and each rejected fallback condition.

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
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer confirms asset precedence and fallback trust boundaries before Task 07 begins.
