# Web / LiveView rules

- Use HEEx only.
- Start LiveView pages with `<Layouts.app flash={@flash} ...>`.
- Use `to_form/2` and `<.form for={@form}>`.
- Use `<.input>` for form fields.
- Add stable DOM IDs for tests.
- Use LiveView streams for large or dynamic collections.
- Do not use `Enum.each` in templates; use `<%= for ... do %>`.
- Use HEEx comments: `<%!-- comment --%>`.
- Use `phx-no-curly-interpolation` for literal `{}` inside code snippets.
- Do not use embedded `<script>` tags.
