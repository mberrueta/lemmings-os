defmodule LemmingsOs.MockData do
  @moduledoc """
  Static UI data used to render the mock management interface.
  """

  @cities [
    %{
      id: "city-alpha",
      name: "Alpha Node",
      description: "Primary production server with the busiest agent traffic.",
      region: "us-east-1",
      status: :online,
      accent: "#61e0ff",
      x: 24,
      y: 34
    },
    %{
      id: "city-beta",
      name: "Beta Node",
      description: "Research and model evaluation cluster for experiments.",
      region: "eu-west-1",
      status: :online,
      accent: "#f7cf4e",
      x: 54,
      y: 24
    },
    %{
      id: "city-gamma",
      name: "Gamma Node",
      description: "Support and edge automation cluster currently under load.",
      region: "ap-southeast-1",
      status: :degraded,
      accent: "#ff7be5",
      x: 78,
      y: 56
    }
  ]

  @departments [
    %{
      id: "eng",
      name: "Engineering",
      description: "Builds and maintains core infrastructure.",
      accent: "#61e0ff",
      city_id: "city-alpha",
      tasks_queue: ["Fix auth bug", "Deploy v2.1", "Code review PR #42"]
    },
    %{
      id: "research",
      name: "Research",
      description: "Explores new ideas and evaluates emerging models.",
      accent: "#f7cf4e",
      city_id: "city-beta",
      tasks_queue: ["Read RAG paper", "Benchmark models", "Write summary"]
    },
    %{
      id: "ops",
      name: "Operations",
      description: "Manages deployments, monitoring, and runtime health.",
      accent: "#ff7be5",
      city_id: "city-alpha",
      tasks_queue: ["Monitor uptime", "Scale cluster", "Rotate keys"]
    },
    %{
      id: "support",
      name: "Support",
      description: "Handles user tickets, triage, and knowledge flows.",
      accent: "#ff9b54",
      city_id: "city-gamma",
      tasks_queue: ["Reply to ticket #88", "Update FAQ", "Triage inbox"]
    }
  ]

  @lemmings [
    %{
      id: "lem-1",
      name: "Ada",
      role: "Backend Dev",
      current_task: "Fix auth bug",
      status: :running,
      model: "gpt-4o",
      department_id: "eng",
      accent: "#49f28e",
      system_prompt: "Focused on reliability, interfaces, and production-grade code.",
      tools: ["code_editor", "terminal", "git"],
      recent_messages: [
        %{role: :user, content: "Fix the JWT expiry issue", time: "14:32"},
        %{role: :assistant, content: "Found the refresh bug. Patching now.", time: "14:33"}
      ],
      activity_log: [
        %{action: "Started task: Fix auth bug", time: "14:30"},
        %{action: "Opened file: auth_controller.ex", time: "14:31"},
        %{action: "Running tests", time: "14:35"}
      ]
    },
    %{
      id: "lem-2",
      name: "Babbage",
      role: "Frontend Dev",
      current_task: "Deploy v2.1",
      status: :thinking,
      model: "claude-3.5",
      department_id: "eng",
      accent: "#61e0ff",
      system_prompt: "Turns visual systems into maintainable interfaces.",
      tools: ["code_editor", "browser", "figma"],
      recent_messages: [
        %{role: :user, content: "Prepare deploy checklist", time: "14:20"},
        %{role: :assistant, content: "Checking build status and release notes.", time: "14:21"}
      ],
      activity_log: [
        %{action: "Reviewing deploy pipeline", time: "14:18"},
        %{action: "Checking rollback strategy", time: "14:22"}
      ]
    },
    %{
      id: "lem-3",
      name: "Curie",
      role: "Researcher",
      current_task: "Read RAG paper",
      status: :running,
      model: "gpt-4o",
      department_id: "research",
      accent: "#f7cf4e",
      system_prompt: "Summarizes papers, compares approaches, and flags tradeoffs.",
      tools: ["web_search", "note_taker", "pdf_reader"],
      recent_messages: [
        %{role: :user, content: "Summarize the latest RAG improvements", time: "13:00"},
        %{
          role: :assistant,
          content: "Reading benchmark notes and paper highlights.",
          time: "13:01"
        }
      ],
      activity_log: [
        %{action: "Started reading paper", time: "13:00"},
        %{action: "Highlighted key findings", time: "13:15"}
      ]
    },
    %{
      id: "lem-4",
      name: "Darwin",
      role: "Data Analyst",
      current_task: "Benchmark models",
      status: :idle,
      model: "claude-3.5",
      department_id: "research",
      accent: "#ffb84d",
      system_prompt: "Analyzes model performance data and produces crisp reports.",
      tools: ["python", "charts", "database"],
      recent_messages: [],
      activity_log: [
        %{action: "Completed last benchmark run", time: "12:45"},
        %{action: "Waiting for next experiment", time: "12:50"}
      ]
    },
    %{
      id: "lem-5",
      name: "Euler",
      role: "DevOps",
      current_task: "Monitor uptime",
      status: :running,
      model: "gpt-4o-mini",
      department_id: "ops",
      accent: "#c47bff",
      system_prompt: "Monitors systems and responds to incidents quickly.",
      tools: ["grafana", "terminal", "pagerduty"],
      recent_messages: [
        %{role: :user, content: "Check system health", time: "14:00"},
        %{role: :assistant, content: "All systems nominal. CPU at 42%.", time: "14:01"}
      ],
      activity_log: [
        %{action: "Health check: OK", time: "14:00"},
        %{action: "Refreshing monitoring dashboard", time: "14:05"}
      ]
    },
    %{
      id: "lem-6",
      name: "Fermi",
      role: "SRE",
      current_task: "Scale cluster",
      status: :error,
      model: "gpt-4o",
      department_id: "ops",
      accent: "#ff6d7d",
      system_prompt: "Manages scaling and reliability under production pressure.",
      tools: ["kubernetes", "terraform", "terminal"],
      recent_messages: [
        %{role: :user, content: "Scale web pods to eight", time: "13:50"},
        %{
          role: :assistant,
          content: "Error: insufficient resources in zone us-east-1b",
          time: "13:51"
        }
      ],
      activity_log: [
        %{action: "Attempted scale-up", time: "13:50"},
        %{action: "Resource limit reached", time: "13:51"}
      ]
    },
    %{
      id: "lem-7",
      name: "Grace",
      role: "Support Agent",
      current_task: "Reply to ticket #88",
      status: :running,
      model: "gpt-4o-mini",
      department_id: "support",
      accent: "#ff9b54",
      system_prompt: "Handles customer issues with clear, empathetic replies.",
      tools: ["ticketing", "knowledge_base", "email"],
      recent_messages: [
        %{role: :user, content: "User cannot reset password", time: "14:10"},
        %{
          role: :assistant,
          content: "Checking account state and preparing a reset.",
          time: "14:11"
        }
      ],
      activity_log: [
        %{action: "Opened ticket #88", time: "14:10"},
        %{action: "Sending password reset", time: "14:12"}
      ]
    },
    %{
      id: "lem-8",
      name: "Hopper",
      role: "QA Tester",
      current_task: "Triage inbox",
      status: :thinking,
      model: "claude-3.5",
      department_id: "support",
      accent: "#ffb84d",
      system_prompt: "Categorizes incoming support work and flags regressions.",
      tools: ["ticketing", "classifier", "slack"],
      recent_messages: [],
      activity_log: [
        %{action: "Scanning inbox", time: "14:25"},
        %{action: "Reviewing priority assignment", time: "14:26"}
      ]
    }
  ]

  @tools [
    %{
      id: "code_editor",
      name: "code_editor",
      description: "Read and write code files",
      agents: 3,
      icon: "hero-code-bracket-square"
    },
    %{
      id: "terminal",
      name: "terminal",
      description: "Execute shell commands",
      agents: 3,
      icon: "hero-command-line"
    },
    %{
      id: "git",
      name: "git",
      description: "Version control operations",
      agents: 1,
      icon: "hero-arrow-path-rounded-square"
    },
    %{
      id: "web_search",
      name: "web_search",
      description: "Search the internet",
      agents: 1,
      icon: "hero-globe-alt"
    },
    %{
      id: "browser",
      name: "browser",
      description: "Inspect and navigate web pages",
      agents: 1,
      icon: "hero-window"
    },
    %{
      id: "database",
      name: "database",
      description: "Query and update data stores",
      agents: 1,
      icon: "hero-circle-stack"
    },
    %{
      id: "email",
      name: "email",
      description: "Send and read support mail",
      agents: 1,
      icon: "hero-envelope"
    },
    %{
      id: "slack",
      name: "slack",
      description: "Post messages into team channels",
      agents: 1,
      icon: "hero-chat-bubble-left-right"
    },
    %{
      id: "grafana",
      name: "grafana",
      description: "Monitor cluster metrics",
      agents: 1,
      icon: "hero-chart-bar-square"
    },
    %{
      id: "kubernetes",
      name: "kubernetes",
      description: "Manage orchestration workloads",
      agents: 1,
      icon: "hero-server-stack"
    }
  ]

  @global_activity_log [
    %{agent: "Ada", action: "Started task: Fix auth bug", time: "14:30", type: :task},
    %{agent: "Babbage", action: "Reviewing deploy pipeline", time: "14:18", type: :task},
    %{agent: "Fermi", action: "Resource limit reached", time: "13:51", type: :error},
    %{agent: "Grace", action: "Opened ticket #88", time: "14:10", type: :task},
    %{agent: "Curie", action: "Highlighted key findings", time: "13:15", type: :task},
    %{agent: "Euler", action: "Health check: OK", time: "14:00", type: :system},
    %{agent: "Hopper", action: "Scanning inbox", time: "14:25", type: :task},
    %{agent: "Darwin", action: "Completed last benchmark run", time: "12:45", type: :task},
    %{agent: "System", action: "Operations shell v0.1 booted", time: "12:00", type: :system},
    %{agent: "System", action: "All departments initialized", time: "12:01", type: :system}
  ]

  def cities, do: @cities
  def departments, do: @departments
  def lemmings, do: @lemmings
  def tools, do: @tools
  def global_activity_log, do: @global_activity_log

  def summary do
    %{
      version: "0.1.0",
      mem: "64MB",
      tick: 1337,
      cpu: "42%",
      max_agents: 16,
      agents_count: length(@lemmings),
      active_agents_count: Enum.count(@lemmings, &(&1.status in [:running, :thinking])),
      cities_count: length(@cities),
      online_cities_count: Enum.count(@cities, &(&1.status == :online)),
      departments_count: length(@departments),
      tools_count: length(@tools)
    }
  end

  def find_city(nil), do: nil
  def find_city(id), do: Enum.find(@cities, &(&1.id == id))

  def find_department(nil), do: nil
  def find_department(id), do: Enum.find(@departments, &(&1.id == id))

  def find_lemming(nil), do: nil
  def find_lemming(id), do: Enum.find(@lemmings, &(&1.id == id))

  def departments_for_city(city_id), do: Enum.filter(@departments, &(&1.city_id == city_id))

  def lemmings_for_department(department_id),
    do: Enum.filter(@lemmings, &(&1.department_id == department_id))

  def lemmings_for_city(city_id) do
    city_id
    |> departments_for_city()
    |> Enum.map(& &1.id)
    |> then(fn department_ids ->
      Enum.filter(@lemmings, &(&1.department_id in department_ids))
    end)
  end

  def city_for_department(department_id) do
    case find_department(department_id) do
      %{city_id: city_id} -> find_city(city_id)
      _ -> nil
    end
  end

  def department_for_lemming(lemming_id) do
    case find_lemming(lemming_id) do
      %{department_id: department_id} -> find_department(department_id)
      _ -> nil
    end
  end

  def recent_activity(limit \\ 6), do: Enum.take(@global_activity_log, limit)

  def active_lemmings(limit \\ 4),
    do: @lemmings |> Enum.filter(&(&1.status in [:running, :thinking])) |> Enum.take(limit)
end
