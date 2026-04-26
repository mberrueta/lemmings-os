defmodule LemmingsOs.LemmingInstances.Executor.CommunicationTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.Communication
  alias LemmingsOs.ModelRuntime.Response

  doctest Communication

  defmodule FakeCalls do
    def request_call(_instance, attrs, _opts),
      do: {:ok, %{id: "call-1", request_text: attrs.request}}

    def available_targets(_instance), do: [%{slug: "ops-worker"}]

    def list_manager_calls(_instance, opts) do
      case Keyword.get(opts, :statuses, []) do
        ["accepted" | _rest] -> [%{id: "pending-1"}]
        _other -> []
      end
    end

    def sync_child_instance_terminal(_instance, _status, _attrs), do: :ok
  end

  defmodule RejectingCalls do
    def request_call(_instance, _attrs, _opts), do: {:error, :not_allowed}
  end

  test "request_call/3 returns unavailable when module is nil or missing function" do
    response =
      Response.new(
        action: :lemming_call,
        lemming_target: "ops-worker",
        lemming_request: "Draft notes"
      )

    assert {:error, :lemming_call_unavailable} = Communication.request_call(nil, %{}, response)

    assert {:error, :lemming_call_unavailable} =
             Communication.request_call(__MODULE__, %{}, response)
  end

  test "request_call/3 normalizes success and failure shapes" do
    response =
      Response.new(
        action: :lemming_call,
        lemming_target: "ops-worker",
        lemming_request: "Draft notes"
      )

    assert {:ok, %{target: "ops-worker", request: "Draft notes"}, %{id: "call-1"}} =
             Communication.request_call(FakeCalls, %{id: "instance-1"}, response)

    assert {:error, {:lemming_call_failed, :not_allowed}} =
             Communication.request_call(RejectingCalls, %{id: "instance-1"}, response)
  end

  test "available_targets/2 returns empty list when unsupported" do
    assert [] = Communication.available_targets(nil, %{id: "instance-1"})
    assert [] = Communication.available_targets(__MODULE__, %{id: "instance-1"})

    assert [%{slug: "ops-worker"}] =
             Communication.available_targets(FakeCalls, %{id: "instance-1"})
  end

  test "put_targets_in_config/2 sets target list only when non-empty" do
    config = %{model: "m"}
    assert %{model: "m"} = Communication.put_targets_in_config(config, [])

    assert %{model: "m", lemming_call_targets: [%{slug: "ops-worker"}]} =
             Communication.put_targets_in_config(config, [%{slug: "ops-worker"}])
  end

  test "pending_manager_calls?/2 follows list_manager_calls status filter" do
    assert Communication.pending_manager_calls?(FakeCalls, %{id: "manager-1"})
    refute Communication.pending_manager_calls?(nil, %{id: "manager-1"})
    refute Communication.pending_manager_calls?(__MODULE__, %{id: "manager-1"})
  end

  test "child terminal helpers preserve sync decision and payload shaping" do
    assert :skip = Communication.child_terminal_sync_decision("idle", true)
    assert :sync = Communication.child_terminal_sync_decision("idle", false)
    assert :sync = Communication.child_terminal_sync_decision("failed", true)
    assert :skip = Communication.child_terminal_sync_decision("processing", false)

    attrs =
      Communication.child_terminal_sync_attrs(
        "idle",
        [%{role: "assistant", content: "final summary"}],
        "last error",
        ~U[2026-04-26 14:00:00Z]
      )

    assert attrs.result_summary == "final summary"
    assert attrs.error_summary == "last error"
    assert attrs.completed_at == ~U[2026-04-26 14:00:00Z]
  end

  test "resume helpers normalize rejection and reset runtime fields" do
    assert :terminal_instance =
             Communication.resume_rejection_reason("failed", %{id: "item-1"}, nil)

    assert :resume_not_possible =
             Communication.resume_rejection_reason("idle", nil, nil)

    assert :resume_not_possible =
             Communication.resume_rejection_reason("idle", %{id: "item-1"}, self())

    assert is_nil(Communication.resume_rejection_reason("idle", %{id: "item-1"}, nil))

    state = %{
      context_messages: [%{role: "user", content: "Delegate this"}],
      retry_count: 2,
      last_error: "boom",
      internal_error_details: %{kind: :model_timeout}
    }

    call = %{status: "completed", result_summary: "Done"}

    updated = Communication.prepare_state_for_resume(state, call)

    assert updated.retry_count == 0
    assert updated.last_error == nil
    assert updated.internal_error_details == nil
    assert length(updated.context_messages) == 2
    assert String.contains?(List.last(updated.context_messages).content, "Lemming call result:")
  end
end
