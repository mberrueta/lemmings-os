defmodule LemmingsOsWeb.Telemetry do
  use Supervisor
  import Ecto.Query, warn: false
  import Telemetry.Metrics

  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Repo

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller,
       measurements: periodic_measurements(), period: 10_000, init_delay: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("lemmings_os.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("lemmings_os.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("lemmings_os.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("lemmings_os.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("lemmings_os.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Runtime metrics
      last_value("lemmings_os.runtime.instances.total"),
      last_value("lemmings_os.runtime.instances.created"),
      last_value("lemmings_os.runtime.instances.queued"),
      last_value("lemmings_os.runtime.instances.processing"),
      last_value("lemmings_os.runtime.instances.retrying"),
      last_value("lemmings_os.runtime.instances.idle"),
      last_value("lemmings_os.runtime.instances.failed"),
      last_value("lemmings_os.runtime.instances.expired"),
      sum("lemmings_os.runtime.session.spawn.count"),
      sum("lemmings_os.runtime.session.recovered.count"),
      sum("lemmings_os.runtime.tool_execution.started.count"),
      sum("lemmings_os.runtime.tool_execution.completed.count"),
      sum("lemmings_os.runtime.tool_execution.failed.count"),
      summary("lemmings_os.runtime.tool_execution.completed.duration_ms"),
      summary("lemmings_os.runtime.tool_execution.failed.duration_ms"),
      last_value("lemmings_os.runtime.lemming_calls.total"),
      last_value("lemmings_os.runtime.lemming_calls.accepted"),
      last_value("lemmings_os.runtime.lemming_calls.running"),
      last_value("lemmings_os.runtime.lemming_calls.needs_more_context"),
      last_value("lemmings_os.runtime.lemming_calls.partial_result"),
      last_value("lemmings_os.runtime.lemming_calls.completed"),
      last_value("lemmings_os.runtime.lemming_calls.failed"),
      sum("lemmings_os.runtime.lemming_call.created.count"),
      sum("lemmings_os.runtime.lemming_call.started.count"),
      sum("lemmings_os.runtime.lemming_call.status_changed.count"),
      sum("lemmings_os.runtime.lemming_call.completed.count"),
      sum("lemmings_os.runtime.lemming_call.failed.count"),
      sum("lemmings_os.runtime.lemming_call.recovery_pending.count"),
      sum("lemmings_os.runtime.lemming_call.recovered.count"),
      sum("lemmings_os.runtime.lemming_call.dead.count"),
      summary("lemmings_os.runtime.lemming_call.completed.duration_ms"),
      summary("lemmings_os.runtime.lemming_call.failed.duration_ms"),
      summary("lemmings_os.runtime.lemming_call.dead.duration_ms"),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [{__MODULE__, :emit_runtime_snapshot, []}]
  end

  def emit_runtime_snapshot do
    measurements = runtime_instance_measurements()
    call_measurements = runtime_lemming_call_measurements()

    :telemetry.execute([:lemmings_os, :runtime, :instances], measurements, %{
      source: :poller
    })

    :telemetry.execute([:lemmings_os, :runtime, :lemming_calls], call_measurements, %{
      source: :poller
    })
  end

  defp runtime_instance_measurements do
    try do
      base_query =
        from(instance in LemmingInstance,
          group_by: instance.status,
          select: %{status: instance.status, count: count(instance.id)}
        )

      counts =
        Repo.all(base_query)
        |> Map.new(fn %{status: status, count: count} -> {status, count} end)

      %{
        total: Enum.reduce(counts, 0, fn {_status, count}, acc -> acc + count end),
        created: Map.get(counts, "created", 0),
        queued: Map.get(counts, "queued", 0),
        processing: Map.get(counts, "processing", 0),
        retrying: Map.get(counts, "retrying", 0),
        idle: Map.get(counts, "idle", 0),
        failed: Map.get(counts, "failed", 0),
        expired: Map.get(counts, "expired", 0)
      }
    rescue
      _ ->
        %{
          total: 0,
          created: 0,
          queued: 0,
          processing: 0,
          retrying: 0,
          idle: 0,
          failed: 0,
          expired: 0
        }
    end
  end

  defp runtime_lemming_call_measurements do
    try do
      base_query =
        from(call in LemmingCall,
          group_by: call.status,
          select: %{status: call.status, count: count(call.id)}
        )

      counts =
        Repo.all(base_query)
        |> Map.new(fn %{status: status, count: count} -> {status, count} end)

      %{
        total: Enum.reduce(counts, 0, fn {_status, count}, acc -> acc + count end),
        accepted: Map.get(counts, "accepted", 0),
        running: Map.get(counts, "running", 0),
        needs_more_context: Map.get(counts, "needs_more_context", 0),
        partial_result: Map.get(counts, "partial_result", 0),
        completed: Map.get(counts, "completed", 0),
        failed: Map.get(counts, "failed", 0)
      }
    rescue
      _ ->
        %{
          total: 0,
          accepted: 0,
          running: 0,
          needs_more_context: 0,
          partial_result: 0,
          completed: 0,
          failed: 0
        }
    end
  end
end
