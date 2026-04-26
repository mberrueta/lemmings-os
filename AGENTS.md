# AGENTS.md

This is a Phoenix 1.8 / Elixir application.

## Working mode

- Act as a senior Elixir/Phoenix engineer.
- Prefer small, focused changes over broad rewrites.
- Inspect existing code before changing behavior.
- Do not add dependencies unless explicitly requested.
- When done, run the narrowest relevant checks first, then `mix precommit` when the change is complete.

## Project commands

- Format: `mix format`
- Tests: `mix test`
- Failed tests only: `mix test --failed`
- Final validation: `mix precommit`
- Use `mix help <task>` before unfamiliar Mix tasks.
- Avoid `mix deps.clean --all` unless there is a clear dependency corruption issue.

## Elixir conventions

- Do not use `String.to_atom/1` on user input.
- Do not use map access syntax on structs.
- Use `Ecto.Changeset.get_field/2` for changeset field access.
- Do not nest multiple modules in the same file.
- Predicate functions should end with `?`; reserve `is_*` for guards.
- For indexed list access, use pattern matching, `Enum.at/2`, or `List`, not `list[index]`.
- For concurrent enumeration, prefer `Task.async_stream/3` with back-pressure.

## Phoenix / LiveView conventions

- LiveView templates must be HEEx: `~H` or `.html.heex`.
- Begin LiveView pages with `<Layouts.app flash={@flash} ...>`.
- Pass `current_scope` correctly through authenticated LiveViews.
- Do not call `<.flash_group>` outside `layouts.ex`.
- Use imported `<.icon>`; do not use `Heroicons` modules directly.
- Use imported `<.input>` where possible.
- Use `to_form/2` and `<.form for={@form}>`; do not pass changesets directly to templates.
- Add stable DOM IDs to forms, buttons, and key UI elements.
- Use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate`, and `push_patch`; avoid deprecated LiveView navigation helpers.
- Do not embed `<script>` tags in HEEx. Put hooks/scripts under `assets/js`.

## Ecto conventions

- Preload associations before accessing them in templates.
- Use `:string` for schema fields, including text columns.
- Do not use `allow_nil` with `validate_number/2`.
- Do not cast programmatically assigned fields such as `user_id`; set them explicitly.

## HTTP

- Use the existing `Req` library.
- Do not introduce `:httpoison`, `:tesla`, or `:httpc`.

## Testing

- Prefer outcome-based tests.
- For LiveView tests, use `Phoenix.LiveViewTest` selectors such as `element/2` and `has_element?/2`.
- Avoid assertions against large raw HTML.
- Use stable DOM IDs from templates in tests.
- Add doctests for public modules when examples clarify usage.
