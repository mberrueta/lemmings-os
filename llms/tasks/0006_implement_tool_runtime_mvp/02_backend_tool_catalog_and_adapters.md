# Task 02: Backend Tool Catalog And Adapters

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the fixed Tool Runtime catalog and MVP tool adapters.

## Objective
Implement the fixed four-tool catalog and the backend execution support for `fs.read_text_file`, `fs.write_text_file`, `web.search`, and `web.fetch`.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Task 01 outputs
- [ ] Existing `lib/lemmings_os/tools/` registry seam
- [ ] Existing runtime/config conventions

## Expected Outputs

- [ ] Fixed global tool catalog for this PR
- [ ] Structured arg validation and normalized success/error handling for the four approved tools
- [ ] Backend adapters for filesystem and web tools using project conventions

## Acceptance Criteria

- [ ] Only the four approved tools are executable
- [ ] Filesystem tools enforce workspace-relative paths
- [ ] Web tools use `Req`
- [ ] Success and error outcomes are normalized consistently
- [ ] The runtime-facing catalog can be reused by the tools page later

## Technical Notes

### Constraints
- No `exec.run`
- No shell execution path
- No catalog expansion beyond the approved four tools

## Execution Instructions

### For the Agent
1. Implement the fixed catalog definition.
2. Implement adapters and arg validation for the four approved tools.
3. Keep the result/error contract stable enough for executor/UI use.

### For the Human Reviewer
1. Verify only four tools are present.
2. Verify `Req` is used for web behavior.
3. Verify path handling remains within `/workspace`.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
