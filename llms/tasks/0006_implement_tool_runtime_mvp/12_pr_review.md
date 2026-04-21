# Task 12: PR Review

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir`

## Agent Invocation
Act as `audit-pr-elixir` following `llms/constitution.md` and perform the final PR review for Tool Runtime MVP on `feat/0006_tool_runtime_mvp`.

## Objective
Review the full branch after implementation, tests, and ADR updates are complete, and issue an approve/request-changes verdict.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Tasks 01 through 11 outputs
- [ ] Full branch diff

## Expected Outputs

- [ ] Final PR review with findings and verdict

## Acceptance Criteria

- [ ] Review verifies the branch remains within the four-tool MVP slice
- [ ] Review verifies runtime correctness, workspace boundary safety, transcript visibility, observability, and test coverage
- [ ] Review verifies ADR/docs align with shipped behavior
- [ ] Findings are concrete and actionable

## Execution Instructions

### For the Agent
1. Review the branch against the plan and all task outputs.
2. Report findings by severity.
3. Issue a final verdict.

### For the Human Reviewer
1. Review the findings and verdict.
2. Decide whether the branch is ready for merge or needs follow-up work.

---

## Execution Summary
### Summary
- Branch stays inside the fixed four-tool MVP execution catalog: `fs.read_text_file`, `fs.write_text_file`, `web.search`, and `web.fetch`.
- Direct executor-to-tool-runtime call path is implemented; PubSub remains a UI notification path, not the execution mechanism.
- Durable tool execution history, transcript tool cards, runtime telemetry, metrics, and ADR updates are present.
- Blocker follow-up fixed workspace/artifact symlink escapes and added regression tests.
- Artifact endpoint follow-up changed artifact responses to download-only binary responses with `nosniff`.
- Web egress follow-up added default private-host blocking, explicit Req timeouts, and no-retry behavior.
- `mix precommit` passed after blocker, artifact, and web egress hardening fixes on 2026-04-21.

### Risk assessment
**Low-to-medium** after follow-up fixes. The MVP tool boundary now has workspace symlink rejection, download-only artifact responses, and default web egress blocking for loopback/private/link-local host targets. Residual risk remains around future policy sophistication and DNS-based egress controls.

### BLOCKER

None open after blocker follow-up.

### RESOLVED

#### Filesystem tools can follow symlinks outside the work area
- **Where**: `lib/lemmings_os/tools/adapters/filesystem.ex`, `lib/lemmings_os/lemming_instances.ex`
- **Resolution**: Workspace root paths are expanded before work-area resolution, and existing path components are checked with `File.lstat/1`; symlink components now return `tool.fs.path_outside_workspace` or `:path_outside_workspace` before file IO.
- **Tests added**: `test/lemmings_os/tools/adapters/filesystem_test.exs` covers read symlink, write symlink, and symlink parent directory escapes. `test/lemmings_os_web/live/instance_live_test.exs` covers artifact download via symlink.

#### Artifact endpoint serves generated files inline with sniffed content type
- **Where**: `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`, `show/2`
- **Resolution**: Artifact responses now use `content-type: application/octet-stream`, `content-disposition: attachment`, and `x-content-type-options: nosniff`.
- **Tests added**: `test/lemmings_os_web/live/instance_live_test.exs` covers `.md`, `.html`, and `.svg` artifact downloads and asserts non-inline headers.

#### Web fetch has no network egress guardrails
- **Where**: `lib/lemmings_os/tools/adapters/web.ex`, `validate_http_url/1`, `request_fetch/1`, `request_search/1`
- **Resolution**: Fetch URLs and configured search endpoints now reject localhost, `.localhost`, loopback, private, link-local, and selected reserved IP literal targets by default. Tests can opt into private hosts via `:tools_web_allow_private_hosts`. Req calls now use configured `:tools_web_timeout_ms`, `receive_timeout`, `connect_options`, and `retry: false`.
- **Tests added**: `test/lemmings_os/tools/adapters/web_test.exs` covers blocked fetch hosts, blocked private search endpoints, and timeout normalization. `test/lemmings_os/tools/runtime_test.exs` opts into private hosts for Bypass-backed runtime tests.

### MAJOR

None open.

### MINOR

#### Raw context page is larger than the stated transcript MVP
- **Where**: `lib/lemmings_os_web/live/instance_raw_live.ex`, `lib/lemmings_os_web/router.ex`
- **Why it matters**: The page is useful, but it exposes raw prompt/config/runtime internals and was not called out in the four-tool MVP plan. That increases review and privacy surface.
- **Suggested fix**: Either document it explicitly in Task 11/ADRs as delivered behavior and keep it operator-only, or defer the route to a follow-up PR.

### NITS
- None blocking.

### Test coverage notes
- Good coverage exists for persistence, executor loop, telemetry, tool cards, tools page, and basic path traversal.
- Added coverage for symlink escapes, artifact active-content response headers, and web egress blocking/timeout behavior.

### Observability notes
- Lifecycle logs, telemetry, metrics, activity log records, and PubSub updates are present.
- Web egress blocking now returns stable `tool.web.egress_blocked`; timeouts normalize through `tool.web.request_failed`.

### Merge recommendation
**COMMENT_ONLY**. The previously identified BLOCKER and MAJOR findings have been addressed; remaining risk is acceptable for the fixed four-tool MVP if maintainers are comfortable deferring deeper DNS/policy egress controls.

## Human Review
*[Filled by human reviewer]*
