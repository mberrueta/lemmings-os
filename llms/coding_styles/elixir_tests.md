# LemmingsOS — Testing Guidelines (ExUnit, Ecto, OTP, LiveView)

> Fast, isolated, descriptive. Prefer pattern-matching assertions and explicit failure cases.

## 0) Test Types

- **Unit**: pure modules, no DB, no processes.
- **DataCase**: DB-backed contexts/schemas (uses SQL Sandbox).
- **ConnCase**: HTTP controllers/plugs.
- **LiveViewCase**: LiveView interactions, HEEx rendering.
- **OTP tests**: process lifecycle, supervision trees (use `start_supervised/1`).
- **Integration**: happy-path flows across layers.

## 1) Structure & Naming

- One `describe` per function/behavior; meaningful test names.
- Use factories as the default test-data mechanism; avoid `*_fixture` helpers and fixture-style naming.
- Never seed data with raw SQL in tests.
- Always pass `world_id` explicitly in context calls — no implicit global scope.

```elixir
# test/lemmings_os/department_test.exs
defmodule LemmingsOs.DepartmentTest do
  use LemmingsOs.DataCase, async: true
  import LemmingsOs.Factory

  describe "create/2" do
    test "creates a department scoped to the world" do
      world = insert(:world)
      attrs = %{name: "Ops", city_id: insert(:city, world: world).id}

      assert {:ok, dept} = Department.create(attrs, world.id)
      assert dept.world_id == world.id
    end

    test "returns changeset error on duplicate name within a city" do
      world = insert(:world)
      city = insert(:city, world: world)
      insert(:department, name: "Ops", city: city, world: world)

      assert {:error, %Ecto.Changeset{}} =
               Department.create(%{name: "Ops", city_id: city.id}, world.id)
    end
  end
end
```

## 2) ExMachina Factories

- Centralize valid attrs; override per test.
- Prefer `build/2` + `insert/2` over hand-built structs.
- Factories for World-scoped entities MUST include `world_id` by default.

```elixir
# test/support/factory.ex
defmodule LemmingsOs.Factory do
  use ExMachina.Ecto, repo: LemmingsOs.Repo

  def world_factory do
    %LemmingsOs.World.Schema{
      name: sequence(:world_name, &"world-#{&1}")
    }
  end

  def city_factory do
    %LemmingsOs.City.Schema{
      world: build(:world),
      name: sequence(:city_name, &"city-#{&1}"),
      node_name: sequence(:node, &"node#{&1}@localhost")
    }
  end

  def lemming_factory do
    %LemmingsOs.Lemming.Schema{
      department: build(:department),
      city: build(:city),
      world: build(:world),
      status: :stopped,
      agent_module: "LemmingsOs.Agents.NoOp"
    }
  end
end
```

## 3) Pattern-Matching Assertions

- Assert on typed tuples and struct fields.
- Avoid string contains for behavior validation.

```elixir
assert {:ok, %LemmingsOs.Lemming.Schema{id: id}} = Lemming.create(attrs, world.id)
refute is_nil(id)
```

## 4) OTP / Process Tests

- Use `start_supervised/1` for all process tests — never start processes manually in tests.
- Assert process state via explicit calls, not `Process.sleep/1`.
- Test supervision restart behavior with `Process.exit(pid, :kill)` + `assert_receive`.

```elixir
defmodule LemmingsOs.Lemming.ExecutorTest do
  use ExUnit.Case, async: true
  import LemmingsOs.Factory

  test "restarts after crash" do
    lemming = build(:lemming, id: Ecto.UUID.generate())
    {:ok, pid} = start_supervised({LemmingsOs.Lemming.Executor, lemming})

    Process.exit(pid, :kill)
    # give supervisor one scheduling cycle
    :timer.sleep(10)

    assert Process.alive?(GenServer.whereis(LemmingsOs.Lemming.Executor.via_tuple(lemming.id)))
  end
end
```

## 5) LiveView Tests

- Use `live(conn, ~p"/path")`, `element/2`, `render_click/1`, `render_change/1`.
- Assert navigation with `assert_patch`/`assert_redirect`.

```elixir
use LemmingsOsWeb.ConnCase

setup :register_and_log_in_user

test "displays department list" do
  world = insert(:world)
  insert(:department, name: "Ops", world: world)

  {:ok, view, _html} = live(conn, ~p"/worlds/#{world.id}/departments")
  assert has_element?(view, "[data-department-name]", "Ops")
end
```

## 6) HTTP & External Services

- Use **Bypass** for HTTP servers (e.g., LLM API stubs).
- Use **Mox** for behaviours (declare `@behaviour` in client modules).

```elixir
setup do
  bypass = Bypass.open()
  Application.put_env(:lemmings_os, :llm_base_url, "http://localhost:#{bypass.port}")
  {:ok, bypass: bypass}
end

test "calls LLM and parses response", %{bypass: bypass} do
  Bypass.expect(bypass, fn conn ->
    Plug.Conn.resp(conn, 200, ~s({"result":"ok"}))
  end)
  assert {:ok, %{"result" => "ok"}} = LemmingsOs.LLM.Client.call("prompt")
end
```

## 7) Sandbox, Concurrency & Timing

- `DataCase` defaults to SQL Sandbox; set `async: true` when possible.
- Avoid `Process.sleep/1`; use `assert_receive` with timeouts.
- For telemetry assertions, attach a test handler with `telemetry_subscribe/2` and
  use `assert_receive`.

```elixir
send(self(), {:done, 1})
assert_receive {:done, 1}, 50
```

## 8) Test Helpers

- Put helpers in `test/support/*.ex`.
- If asserting HTML, use Floki selectors and roles/labels rather than class names.

```elixir
import Floki, only: [find: 2, text: 1]
html = render(view)
assert html |> find("[role=heading]") |> text() =~ "Ops"
```

## 9) CI Expectations

- Keep tests fast (< 5s ideally for unit; < 30s for OTP integration).
- No external network in tests. Use Bypass or Mox.
- No sleeps > 50ms.
- Coverage goal: pragmatic; prefer meaningful tests over raw percentage.
